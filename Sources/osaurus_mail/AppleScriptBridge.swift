import Foundation
import OsaurusPluginKit

// MARK: - AppleScript Execution

/// Result of running an AppleScript.
enum AppleScriptResult {
  case success(String)
  case error(MailPluginError, String)
}

/// how long to wait for an AppleScript before killing the process and returning an error.
private let appleScriptTimeoutSeconds: TimeInterval = 25

/// Execute an AppleScript source string and return the result.
///
/// Uses the SDK's `ProcessRunner` with `/usr/bin/osascript`: stdout/stderr
/// are drained concurrently (large output cannot deadlock), the process is
/// killed if it does not finish within `appleScriptTimeoutSeconds`, and
/// captured output is capped. Maps common Apple Mail errors to
/// `MailPluginError` codes.
func runAppleScript(_ source: String) -> AppleScriptResult {
  let result: ProcessRunner.Output
  do {
    result = try ProcessRunner.run(
      executable: "/usr/bin/osascript", arguments: ["-e", source],
      timeout: appleScriptTimeoutSeconds)
  } catch ProcessRunnerError.launchFailed(let message) {
    return .error(.mailNotRunning, "Failed to execute AppleScript: \(message)")
  } catch {
    return .error(.mailNotRunning, "Failed to execute AppleScript: \(error.localizedDescription)")
  }

  if result.timedOut {
    return .error(
      .timeout,
      "AppleScript did not finish within \(Int(appleScriptTimeoutSeconds)) seconds and was terminated. Mail may be busy — try again."
    )
  }

  let stdout = result.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
  let stderr = result.stderrText.trimmingCharacters(in: .whitespacesAndNewlines)

  if result.exitStatus != 0 {
    return mapAppleScriptError(stderr)
  }

  return .success(stdout)
}

/// Map an AppleScript error message to a structured plugin error.
private func mapAppleScriptError(_ stderr: String) -> AppleScriptResult {
  // Mail emits typographic apostrophes ("Can’t get account") — normalize to ASCII
  // so the substring checks below actually match instead of falling through to the
  // generic "not running" catch-all.
  let lower = stderr.lowercased()
    .replacingOccurrences(of: "\u{2019}", with: "'")
    .replacingOccurrences(of: "\u{2018}", with: "'")

  // -1712: apple event timed out — Mail is running but too busy to respond.
  // must be checked before the generic "not running" branch so it isn't misclassified.
  if lower.contains("-1712") || lower.contains("appleevent timed out")
    || lower.contains("apple event timed out")
  {
    return .error(
      .timeout,
      "Mail did not respond in time (Apple Event timed out). Mail may be busy — wait a moment and try again."
    )
  }
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
    return .error(
      .mailboxNotFound,
      "Mailbox or account not found. Run list_mailboxes to see the exact account and mailbox names, then use the 'Account/Mailbox' format (e.g. 'Google/INBOX')."
    )
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
/// Returns `nil` when the input is not a valid ISO 8601 timestamp or date,
/// so callers can reject it instead of passing garbage into AppleScript.
func formatDateForAppleScript(_ iso8601: String) -> String? {
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
  // Accept a bare date (e.g. "2025-02-01") as midnight UTC
  let df = DateFormatter()
  df.dateFormat = "yyyy-MM-dd"
  df.locale = Locale(identifier: "en_US_POSIX")
  df.timeZone = TimeZone(identifier: "UTC")
  if let date = df.date(from: iso8601) {
    return appleScriptDateString(from: date)
  }
  return nil
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
