import Testing

@testable import osaurus_mail

@Suite("MailboxPath")
struct MailboxPathTests {

  @Test("simple path: you@gmail.com/INBOX")
  func simplePath() {
    let result = parseMailboxPath("you@gmail.com/INBOX")
    #expect(result != nil)
    #expect(result?.accountKey == "you@gmail.com")
    // mailbox/account are resolved at runtime into the `targetMailbox` variable
    #expect(result?.mailboxRef == "targetMailbox")
    // the account is resolved by a loop matching name or email
    #expect(result?.resolveScript.contains("set acctKey to \"you@gmail.com\"") == true)
    #expect(result?.resolveScript.contains("email addresses of a contains acctKey") == true)
    // the mailbox is resolved by iterating and matching the display name (not `mailbox "X" of`)
    #expect(result?.resolveScript.contains("if name of _mb is \"INBOX\"") == true)
    #expect(result?.resolveScript.contains("set targetMailbox to _container") == true)
  }

  @Test("name-based path still parses (backward compatible)")
  func namePath() {
    let result = parseMailboxPath("iCloud/INBOX")
    #expect(result != nil)
    #expect(result?.accountKey == "iCloud")
    #expect(result?.mailboxRef == "targetMailbox")
    #expect(result?.resolveScript.contains("set acctKey to \"iCloud\"") == true)
  }

  @Test("nested path resolves each segment by name")
  func nestedPath() {
    let result = parseMailboxPath("you@work.com/Work/Projects")
    #expect(result != nil)
    #expect(result?.accountKey == "you@work.com")
    #expect(result?.mailboxRef == "targetMailbox")
    #expect(result?.resolveScript.contains("if name of _mb is \"Work\"") == true)
    #expect(result?.resolveScript.contains("if name of _mb is \"Projects\"") == true)
  }

  @Test("Gmail special folder: you@gmail.com/All Mail")
  func gmailAllMail() {
    let result = parseMailboxPath("you@gmail.com/All Mail")
    #expect(result != nil)
    #expect(result?.accountKey == "you@gmail.com")
    #expect(result?.mailboxRef == "targetMailbox")
    #expect(result?.resolveScript.contains("if name of _mb is \"All Mail\"") == true)
  }

  @Test("no slash returns nil")
  func noSlash() {
    #expect(parseMailboxPath("INBOX") == nil)
  }

  @Test("empty account returns nil")
  func emptyAccount() {
    #expect(parseMailboxPath("/INBOX") == nil)
  }

  @Test("empty mailbox returns nil")
  func emptyMailbox() {
    #expect(parseMailboxPath("iCloud/") == nil)
  }

  @Test("empty string returns nil")
  func emptyString() {
    #expect(parseMailboxPath("") == nil)
  }

  // MARK: - escapeAppleScriptString

  @Test("escapes quotes in AppleScript strings")
  func escapeQuotes() {
    #expect(escapeAppleScriptString("hello \"world\"") == "hello \\\"world\\\"")
  }

  @Test("escapes backslashes in AppleScript strings")
  func escapeBackslashes() {
    #expect(escapeAppleScriptString("path\\to\\file") == "path\\\\to\\\\file")
  }

  @Test("leaves plain strings unchanged")
  func plainString() {
    #expect(escapeAppleScriptString("hello world") == "hello world")
  }
}
