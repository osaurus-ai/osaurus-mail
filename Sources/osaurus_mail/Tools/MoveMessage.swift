import Foundation

// MARK: - Move Message Tool

struct MoveMessageTool {
  let name = "move_message"

  struct Args: Decodable {
    let message_id: String
    let destination_mailbox_path: String
  }

  func run(args: String, cache: MessageCache) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return MailPluginError.invalidParameter.json(message: "Invalid arguments for move_message.")
    }

    let messageID = input.message_id

    guard let destParsed = parseMailboxPath(input.destination_mailbox_path) else {
      return MailPluginError.invalidDestination.json(
        message:
          "Invalid destination mailbox path: '\(input.destination_mailbox_path)'. Expected format: 'Account/Mailbox'."
      )
    }

    let resolveScript = buildResolveScript(messageID: messageID, cache: cache)
    let destRef = destParsed.applescriptRef
    let destAccount = destParsed.account

    // Move the message and return the source mailbox path
    let script = """
      tell application "Mail"
          \(resolveScript)
          set srcMbox to mailbox of m
          set srcMboxName to name of srcMbox
          set srcAcctName to name of account of srcMbox
          set srcPath to srcAcctName & "/" & srcMboxName
          -- Validate same account
          if srcAcctName is not "\(escapeAppleScriptString(destAccount))" then
              error "Cross-account move: source is " & srcAcctName & ", destination is \(escapeAppleScriptString(destAccount))"
          end if
          move m to \(destRef)
          return srcPath
      end tell
      """

    switch runAppleScript(script) {
    case .success(let output):
      let fromPath = output.trimmingCharacters(in: .whitespacesAndNewlines)
      return jsonEncode([
        "status": "moved",
        "message_id": messageID,
        "from_mailbox_path": fromPath,
        "to_mailbox_path": input.destination_mailbox_path,
      ])

    case .error(let code, let message):
      // Check for cross-account error
      if message.contains("Cross-account move") {
        return MailPluginError.invalidDestination.json(
          message: "Cannot move to '\(input.destination_mailbox_path)': \(message)")
      }
      return code.json(message: message)
    }
  }
}
