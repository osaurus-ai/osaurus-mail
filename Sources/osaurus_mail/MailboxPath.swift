import Foundation

// MARK: - Mailbox Path Resolution

/// A parsed mailbox path, split into a resolution snippet and the variable it binds.
struct ParsedMailbox {
  /// the raw account segment as supplied (an email address or an account name)
  let accountKey: String
  /// AppleScript that binds `targetAccount` and `targetMailbox` (or errors). Must be emitted
  /// inside the `tell application "Mail"` block before `mailboxRef` is used.
  let resolveScript: String
  /// the resolved mailbox variable bound by `resolveScript` — always `targetMailbox`
  let mailboxRef: String
}

/// Parse a qualified mailbox path into an account+mailbox resolver.
///
/// Format: `<account>/<mailbox>[/<child>]*` where `<account>` is the account's **email
/// address** (preferred — unique across same-named accounts) or its display name (still
/// accepted for backward compatibility).
/// - `"you@gmail.com/INBOX"` -> account whose email is you@gmail.com, mailbox named INBOX
/// - `"iCloud/INBOX"`        -> account named "iCloud"
/// - `"you@gmail.com/All Mail"` / nested `"…/Work/Projects"` are resolved by matching the
///   mailbox display `name` at each level.
///
/// Mailboxes are resolved by **iterating and matching `name`** rather than `mailbox "X" of …`
/// because Gmail's special folders (All Mail, Sent Mail, …) report a display name that isn't
/// directly addressable by that name (lives under `[Gmail]`), so a by-name lookup errors -1728.
/// Iteration mirrors how `list_mailboxes` enumerates names, so its paths always round-trip.
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

  // Resolve the account, then walk each path segment by matching the mailbox display name
  // within the current container (account, then nested mailbox).
  var script = resolveAccountScript(forKey: account)
  script += "\nset _container to targetAccount\n"
  for segment in segments {
    let esc = escapeAppleScriptString(segment)
    script += """
      set _found to missing value
      repeat with _mb in (every mailbox of _container)
          if name of _mb is "\(esc)" then
              set _found to _mb
              exit repeat
          end if
      end repeat
      if _found is missing value then error "Can't get mailbox: \(esc)"
      set _container to _found

      """
  }
  script += "set targetMailbox to _container"

  return ParsedMailbox(accountKey: account, resolveScript: script, mailboxRef: "targetMailbox")
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
