import Foundation

// MARK: - C ABI surface

// Opaque context
private typealias osr_plugin_ctx_t = UnsafeMutableRawPointer

// Function pointers
private typealias osr_free_string_t = @convention(c) (UnsafePointer<CChar>?) -> Void
private typealias osr_init_t = @convention(c) () -> osr_plugin_ctx_t?
private typealias osr_destroy_t = @convention(c) (osr_plugin_ctx_t?) -> Void
private typealias osr_get_manifest_t = @convention(c) (osr_plugin_ctx_t?) -> UnsafePointer<CChar>?
private typealias osr_invoke_t =
  @convention(c) (
    osr_plugin_ctx_t?,
    UnsafePointer<CChar>?,  // type
    UnsafePointer<CChar>?,  // id
    UnsafePointer<CChar>?  // payload
  ) -> UnsafePointer<CChar>?

private struct osr_plugin_api {
  var free_string: osr_free_string_t?
  var `init`: osr_init_t?
  var destroy: osr_destroy_t?
  var get_manifest: osr_get_manifest_t?
  var invoke: osr_invoke_t?
}

// MARK: - Plugin Context

/// Holds all tool instances and the shared message ID cache.
private class PluginContext {
  let cache = MessageCache(capacity: 10_000)
  let listMailboxes = ListMailboxesTool()
  let listMessages = ListMessagesTool()
  let readMessage = ReadMessageTool()
  let searchMessages = SearchMessagesTool()
  let composeMessage = ComposeMessageTool()
  let replyToMessage = ReplyToMessageTool()
  let moveMessage = MoveMessageTool()
  let setMessageStatus = SetMessageStatusTool()
  let getThread = GetThreadTool()
}

// MARK: - Helpers

/// Allocate a C string (caller must free via free_string).
private func makeCString(_ s: String) -> UnsafePointer<CChar>? {
  guard let dup = strdup(s) else { return nil }
  return UnsafePointer(dup)
}

// MARK: - API Implementation

nonisolated(unsafe) private var api: osr_plugin_api = {
  var api = osr_plugin_api()

  api.free_string = { ptr in
    if let p = ptr { free(UnsafeMutableRawPointer(mutating: p)) }
  }

  api.`init` = {
    let ctx = PluginContext()
    return Unmanaged.passRetained(ctx).toOpaque()
  }

  api.destroy = { ctxPtr in
    guard let ctxPtr = ctxPtr else { return }
    Unmanaged<PluginContext>.fromOpaque(ctxPtr).release()
  }

  api.get_manifest = { _ in
    let manifest = """
      {
        "plugin_id": "osaurus.mail",
        "name": "Osaurus Mail",
        "version": "0.1.0",
        "description": "Read, search, compose, and manage Apple Mail — locally and privately",
        "license": "MIT",
        "authors": [],
        "min_macos": "15.0",
        "min_osaurus": "0.5.0",
        "capabilities": {
          "tools": [
            {
              "id": "list_mailboxes",
              "description": "List all mailboxes in Apple Mail. Returns a flat list of mailbox_path identifiers (e.g. 'iCloud/INBOX', 'Gmail/[Gmail]/All Mail') that are used as the mailbox_path parameter in other tools. Call this first to discover available mailboxes.",
              "parameters": {"type":"object","properties":{}},
              "requirements": ["automation"],
              "permission_policy": "auto"
            },
            {
              "id": "list_messages",
              "description": "List message summaries in a mailbox. Returns subject, sender, date, and flags — but NOT the message body. Use read_message to get the body of a specific message. Supports filtering and pagination via offset. Messages are returned newest-first.",
              "parameters": {
                "type": "object",
                "properties": {
                  "mailbox_path": {"type":"string","description":"Mailbox path from list_mailboxes (e.g. 'iCloud/INBOX')"},
                  "limit": {"type":"integer","description":"Max messages to return, 1-50 (default: 20)"},
                  "offset": {"type":"integer","description":"Number of messages to skip for pagination (default: 0). Use the next_offset value from a previous response to get the next page."},
                  "unread_only": {"type":"boolean","description":"Only return unread messages (default: false)"},
                  "since": {"type":"string","description":"Only messages received after this date (ISO 8601, e.g. '2025-02-01T00:00:00Z')"},
                  "before": {"type":"string","description":"Only messages received before this date (ISO 8601)"},
                  "from_contains": {"type":"string","description":"Filter by sender — matches if sender name or address contains this string (case-insensitive)"}
                },
                "required": ["mailbox_path"]
              },
              "requirements": ["automation"],
              "permission_policy": "auto"
            },
            {
              "id": "read_message",
              "description": "Read the full content of a specific email message. Use this after list_messages or search_messages to get the message body. Returns plain text body by default.",
              "parameters": {
                "type": "object",
                "properties": {
                  "message_id": {"type":"string","description":"RFC Message-ID from list_messages or search_messages (e.g. '<CABx+...@mail.gmail.com>')"},
                  "max_length": {"type":"integer","description":"Truncate body to this many characters (default: 10000). Use a higher value for long emails."},
                  "include_headers": {"type":"boolean","description":"Include raw email headers (default: false)"}
                },
                "required": ["message_id"]
              },
              "requirements": ["automation"],
              "permission_policy": "ask"
            },
            {
              "id": "search_messages",
              "description": "Search for messages by keyword across subject and sender. Returns the same message summary format as list_messages (no body — use read_message for that). Searches subject line and sender name/address only; body-text search is not supported. Use this instead of list_messages when you need to find messages by subject or sender rather than browsing a specific mailbox.",
              "parameters": {
                "type": "object",
                "properties": {
                  "query": {"type":"string","description":"Search keywords (matched against subject line and sender name/address)"},
                  "mailbox_path": {"type":"string","description":"Limit search to a specific mailbox path. If omitted, searches all mailboxes."},
                  "limit": {"type":"integer","description":"Max results, 1-50 (default: 10)"},
                  "offset": {"type":"integer","description":"Skip N results for pagination (default: 0)"},
                  "since": {"type":"string","description":"Only messages after this date (ISO 8601)"},
                  "before": {"type":"string","description":"Only messages before this date (ISO 8601)"}
                },
                "required": ["query"]
              },
              "requirements": ["automation"],
              "permission_policy": "auto"
            },
            {
              "id": "compose_message",
              "description": "Compose a new email. By default opens as a draft for the user to review (send: false). Set send: true to send immediately. Provide either body (plain text) or html_body (rich HTML) or both — if both are provided, html_body is used. At least one of body or html_body is required.",
              "parameters": {
                "type": "object",
                "properties": {
                  "to": {"type":"array","items":{"type":"string"},"description":"Recipient email addresses"},
                  "subject": {"type":"string","description":"Email subject line"},
                  "body": {"type":"string","description":"Plain text body"},
                  "html_body": {"type":"string","description":"HTML body (takes precedence over body)"},
                  "cc": {"type":"array","items":{"type":"string"},"description":"CC recipients"},
                  "bcc": {"type":"array","items":{"type":"string"},"description":"BCC recipients"},
                  "from_account": {"type":"string","description":"Send from a specific account. Use the account prefix of a mailbox_path (e.g. 'iCloud' or 'Gmail'). If omitted, uses Mail's default account."},
                  "send": {"type":"boolean","description":"true = send immediately, false = open as draft for user review (default: false)"}
                },
                "required": ["to","subject"]
              },
              "requirements": ["automation"],
              "permission_policy": "ask"
            },
            {
              "id": "reply_to_message",
              "description": "Reply to an existing email. By default opens as a draft for user review. The original message is quoted automatically by Mail. Provide either body or html_body for the reply content. At least one of body or html_body is required.",
              "parameters": {
                "type": "object",
                "properties": {
                  "message_id": {"type":"string","description":"RFC Message-ID of the message to reply to"},
                  "body": {"type":"string","description":"Plain text reply body"},
                  "html_body": {"type":"string","description":"HTML reply body (takes precedence over body)"},
                  "reply_all": {"type":"boolean","description":"Reply to all recipients (default: false)"},
                  "send": {"type":"boolean","description":"true = send immediately, false = open as draft (default: false)"}
                },
                "required": ["message_id"]
              },
              "requirements": ["automation"],
              "permission_policy": "ask"
            },
            {
              "id": "move_message",
              "description": "Move a message to a different mailbox. Use list_mailboxes to get valid destination mailbox_path values. The destination must be in the same account as the message.",
              "parameters": {
                "type": "object",
                "properties": {
                  "message_id": {"type":"string","description":"RFC Message-ID of the message to move"},
                  "destination_mailbox_path": {"type":"string","description":"Target mailbox path (e.g. 'iCloud/Archive', 'Gmail/Trash')"}
                },
                "required": ["message_id","destination_mailbox_path"]
              },
              "requirements": ["automation"],
              "permission_policy": "ask"
            },
            {
              "id": "set_message_status",
              "description": "Update the read, flagged, or junk status of a message. Only the provided fields are changed — omitted fields are left as-is.",
              "parameters": {
                "type": "object",
                "properties": {
                  "message_id": {"type":"string","description":"RFC Message-ID of the message"},
                  "is_read": {"type":"boolean","description":"Set to true to mark as read, false to mark as unread"},
                  "is_flagged": {"type":"boolean","description":"Set to true to flag, false to unflag"},
                  "is_junk": {"type":"boolean","description":"Set to true to mark as junk, false to unmark"}
                },
                "required": ["message_id"]
              },
              "requirements": ["automation"],
              "permission_policy": "auto"
            },
            {
              "id": "get_thread",
              "description": "Get all messages in a conversation thread, ordered chronologically (oldest first). Provide any message_id from the thread. Returns summaries by default — set include_bodies to true to include message bodies. Thread detection is based on subject matching and In-Reply-To/References headers (best-effort).",
              "parameters": {
                "type": "object",
                "properties": {
                  "message_id": {"type":"string","description":"RFC Message-ID of any message in the thread"},
                  "include_bodies": {"type":"boolean","description":"Include message bodies in results (default: false). When false, returns same fields as list_messages."},
                  "max_body_length": {"type":"integer","description":"When include_bodies is true, truncate each body to this many characters (default: 5000)"}
                },
                "required": ["message_id"]
              },
              "requirements": ["automation"],
              "permission_policy": "ask"
            }
          ]
        }
      }
      """
    return makeCString(manifest)
  }

  api.invoke = { ctxPtr, typePtr, idPtr, payloadPtr in
    guard let ctxPtr = ctxPtr,
      let typePtr = typePtr,
      let idPtr = idPtr,
      let payloadPtr = payloadPtr
    else { return nil }

    let ctx = Unmanaged<PluginContext>.fromOpaque(ctxPtr).takeUnretainedValue()
    let type = String(cString: typePtr)
    let id = String(cString: idPtr)
    let payload = String(cString: payloadPtr)

    guard type == "tool" else {
      return makeCString(
        "{\"error\":\"unknown_capability\",\"message\":\"Unknown capability type: \(type)\"}")
    }

    let result: String
    switch id {
    case ctx.listMailboxes.name:
      result = ctx.listMailboxes.run(args: payload, cache: ctx.cache)
    case ctx.listMessages.name:
      result = ctx.listMessages.run(args: payload, cache: ctx.cache)
    case ctx.readMessage.name:
      result = ctx.readMessage.run(args: payload, cache: ctx.cache)
    case ctx.searchMessages.name:
      result = ctx.searchMessages.run(args: payload, cache: ctx.cache)
    case ctx.composeMessage.name:
      result = ctx.composeMessage.run(args: payload, cache: ctx.cache)
    case ctx.replyToMessage.name:
      result = ctx.replyToMessage.run(args: payload, cache: ctx.cache)
    case ctx.moveMessage.name:
      result = ctx.moveMessage.run(args: payload, cache: ctx.cache)
    case ctx.setMessageStatus.name:
      result = ctx.setMessageStatus.run(args: payload, cache: ctx.cache)
    case ctx.getThread.name:
      result = ctx.getThread.run(args: payload, cache: ctx.cache)
    default:
      result = "{\"error\":\"unknown_tool\",\"message\":\"Unknown tool: \(id)\"}"
    }

    return makeCString(result)
  }

  return api
}()

// MARK: - Entry Point

@_cdecl("osaurus_plugin_entry")
public func osaurus_plugin_entry() -> UnsafeRawPointer? {
  return UnsafeRawPointer(&api)
}
