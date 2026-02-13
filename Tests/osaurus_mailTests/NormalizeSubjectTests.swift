import Testing

@testable import osaurus_mail

@Suite("normalizeSubject")
struct NormalizeSubjectTests {

  @Test("strips Re: prefix")
  func stripRe() {
    #expect(normalizeSubject("Re: Hello World") == "Hello World")
  }

  @Test("strips Fwd: prefix")
  func stripFwd() {
    #expect(normalizeSubject("Fwd: Hello World") == "Hello World")
  }

  @Test("strips Fw: prefix")
  func stripFw() {
    #expect(normalizeSubject("Fw: Hello World") == "Hello World")
  }

  @Test("strips multiple Re: prefixes")
  func stripMultipleRe() {
    #expect(normalizeSubject("Re: Re: Re: Hello") == "Hello")
  }

  @Test("strips mixed Re: and Fwd: prefixes")
  func stripMixed() {
    #expect(normalizeSubject("Re: Fwd: Re: Hello") == "Hello")
  }

  @Test("case insensitive: RE:, re:, rE:")
  func caseInsensitive() {
    #expect(normalizeSubject("RE: Hello") == "Hello")
    #expect(normalizeSubject("re: Hello") == "Hello")
    #expect(normalizeSubject("rE: Hello") == "Hello")
    #expect(normalizeSubject("FWD: Hello") == "Hello")
  }

  @Test("leaves plain subjects unchanged")
  func plainSubject() {
    #expect(normalizeSubject("Q4 Budget Review") == "Q4 Budget Review")
  }

  @Test("trims whitespace")
  func trimsWhitespace() {
    #expect(normalizeSubject("  Re: Hello  ") == "Hello")
  }

  @Test("handles empty subject")
  func emptySubject() {
    #expect(normalizeSubject("") == "")
  }

  @Test("handles Re: with no following text")
  func reWithNoText() {
    #expect(normalizeSubject("Re: ") == "")
  }
}
