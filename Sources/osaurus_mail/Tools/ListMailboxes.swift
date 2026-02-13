import Foundation

// MARK: - List Mailboxes Tool

struct ListMailboxesTool {
  let name = "list_mailboxes"

  func run(args: String, cache: MessageCache) -> String {
    // Iterate accounts, then mailboxes of each account (up to 3 levels deep).
    let simpleScript = """
      tell application "Mail"
          set output to ""
          set allAccounts to every account
          repeat with acct in allAccounts
              set acctName to name of acct
              set topMailboxes to every mailbox of acct
              repeat with mbox in topMailboxes
                  set mboxName to name of mbox
                  set fullPath to acctName & "/" & mboxName
                  set uc to unread count of mbox
                  try
                      set mc to count of messages of mbox
                  on error
                      set mc to 0
                  end try
                  set output to output & fullPath & "\\t" & uc & "\\t" & mc & linefeed
                  -- Second level
                  try
                      set childMailboxes to every mailbox of mbox
                      repeat with child in childMailboxes
                          set childName to name of child
                          set childPath to fullPath & "/" & childName
                          set childUC to unread count of child
                          try
                              set childMC to count of messages of child
                          on error
                              set childMC to 0
                          end try
                          set output to output & childPath & "\\t" & childUC & "\\t" & childMC & linefeed
                          -- Third level
                          try
                              set grandchildren to every mailbox of child
                              repeat with gc in grandchildren
                                  set gcName to name of gc
                                  set gcPath to childPath & "/" & gcName
                                  set gcUC to unread count of gc
                                  try
                                      set gcMC to count of messages of gc
                                  on error
                                      set gcMC to 0
                                  end try
                                  set output to output & gcPath & "\\t" & gcUC & "\\t" & gcMC & linefeed
                              end repeat
                          end try
                      end repeat
                  end try
              end repeat
          end repeat
          return output
      end tell
      """

    switch runAppleScript(simpleScript) {
    case .success(let output):
      var mailboxes: [[String: Any]] = []
      let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
      for line in lines {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        if parts.count >= 3 {
          let mailboxPath = parts[0]
          let unreadCount = Int(parts[1]) ?? 0
          let messageCount = Int(parts[2]) ?? 0
          mailboxes.append([
            "mailbox_path": mailboxPath,
            "unread_count": unreadCount,
            "message_count": messageCount,
          ])
        }
      }
      return jsonEncode(["mailboxes": mailboxes])

    case .error(let code, let message):
      return code.json(message: message)
    }
  }
}
