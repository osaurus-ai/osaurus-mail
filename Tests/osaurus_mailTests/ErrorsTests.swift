import Foundation
import Testing

@testable import osaurus_mail

@Suite("Errors & JSON Helpers")
struct ErrorsTests {

  // MARK: - MailPluginError.json

  @Test("error JSON has correct structure")
  func errorJsonStructure() {
    let json = MailPluginError.mailNotRunning.json(message: "Mail is not open")
    let data = json.data(using: .utf8)!
    let obj = try! JSONSerialization.jsonObject(with: data) as! [String: String]

    #expect(obj["error"] == "mail_not_running")
    #expect(obj["message"] == "Mail is not open")
  }

  @Test("error JSON escapes special characters in message")
  func errorJsonEscapesMessage() {
    let json = MailPluginError.messageNotFound.json(message: "Can't find \"<abc@x>\"")
    let data = json.data(using: .utf8)!
    let obj = try! JSONSerialization.jsonObject(with: data) as! [String: String]

    #expect(obj["error"] == "message_not_found")
    #expect(obj["message"] == "Can't find \"<abc@x>\"")
  }

  @Test("all error codes have correct raw values")
  func errorCodes() {
    #expect(MailPluginError.mailNotRunning.rawValue == "mail_not_running")
    #expect(MailPluginError.permissionDenied.rawValue == "permission_denied")
    #expect(MailPluginError.mailboxNotFound.rawValue == "mailbox_not_found")
    #expect(MailPluginError.messageNotFound.rawValue == "message_not_found")
    #expect(MailPluginError.invalidDestination.rawValue == "invalid_destination")
    #expect(MailPluginError.sendFailed.rawValue == "send_failed")
    #expect(MailPluginError.missingBody.rawValue == "missing_body")
    #expect(MailPluginError.invalidParameter.rawValue == "invalid_parameter")
  }

  // MARK: - jsonEscapeString

  @Test("escapes quotes")
  func escapeQuotes() {
    #expect(jsonEscapeString("say \"hello\"") == "say \\\"hello\\\"")
  }

  @Test("escapes backslashes")
  func escapeBackslashes() {
    #expect(jsonEscapeString("a\\b") == "a\\\\b")
  }

  @Test("escapes newlines and tabs")
  func escapeWhitespace() {
    #expect(jsonEscapeString("line1\nline2\ttab") == "line1\\nline2\\ttab")
  }

  @Test("escapes carriage returns")
  func escapeCarriageReturn() {
    #expect(jsonEscapeString("hello\rworld") == "hello\\rworld")
  }

  @Test("leaves normal text unchanged")
  func normalText() {
    #expect(jsonEscapeString("hello world 123") == "hello world 123")
  }

  // MARK: - jsonEncode

  @Test("encodes simple dictionary")
  func encodeDictionary() {
    let result = jsonEncode(["key": "value"])
    let data = result.data(using: .utf8)!
    let obj = try! JSONSerialization.jsonObject(with: data) as! [String: String]
    #expect(obj["key"] == "value")
  }

  @Test("encodes nested structure")
  func encodeNested() {
    let input: [String: Any] = [
      "count": 5,
      "items": ["a", "b"],
    ]
    let result = jsonEncode(input)
    let data = result.data(using: .utf8)!
    let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(obj["count"] as? Int == 5)
    #expect(obj["items"] as? [String] == ["a", "b"])
  }

  @Test("encodes booleans correctly")
  func encodeBooleans() {
    let result = jsonEncode(["flag": true])
    let data = result.data(using: .utf8)!
    let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Bool]
    #expect(obj["flag"] == true)
  }
}
