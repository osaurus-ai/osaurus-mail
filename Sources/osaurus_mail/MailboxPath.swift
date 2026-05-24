import Foundation

// MARK: - Mailbox Path Resolution

/// A parsed mailbox path, split into an account-resolution snippet and a mailbox reference
/// that hangs off the `targetAccount` variable that snippet binds.
struct ParsedMailbox {
  /// the raw account segment as supplied (an email address or an account name)
  let accountKey: String
  /// AppleScript that binds `targetAccount` to the matching account (or errors). Must be
  /// emitted inside the `tell application "Mail"` block before `mailboxRef` is used.
  let resolveAccountScript: String
  /// nested mailbox reference rooted at `targetAccount`,
  /// e.g. `mailbox "Projects" of mailbox "Work" of targetAccount`
  let mailboxRef: String
}

/// Parse a qualified mailbox path into an account resolver + mailbox reference.
///
/// Format: `<account>/<mailbox>[/<child>]*` where `<account>` is the account's **email
/// address** (preferred — unique across same-named accounts) or its display name (still
/// accepted for backward compatibility).
/// - `"you@gmail.com/INBOX"` -> resolves the account whose email is you@gmail.com
/// - `"iCloud/INBOX"`        -> resolves the account named "iCloud"
/// - `"Work/Projects"` under `you@work.com` -> `mailbox "Projects" of mailbox "Work" of targetAccount`
///
/// Returns `nil` if the path has no `/` separator (invalid format).
func parseMailboxPath(_ mailboxPath: String) -> ParsedMailbox? {
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

  // Build nested mailbox reference rooted at the resolved account variable.
  var ref = "targetAccount"
  for segment in segments {
    let escapedSegment = escapeAppleScriptString(segment)
    ref = "mailbox \"\(escapedSegment)\" of \(ref)"
  }

  return ParsedMailbox(
    accountKey: account,
    resolveAccountScript: resolveAccountScript(forKey: account),
    mailboxRef: ref)
}

/// AppleScript that binds `targetAccount` to the account matching `key` (its email address
/// or display name), erroring if none match. Must be emitted inside a `tell application "Mail"`
/// block before `targetAccount` is referenced.
///
/// We loop rather than use `whose` because Mail rejects `whose email addresses contains …`
/// with error -1719. Matching name OR email keeps old name-based paths working while letting
/// new email-based paths disambiguate two accounts that share a display name.
func resolveAccountScript(forKey key: String) -> String {
  let escaped = escapeAppleScriptString(key)
  return """
    set acctKey to "\(escaped)"
    set targetAccount to missing value
    repeat with a in accounts
        if (name of a is acctKey) or (email addresses of a contains acctKey) then
            set targetAccount to a
            exit repeat
        end if
    end repeat
    if targetAccount is missing value then error "Can't get account: " & acctKey
    """
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
