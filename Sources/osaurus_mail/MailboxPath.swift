import Foundation

// MARK: - Mailbox Path Resolution

/// Parse a qualified mailbox path (e.g. "Gmail/Work/Projects") into an AppleScript reference.
///
/// Format: `<account_name>/<mailbox>[/<child>]*`
/// - `"iCloud/INBOX"` -> account: "iCloud", mailboxRef: `mailbox "INBOX" of account "iCloud"`
/// - `"Gmail/Work/Projects"` -> account: "Gmail", mailboxRef: `mailbox "Projects" of mailbox "Work" of account "Gmail"`
///
/// Returns `nil` if the path has no `/` separator (invalid format).
func parseMailboxPath(_ mailboxPath: String) -> (account: String, applescriptRef: String)? {
  guard let slashIndex = mailboxPath.firstIndex(of: "/") else {
    return nil
  }

  let account = String(mailboxPath[mailboxPath.startIndex..<slashIndex])
  let remainder = String(mailboxPath[mailboxPath.index(after: slashIndex)...])

  guard !account.isEmpty, !remainder.isEmpty else {
    return nil
  }

  let segments = remainder.split(separator: "/").map(String.init)
  guard !segments.isEmpty else {
    return nil
  }

  // Build nested AppleScript reference: innermost mailbox first
  // "Work/Projects" -> mailbox "Projects" of mailbox "Work" of account "Gmail"
  let escapedAccount = escapeAppleScriptString(account)
  var ref = "account \"\(escapedAccount)\""
  for segment in segments {
    let escapedSegment = escapeAppleScriptString(segment)
    ref = "mailbox \"\(escapedSegment)\" of \(ref)"
  }

  return (account: account, applescriptRef: ref)
}

/// Escape a string for use inside AppleScript double-quoted strings.
func escapeAppleScriptString(_ s: String) -> String {
  var result = ""
  result.reserveCapacity(s.count)
  for ch in s {
    switch ch {
    case "\"": result += "\\\""
    case "\\": result += "\\\\"
    default: result.append(ch)
    }
  }
  return result
}
