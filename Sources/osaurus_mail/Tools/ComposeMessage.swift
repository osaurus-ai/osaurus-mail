import Foundation

// MARK: - Compose Message Tool

struct ComposeMessageTool {
  let name = "compose_message"

  struct Args: Decodable {
    let to: [String]
    let subject: String
    let body: String?
    let html_body: String?
    let cc: [String]?
    let bcc: [String]?
    let from_account: String?
    let send: Bool?
  }

  func run(args: String, cache: MessageCache) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return MailPluginError.invalidParameter.json(
        message: "Invalid arguments for compose_message.")
    }

    if input.body == nil && input.html_body == nil {
      return MailPluginError.missingBody.json(message: "Either body or html_body must be provided.")
    }

    let shouldSend = input.send ?? false
    let subject = escapeAppleScriptString(input.subject)

    // Build recipient lines
    var recipientLines = ""
    for addr in input.to {
      let escaped = escapeAppleScriptString(addr)
      recipientLines +=
        "make new to recipient at end of to recipients of msg with properties {address:\"\(escaped)\"}\n"
    }
    if let cc = input.cc {
      for addr in cc {
        let escaped = escapeAppleScriptString(addr)
        recipientLines +=
          "make new cc recipient at end of cc recipients of msg with properties {address:\"\(escaped)\"}\n"
      }
    }
    if let bcc = input.bcc {
      for addr in bcc {
        let escaped = escapeAppleScriptString(addr)
        recipientLines +=
          "make new bcc recipient at end of bcc recipients of msg with properties {address:\"\(escaped)\"}\n"
      }
    }

    // Body content
    let bodyLine: String
    if let htmlBody = input.html_body {
      bodyLine = "set html content of msg to \"\(escapeAppleScriptString(htmlBody))\""
    } else if let body = input.body {
      bodyLine = "set content of msg to \"\(escapeAppleScriptString(body))\""
    } else {
      bodyLine = ""
    }

    // Sender account
    var senderLine = ""
    if let fromAccount = input.from_account {
      let escaped = escapeAppleScriptString(fromAccount)
      senderLine = """
        try
            set senderAddr to email addresses of account "\(escaped)"
            if (count of senderAddr) > 0 then
                set sender of msg to (item 1 of senderAddr as text)
            end if
        end try
        """
    }

    let sendOrShow = shouldSend ? "send msg" : "set visible of msg to true"

    let script = """
      tell application "Mail"
          set msg to make new outgoing message with properties {subject:"\(subject)", visible:false}
          \(bodyLine)
          \(recipientLines)\(senderLine)
          \(sendOrShow)
      end tell
      """

    switch runAppleScript(script) {
    case .success:
      if shouldSend {
        return jsonEncode([
          "status": "sent",
          "message": "Email sent to \(input.to.joined(separator: ", ")).",
        ])
      } else {
        return jsonEncode([
          "status": "drafted",
          "message": "Draft opened in Mail compose window for user review.",
        ])
      }

    case .error(let code, let message):
      if shouldSend {
        return MailPluginError.sendFailed.json(message: "Failed to send email: \(message)")
      }
      return code.json(message: message)
    }
  }
}
