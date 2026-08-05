import Foundation

// MARK: - List Messages Tool

struct ListMessagesTool {
  let name = "list_messages"

  struct Args: Decodable {
    let mailbox_path: String
    let limit: Int?
    let offset: Int?
    let unread_only: Bool?
    let since: String?
    let before: String?
    let from_contains: String?
  }

  func run(args: String, cache: MessageCache) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return MailPluginError.invalidParameter.json(message: "Invalid arguments for list_messages.")
    }

    let limit = min(max(input.limit ?? 20, 1), 50)
    let offset = max(input.offset ?? 0, 0)

    guard let parsed = parseMailboxPath(input.mailbox_path) else {
      return MailPluginError.mailboxNotFound.json(
        message:
          "Invalid mailbox path format: '\(input.mailbox_path)'. Expected format: 'Account/Mailbox'."
      )
    }

    // Build whose clause filters
    var whoseClauses: [String] = []
    if input.unread_only == true {
      whoseClauses.append("read status is false")
    }
    if let since = input.since {
      guard let formatted = formatDateForAppleScript(since) else {
        return MailPluginError.invalidParameter.json(
          message: "Invalid 'since' date: '\(since)'. Use ISO 8601 (e.g. '2025-02-01T00:00:00Z').")
      }
      whoseClauses.append("date received > date \"\(escapeAppleScriptString(formatted))\"")
    }
    if let before = input.before {
      guard let formatted = formatDateForAppleScript(before) else {
        return MailPluginError.invalidParameter.json(
          message: "Invalid 'before' date: '\(before)'. Use ISO 8601 (e.g. '2025-02-01T00:00:00Z')."
        )
      }
      whoseClauses.append("date received < date \"\(escapeAppleScriptString(formatted))\"")
    }
    if let fromContains = input.from_contains {
      let escaped = escapeAppleScriptString(fromContains)
      whoseClauses.append("sender contains \"\(escaped)\"")
    }

    let mailboxRef = parsed.mailboxRef
    let whoseStr = whoseClauses.isEmpty ? "" : " whose \(whoseClauses.joined(separator: " and "))"

    // Get total count with filters
    let countScript = """
      tell application "Mail"
          \(parsed.resolveScript)
          return count of (every message of \(mailboxRef)\(whoseStr))
      end tell
      """

    var total = 0
    switch runAppleScript(countScript) {
    case .success(let output):
      total = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    case .error(let code, let message):
      return code.json(message: message)
    }

    if total == 0 || offset >= total {
      return jsonEncode([
        "messages": [] as [Any],
        "total": total,
        "has_more": false,
        "next_offset": offset,
      ])
    }

    // AppleScript uses 1-based indexing; messages are newest-first by default
    let startIdx = offset + 1
    let endIdx = min(offset + limit, total)

    let fetchScript = """
      tell application "Mail"
          \(parsed.resolveScript)
          set msgs to (every message of \(mailboxRef)\(whoseStr))
          set output to ""
          repeat with i from \(startIdx) to \(endIdx)
              set m to item i of msgs
              \(appleScriptEmitMessageRow)
          end repeat
          return output
      end tell
      \(appleScriptFieldEncoderHandlers)
      """

    return parseMessageListOutput(
      fetchScript, total: total, offset: offset, endIdx: endIdx, cache: cache)
  }
}

// MARK: - Shared Message List Parsing

/// Run a message-list script and parse its output into a paginated JSON response.
func parseMessageListOutput(
  _ script: String, total: Int, offset: Int, endIdx: Int, cache: MessageCache
) -> String {
  switch runAppleScript(script) {
  case .success(let output):
    return renderMessageListJSON(output, total: total, offset: offset, endIdx: endIdx, cache: cache)
  case .error(let code, let message):
    return code.json(message: message)
  }
}

/// Parse tab-delimited, field-encoded message list output into a paginated JSON response.
func renderMessageListJSON(
  _ output: String, total: Int, offset: Int, endIdx: Int, cache: MessageCache
) -> String {
  var messages: [[String: Any]] = []
  var cacheEntries: [(messageID: String, internalID: Int)] = []
  let lines = output.split(separator: "\n", omittingEmptySubsequences: true)

  for line in lines {
    let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    guard parts.count >= 9 else { continue }

    let messageID = decodeAppleScriptField(parts[0])
    let internalID = Int(parts[7]) ?? 0
    let toStr = parts[8]
    let toList =
      toStr.isEmpty
      ? [String]() : toStr.split(separator: "|||").map { decodeAppleScriptField(String($0)) }

    messages.append([
      "message_id": messageID,
      "subject": decodeAppleScriptField(parts[1]),
      "from": decodeAppleScriptField(parts[2]),
      "to": toList,
      "date": formatISO8601(parts[3]),
      "is_read": parts[4] == "true",
      "is_flagged": parts[5] == "true",
      "has_attachments": parts[6] == "true",
    ])
    cacheEntries.append((messageID: messageID, internalID: internalID))
  }

  cache.populateFromMessages(cacheEntries)

  let hasMore = endIdx < total
  let nextOffset = hasMore ? endIdx : offset

  return jsonEncode([
    "messages": messages,
    "total": total,
    "has_more": hasMore,
    "next_offset": nextOffset,
  ])
}
