import Foundation

// MARK: - Read Message Tool

struct ReadMessageTool {
  let name = "read_message"

  struct Args: Decodable {
    let message_id: String
    let max_length: Int?
    let include_headers: Bool?
  }

  func run(args: String, cache: MessageCache) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return MailPluginError.invalidParameter.json(message: "Invalid arguments for read_message.")
    }

    if let maxLength = input.max_length, maxLength < 1 {
      return MailPluginError.invalidParameter.json(
        message: "max_length must be a positive integer (got \(maxLength)).")
    }
    let maxLength = input.max_length ?? 10000
    let includeHeaders = input.include_headers ?? false
    let messageID = input.message_id
    let resolveScript = buildResolveScript(messageID: messageID, cache: cache)

    let headersLine =
      includeHeaders
      ? "set hdrs to my encodeField(all headers of m)"
      : "set hdrs to \"\""

    let script = """
      tell application "Mail"
          \(resolveScript)
          set subj to subject of m
          set sndr to sender of m
          set dr to date received of m
          set rs to read status of m
          set fs to flagged status of m
          set bodyContent to content of m
          \(headersLine)
          set mid to message id of m
          set iid to id of m
          -- Recipients
          set toList to ""
          repeat with r in (every to recipient of m)
              if toList is not "" then set toList to toList & "|||"
              set toList to toList & my encodeField(address of r as text)
          end repeat
          set ccList to ""
          repeat with r in (every cc recipient of m)
              if ccList is not "" then set ccList to ccList & "|||"
              set ccList to ccList & my encodeField(address of r as text)
          end repeat
          -- Attachments
          set attList to ""
          repeat with att in (every mail attachment of m)
              if attList is not "" then set attList to attList & "|||"
              set attName to name of att
              try
                  set attBytes to file size of att
              on error
                  set attBytes to 0
              end try
              set attList to attList & my encodeField(attName) & ":::" & attBytes
          end repeat
          -- Mailbox path
          set mbox to mailbox of m
          set mboxName to name of mbox
          set acctName to name of account of mbox
          set mboxPath to acctName & "/" & mboxName
          return my encodeField(mid) & "\\t" & my encodeField(subj) & "\\t" & my encodeField(sndr) & "\\t" & (dr as «class isot» as string) & "\\t" & rs & "\\t" & fs & "\\t" & my encodeField(bodyContent) & "\\t" & hdrs & "\\t" & toList & "\\t" & ccList & "\\t" & attList & "\\t" & my encodeField(mboxPath) & "\\t" & iid
      end tell
      \(appleScriptFieldEncoderHandlers)
      """

    switch runAppleScript(script) {
    case .success(let output):
      return parseOutput(
        output, messageID: messageID, maxLength: maxLength, includeHeaders: includeHeaders,
        cache: cache)
    case .error(let code, let message):
      return code.json(message: message)
    }
  }

  /// Parse the tab-delimited, field-encoded read_message script output.
  func parseOutput(
    _ output: String, messageID: String, maxLength: Int, includeHeaders: Bool, cache: MessageCache
  ) -> String {
    let parts = output.split(separator: "\t", maxSplits: 12, omittingEmptySubsequences: false)
      .map(String.init)
    guard parts.count >= 13 else {
      return MailPluginError.messageNotFound.json(
        message: "Message '\(messageID)' not found. It may have been deleted or moved.")
    }

    let msgID = decodeAppleScriptField(parts[0])
    let internalID = Int(parts[12]) ?? 0
    cache.set(msgID, internalID: internalID)

    // Truncate body
    var body = decodeAppleScriptField(parts[6])
    var bodyTruncated = false
    if body.count > maxLength {
      body = String(body.prefix(maxLength))
      bodyTruncated = true
    }

    let toList =
      parts[8].isEmpty
      ? [String]() : parts[8].split(separator: "|||").map { decodeAppleScriptField(String($0)) }
    let ccList =
      parts[9].isEmpty
      ? [String]() : parts[9].split(separator: "|||").map { decodeAppleScriptField(String($0)) }

    // Parse attachments
    var attachments: [[String: Any]] = []
    if !parts[10].isEmpty {
      for att in parts[10].split(separator: "|||").map(String.init) {
        let info = att.split(separator: ":::", maxSplits: 1).map(String.init)
        attachments.append([
          "name": decodeAppleScriptField(info[0]),
          "size_bytes": info.count >= 2 ? (Int(info[1]) ?? 0) : 0,
        ])
      }
    }

    var response: [String: Any] = [
      "message_id": msgID,
      "subject": decodeAppleScriptField(parts[1]),
      "from": decodeAppleScriptField(parts[2]),
      "to": toList,
      "cc": ccList,
      "date": formatISO8601(parts[3]),
      "body": body,
      "body_truncated": bodyTruncated,
      "is_read": parts[4] == "true",
      "is_flagged": parts[5] == "true",
      "attachments": attachments,
      "mailbox_path": decodeAppleScriptField(parts[11]),
    ]

    if includeHeaders && !parts[7].isEmpty {
      response["headers"] = decodeAppleScriptField(parts[7])
    }

    return jsonEncode(response)
  }
}
