import Foundation

// MARK: - List Mailboxes Tool

struct ListMailboxesTool {
  let name = "list_mailboxes"

  func run(args: String, cache: MessageCache) -> String {
    // Enumerate the mailbox hierarchy (up to 3 levels deep) using BULK property
    // fetches: `name of every mailbox of …` returns the whole level in a single
    // Apple event, where the old per-mailbox loop cost one round trip per
    // property per mailbox. On machines where each round trip takes hundreds of
    // milliseconds, that per-item chatter alone blew the script timeout on any
    // account with a few dozen mailboxes (issue osaurus#2298).
    //
    // Per-mailbox `count of messages` was dropped for the same reason: it has
    // no bulk form and forces Mail to materialize each mailbox — it was the
    // single most expensive part of the old script.
    //
    // Name and unread-count lists for a level are fetched inside one `try` so
    // they can never misalign: either both arrive or the level is skipped.
    let simpleScript = """
      tell application "Mail"
          set output to ""
          repeat with acct in every account
              set acctName to name of acct
              set acctEmail to ""
              try
                  set acctEmails to email addresses of acct
                  if (count of acctEmails) > 0 then set acctEmail to item 1 of acctEmails
              end try
              -- prefer the email as the path's account segment (unique across same-named
              -- accounts); fall back to the name for accounts without an email (e.g. local)
              set acctKey to acctName
              if acctEmail is not "" then set acctKey to acctEmail
              set topNames to {}
              set topUnread to {}
              try
                  set topNames to name of every mailbox of acct
                  set topUnread to unread count of every mailbox of acct
              end try
              set childNames to {}
              set childUnread to {}
              try
                  set childNames to name of every mailbox of every mailbox of acct
                  set childUnread to unread count of every mailbox of every mailbox of acct
              end try
              set gcNames to {}
              set gcUnread to {}
              try
                  set gcNames to name of every mailbox of every mailbox of every mailbox of acct
                  set gcUnread to unread count of every mailbox of every mailbox of every mailbox of acct
              end try
              repeat with i from 1 to (count of topNames)
                  set fullPath to acctKey & "/" & (item i of topNames)
                  set output to output & my encodeField(fullPath) & "\\t" & my numOrZero(item i of topUnread) & "\\t" & my encodeField(acctEmail) & linefeed
                  -- Second level: item i of childNames is the list of child names of top mailbox i
                  if i > (count of childNames) then
                      set theseChildNames to {}
                  else
                      set theseChildNames to item i of childNames
                  end if
                  repeat with j from 1 to (count of theseChildNames)
                      set childPath to fullPath & "/" & (item j of theseChildNames)
                      set output to output & my encodeField(childPath) & "\\t" & my numOrZero(item j of (item i of childUnread)) & "\\t" & my encodeField(acctEmail) & linefeed
                      -- Third level: item j of item i of gcNames is the grandchild name list
                      set theseGCNames to {}
                      if i is not greater than (count of gcNames) then
                          if j is not greater than (count of (item i of gcNames)) then
                              set theseGCNames to item j of (item i of gcNames)
                          end if
                      end if
                      repeat with k from 1 to (count of theseGCNames)
                          set gcPath to childPath & "/" & (item k of theseGCNames)
                          set output to output & my encodeField(gcPath) & "\\t" & my numOrZero(item k of (item j of (item i of gcUnread))) & "\\t" & my encodeField(acctEmail) & linefeed
                      end repeat
                  end repeat
              end repeat
          end repeat
          return output
      end tell
      on numOrZero(v)
          if v is missing value then return 0
          return v
      end numOrZero
      \(appleScriptFieldEncoderHandlers)
      """

    switch runAppleScript(simpleScript) {
    case .success(let output):
      var mailboxes: [[String: Any]] = []
      let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
      for line in lines {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        if parts.count >= 3 {
          let mailboxPath = decodeAppleScriptField(parts[0])
          let unreadCount = Int(parts[1]) ?? 0
          let accountEmail = decodeAppleScriptField(parts[2])
          mailboxes.append([
            "mailbox_path": mailboxPath,
            "unread_count": unreadCount,
            "account_email": accountEmail,
          ])
        }
      }
      return jsonEncode(["mailboxes": mailboxes])

    case .error(let code, let message):
      return code.json(message: message)
    }
  }
}
