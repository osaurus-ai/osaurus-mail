import Foundation
import OsaurusPluginKit

// MARK: - AppleScript Execution

/// Result of running an AppleScript.
enum AppleScriptResult {
  case success(String)
  case error(MailPluginError, String)
}

/// How long to wait for an AppleScript before killing the process and returning
/// an error. Mail answers each Apple event on its main thread, so accounts with
/// many mailboxes or messages legitimately need tens of seconds even when the
/// scripts batch their fetches; the host's own tool-call guard (120s) still
/// bounds the worst case above this.
private let appleScriptTimeoutSeconds: TimeInterval = 60

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
      "AppleScript did not finish within \(Int(appleScriptTimeoutSeconds)) seconds and was terminated. Mail may be busy or the account may be very large. Retry with a smaller scope (a specific mailbox_path, lower limit, or narrower date filters)."
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

// MARK: - Message Row Emission

/// AppleScript statements that append one tab-delimited, field-encoded row for
/// the message bound to `m` onto `output`. Shared by list_messages and both
/// search_messages paths so the row format (and its Apple-event cost) stays in
/// one place.
///
/// The seven scalar properties are fetched with a single multi-property `get`
/// (one Apple event) instead of seven separate `x of m` statements (seven
/// events); recipients and the attachment count are one event each. Three
/// round trips per message instead of ~10 — per-event latency is what blew
/// the script timeout on slow machines (issue osaurus#2298).
let appleScriptEmitMessageRow = """
  set props to {message id, subject, sender, date received, read status, flagged status, id} of m
  set recipAddrs to {}
  try
      set recipAddrs to address of every to recipient of m
  end try
  set hasAtt to (count of mail attachments of m) > 0
  set recipList to ""
  repeat with r in recipAddrs
      if recipList is not "" then set recipList to recipList & "|||"
      set recipList to recipList & my encodeField(r as text)
  end repeat
  set output to output & my encodeField(item 1 of props) & "\\t" & my encodeField(item 2 of props) & "\\t" & my encodeField(item 3 of props) & "\\t" & ((item 4 of props) as «class isot» as string) & "\\t" & (item 5 of props) & "\\t" & (item 6 of props) & "\\t" & hasAtt & "\\t" & (item 7 of props) & "\\t" & recipList & linefeed
  """

// MARK: - Message Resolution

/// AppleScript that searches every account for the message whose RFC Message-ID
/// equals the (already escaped) `escapedMsgID`, binding it to `m` or leaving `m`
/// as `missing value`.
private func appleScriptSearchByMessageID(_ escapedMsgID: String) -> String {
  """
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
  """
}

/// Build an AppleScript snippet that resolves a message by its RFC Message-ID and
/// binds it to `m` (or errors with "Message not found").
///
/// Resolution never goes through `message viewer 1`: the front viewer only knows
/// the messages it currently displays, so a numeric id that was valid when the
/// message was listed fails with "Invalid index" (-1719) as soon as the user (or a
/// previous move) changes what the viewer shows — issue #5. Instead, in order of
/// cost:
///
/// 1. `first message of <mailbox> whose id is N` in the mailbox the message was
///    last listed in (one Apple event; the common case for list → read/move
///    sequences). The `whose` form is used because `message id N of <variable>`
///    does not compile.
/// 2. The same lookup in every mailbox of every account (one event per mailbox;
///    covers messages that were moved since they were listed).
/// 3. `whose message id is …` across every account (cache miss, or the internal
///    id became stale because Mail re-indexed).
///
/// Each step is wrapped in `try` so a miss falls through to the next one.
func buildResolveScript(messageID: String, cache: MessageCache) -> String {
  let escapedMsgID = escapeAppleScriptString(messageID)
  var script = "set m to missing value\n"

  if let cached = cache.entry(for: messageID) {
    if let mailboxPath = cached.mailboxPath, let parsed = parseMailboxPath(mailboxPath) {
      script += """
        try
            \(parsed.resolveScript)
            set m to first message of \(parsed.mailboxRef) whose id is \(cached.internalID)
        end try

        """
    }
    script += """
      if m is missing value then
          repeat with acct in every account
              repeat with mbox in every mailbox of acct
                  try
                      set m to first message of mbox whose id is \(cached.internalID)
                      exit repeat
                  end try
              end repeat
              if m is not missing value then exit repeat
          end repeat
      end if

      """
  }

  script += """
    if m is missing value then
    \(appleScriptSearchByMessageID(escapedMsgID))
    end if
    if m is missing value then error "Message not found"
    """
  return script
}

// MARK: - Date Formatting

/// Parse an ISO 8601 timestamp (with or without fractional seconds) or a bare
/// `yyyy-MM-dd` date (taken as midnight UTC). Returns `nil` for anything else.
func parseISO8601Date(_ iso8601: String) -> Date? {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  if let date = formatter.date(from: iso8601) {
    return date
  }
  // Retry without fractional seconds
  formatter.formatOptions = [.withInternetDateTime]
  if let date = formatter.date(from: iso8601) {
    return date
  }
  // Accept a bare date (e.g. "2025-02-01") as midnight UTC
  let df = DateFormatter()
  df.dateFormat = "yyyy-MM-dd"
  df.locale = Locale(identifier: "en_US_POSIX")
  df.timeZone = TimeZone(identifier: "UTC")
  return df.date(from: iso8601)
}

/// AppleScript statements that bind `variable` to the instant described by
/// `iso8601`, expressed in the Mac's local time zone (what Mail's `date received`
/// compares against).
///
/// The date is assembled from numeric components (`set year of d to …`) rather
/// than a `date "February 1, 2026 12:00:00 AM"` literal: AppleScript parses date
/// literals with the *system* locale, so an English literal fails to compile on
/// every non-English Mac ("Datum und Uhrzeit sind ungültig", -30720) — issue #13.
/// `day` is set to 1 before `year`/`month` so an intermediate 31st-of-a-short-month
/// can't roll the month over. Returns `nil` when `iso8601` is not a valid date, so
/// callers can reject it instead of passing garbage into AppleScript.
func appleScriptDateBinding(_ variable: String, iso8601: String) -> String? {
  guard let date = parseISO8601Date(iso8601) else { return nil }
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone.current
  let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
  guard let year = c.year, let month = c.month, let day = c.day,
    let hour = c.hour, let minute = c.minute, let second = c.second
  else { return nil }
  let secondsSinceMidnight = hour * 3600 + minute * 60 + second
  return """
    set \(variable) to current date
    set day of \(variable) to 1
    set year of \(variable) to \(year)
    set month of \(variable) to \(month)
    set day of \(variable) to \(day)
    set time of \(variable) to \(secondsSinceMidnight)
    """
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
