import Foundation

// MARK: - AppleScript Execution

/// Result of running an AppleScript.
enum AppleScriptResult {
  case success(String)
  case error(MailPluginError, String)
}

/// Execute an AppleScript source string and return the result.
///
/// Uses `Process` with `/usr/bin/osascript` for execution.
/// Maps common Apple Mail errors to `MailPluginError` codes.
func runAppleScript(_ source: String) -> AppleScriptResult {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
  process.arguments = ["-e", source]

  let stdoutPipe = Pipe()
  let stderrPipe = Pipe()
  process.standardOutput = stdoutPipe
  process.standardError = stderrPipe

  do {
    try process.run()
    process.waitUntilExit()
  } catch {
    return .error(.mailNotRunning, "Failed to execute AppleScript: \(error.localizedDescription)")
  }

  let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
  let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
  let stdout =
    String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  let stderr =
    String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

  if process.terminationStatus != 0 {
    return mapAppleScriptError(stderr)
  }

  return .success(stdout)
}

/// Map an AppleScript error message to a structured plugin error.
private func mapAppleScriptError(_ stderr: String) -> AppleScriptResult {
  let lower = stderr.lowercased()

  if lower.contains("not running") || lower.contains("application isn") {
    return .error(.mailNotRunning, "Mail.app is not running. Please open Mail and try again.")
  }
  if lower.contains("not allowed") || lower.contains("permission")
    || lower.contains("not authorized")
  {
    return .error(
      .permissionDenied,
      "Automation permission denied. Grant access in System Settings → Privacy & Security → Automation."
    )
  }
  if lower.contains("can't get mailbox") || lower.contains("can't get account") {
    return .error(.mailboxNotFound, stderr)
  }
  if lower.contains("can't get message") {
    return .error(.messageNotFound, stderr)
  }

  return .error(.mailNotRunning, "AppleScript error: \(stderr)")
}

// MARK: - Message Resolution

/// Build an AppleScript snippet that resolves a message by its RFC Message-ID.
///
/// Checks the cache for the Mail.app internal ID first. On cache miss, searches
/// across all accounts via `whose message id is`.
func buildResolveScript(messageID: String, cache: MessageCache) -> String {
  let escapedMsgID = escapeAppleScriptString(messageID)

  if let internalID = cache.get(messageID) {
    return """
          set m to first message of message viewer 1 whose id is \(internalID)
      """
  }

  return """
        set m to missing value
        repeat with acct in every account
            try
                set foundMsgs to (every message of every mailbox of acct whose message id is "\(escapedMsgID)")
                repeat with mboxMsgs in foundMsgs
                    if (count of mboxMsgs) > 0 then
                        set m to item 1 of mboxMsgs
                        exit repeat
                    end if
                end repeat
            end try
            if m is not missing value then exit repeat
        end repeat
        if m is missing value then error "Message not found"
    """
}

// MARK: - Date Formatting

/// Convert an ISO 8601 date string to an AppleScript-friendly date string.
/// AppleScript expects dates like "February 1, 2026 12:00:00 AM".
func formatDateForAppleScript(_ iso8601: String) -> String {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  if let date = formatter.date(from: iso8601) {
    return appleScriptDateString(from: date)
  }
  // Retry without fractional seconds
  formatter.formatOptions = [.withInternetDateTime]
  if let date = formatter.date(from: iso8601) {
    return appleScriptDateString(from: date)
  }
  return iso8601
}

/// Normalize a date string from AppleScript «class isot» format to standard ISO 8601.
/// Appends "Z" if no timezone indicator is present.
func formatISO8601(_ dateStr: String) -> String {
  let trimmed = dateStr.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.hasSuffix("Z") || trimmed.contains("+") {
    return trimmed
  }
  // Check for a negative offset (e.g. "-05:00") after the date portion
  if trimmed.count > 10, trimmed[trimmed.index(trimmed.startIndex, offsetBy: 10)...].contains("-") {
    return trimmed
  }
  return trimmed + "Z"
}

private func appleScriptDateString(from date: Date) -> String {
  let df = DateFormatter()
  df.dateFormat = "MMMM d, yyyy h:mm:ss a"
  df.locale = Locale(identifier: "en_US_POSIX")
  return df.string(from: date)
}
