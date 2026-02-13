import Foundation
import Testing

@testable import osaurus_mail

@Suite("Tool Argument Validation")
struct ToolValidationTests {
  let cache = MessageCache(capacity: 100)

  // MARK: - list_messages

  @Test("list_messages rejects invalid JSON")
  func listMessagesInvalidJSON() {
    let tool = ListMessagesTool()
    let result = tool.run(args: "not json", cache: cache)
    #expect(result.contains("invalid_parameter"))
  }

  @Test("list_messages rejects invalid mailbox path")
  func listMessagesInvalidMailbox() {
    let tool = ListMessagesTool()
    let result = tool.run(args: "{\"mailbox_path\": \"INBOX\"}", cache: cache)
    #expect(result.contains("mailbox_not_found"))
  }

  // MARK: - read_message

  @Test("read_message rejects invalid JSON")
  func readMessageInvalidJSON() {
    let tool = ReadMessageTool()
    let result = tool.run(args: "bad", cache: cache)
    #expect(result.contains("invalid_parameter"))
  }

  // MARK: - search_messages

  @Test("search_messages rejects invalid JSON")
  func searchMessagesInvalidJSON() {
    let tool = SearchMessagesTool()
    let result = tool.run(args: "{}", cache: cache)
    // Missing required "query" field -> decode fails
    #expect(result.contains("invalid_parameter"))
  }

  @Test("search_messages rejects invalid mailbox_path")
  func searchMessagesInvalidMailbox() {
    let tool = SearchMessagesTool()
    let result = tool.run(
      args: "{\"query\": \"test\", \"mailbox_path\": \"NoSlash\"}", cache: cache)
    #expect(result.contains("mailbox_not_found"))
  }

  // MARK: - compose_message

  @Test("compose_message rejects missing body")
  func composeMessageMissingBody() {
    let tool = ComposeMessageTool()
    let result = tool.run(args: "{\"to\": [\"a@b.com\"], \"subject\": \"Hi\"}", cache: cache)
    #expect(result.contains("missing_body"))
  }

  @Test("compose_message rejects invalid JSON")
  func composeMessageInvalidJSON() {
    let tool = ComposeMessageTool()
    let result = tool.run(args: "{}", cache: cache)
    // Missing required "to" and "subject"
    #expect(result.contains("invalid_parameter"))
  }

  // MARK: - reply_to_message

  @Test("reply_to_message rejects missing body")
  func replyMissingBody() {
    let tool = ReplyToMessageTool()
    let result = tool.run(args: "{\"message_id\": \"<abc@x>\"}", cache: cache)
    #expect(result.contains("missing_body"))
  }

  @Test("reply_to_message rejects invalid JSON")
  func replyInvalidJSON() {
    let tool = ReplyToMessageTool()
    let result = tool.run(args: "nope", cache: cache)
    #expect(result.contains("invalid_parameter"))
  }

  // MARK: - move_message

  @Test("move_message rejects invalid destination path")
  func moveMessageInvalidDest() {
    let tool = MoveMessageTool()
    let result = tool.run(
      args: "{\"message_id\": \"<abc@x>\", \"destination_mailbox_path\": \"NoDest\"}", cache: cache)
    #expect(result.contains("invalid_destination"))
  }

  @Test("move_message rejects invalid JSON")
  func moveMessageInvalidJSON() {
    let tool = MoveMessageTool()
    let result = tool.run(args: "bad", cache: cache)
    #expect(result.contains("invalid_parameter"))
  }

  // MARK: - set_message_status

  @Test("set_message_status rejects invalid JSON")
  func setStatusInvalidJSON() {
    let tool = SetMessageStatusTool()
    let result = tool.run(args: "bad", cache: cache)
    #expect(result.contains("invalid_parameter"))
  }

  // MARK: - get_thread

  @Test("get_thread rejects invalid JSON")
  func getThreadInvalidJSON() {
    let tool = GetThreadTool()
    let result = tool.run(args: "{}", cache: cache)
    // Missing required "message_id"
    #expect(result.contains("invalid_parameter"))
  }

  // MARK: - list_mailboxes (no required params, just check it doesn't crash on empty input)

  @Test("list_mailboxes accepts empty JSON")
  func listMailboxesEmpty() {
    let tool = ListMailboxesTool()
    // This will try to call AppleScript and likely fail (Mail not running in CI),
    // but it should return a structured error, not crash.
    let result = tool.run(args: "{}", cache: cache)
    // Should be valid JSON
    let data = result.data(using: .utf8)!
    let parsed = try? JSONSerialization.jsonObject(with: data)
    #expect(parsed != nil, "list_mailboxes should return valid JSON even on failure")
  }
}
