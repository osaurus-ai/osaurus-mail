import Foundation
import OsaurusPluginKit
import Testing

@testable import osaurus_mail

@Suite("Errors & JSON Helpers")
struct ErrorsTests {

  // MARK: - MailPluginError.json

  @Test("error JSON emits the canonical host envelope")
  func errorJsonStructure() {
    let json = MailPluginError.mailNotRunning.json(message: "Mail is not open")
    let data = json.data(using: .utf8)!
    let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]

    // The host classifies a result as a failure only when ok==false with a valid kind.
    #expect(obj["ok"] as? Bool == false)
    #expect(obj["kind"] as? String == "unavailable")
    #expect(obj["retryable"] as? Bool == false)
    #expect(obj["code"] as? String == "mail_not_running")
    #expect(obj["message"] as? String == "Mail is not open")
  }

  @Test("error JSON escapes special characters in message")
  func errorJsonEscapesMessage() {
    let json = MailPluginError.messageNotFound.json(message: "Can't find \"<abc@x>\"")
    let data = json.data(using: .utf8)!
    let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]

    #expect(obj["ok"] as? Bool == false)
    #expect(obj["kind"] as? String == "not_found")
    #expect(obj["retryable"] as? Bool == false)
    #expect(obj["code"] as? String == "message_not_found")
    #expect(obj["message"] as? String == "Can't find \"<abc@x>\"")
  }

  @Test("every error code maps to a valid kind and includes ok/retryable")
  func errorEnvelopeIsCanonical() {
    let validKinds: Set<String> = [
      "invalid_args", "execution_error", "not_found", "unavailable", "timeout",
    ]
    let allCases: [MailPluginError] = [
      .mailNotRunning, .permissionDenied, .mailboxNotFound, .messageNotFound,
      .invalidDestination, .sendFailed, .missingBody, .invalidParameter, .timeout,
    ]

    for err in allCases {
      let json = err.json(message: "boom")
      let data = json.data(using: .utf8)!
      let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]

      #expect(obj["ok"] as? Bool == false, "\(err.rawValue) must have ok == false")
      let kind = obj["kind"] as? String
      #expect(kind != nil && validKinds.contains(kind!), "\(err.rawValue) has invalid kind")
      #expect(obj["retryable"] as? Bool != nil, "\(err.rawValue) must include retryable")
      #expect(obj["code"] as? String == err.rawValue)
    }
  }

  @Test("error kinds map per the host contract")
  func errorKindMapping() {
    #expect(MailPluginError.mailNotRunning.kind == "unavailable")
    #expect(MailPluginError.permissionDenied.kind == "unavailable")
    #expect(MailPluginError.mailboxNotFound.kind == "not_found")
    #expect(MailPluginError.messageNotFound.kind == "not_found")
    #expect(MailPluginError.invalidDestination.kind == "invalid_args")
    #expect(MailPluginError.missingBody.kind == "invalid_args")
    #expect(MailPluginError.invalidParameter.kind == "invalid_args")
    #expect(MailPluginError.sendFailed.kind == "execution_error")
    #expect(MailPluginError.timeout.kind == "timeout")

    #expect(MailPluginError.mailNotRunning.retryable == false)
    #expect(MailPluginError.permissionDenied.retryable == false)
    #expect(MailPluginError.mailboxNotFound.retryable == false)
    #expect(MailPluginError.messageNotFound.retryable == false)
    // invalid_args failures are deterministic — retrying the same arguments cannot succeed
    #expect(MailPluginError.invalidDestination.retryable == false)
    #expect(MailPluginError.missingBody.retryable == false)
    #expect(MailPluginError.invalidParameter.retryable == false)
    #expect(MailPluginError.sendFailed.retryable == true)
    #expect(MailPluginError.timeout.retryable == true)
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
    #expect(MailPluginError.timeout.rawValue == "timeout")
  }

  // MARK: - Envelope.escape (SDK; replaced the local jsonEscapeString)

  @Test("escapes quotes")
  func escapeQuotes() {
    #expect(Envelope.escape("say \"hello\"") == "say \\\"hello\\\"")
  }

  @Test("escapes backslashes")
  func escapeBackslashes() {
    #expect(Envelope.escape("a\\b") == "a\\\\b")
  }

  @Test("escapes newlines and tabs")
  func escapeWhitespace() {
    #expect(Envelope.escape("line1\nline2\ttab") == "line1\\nline2\\ttab")
  }

  @Test("escapes carriage returns")
  func escapeCarriageReturn() {
    #expect(Envelope.escape("hello\rworld") == "hello\\rworld")
  }

  @Test("leaves normal text unchanged")
  func normalText() {
    #expect(Envelope.escape("hello world 123") == "hello world 123")
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
