import Testing

@testable import osaurus_mail

@Suite("Date Formatting")
struct DateFormattingTests {

  // MARK: - formatDateForAppleScript

  @Test("converts ISO 8601 to AppleScript date format")
  func convertISOToAppleScript() throws {
    let result = try #require(formatDateForAppleScript("2026-02-13T09:30:00Z"))
    // Should produce something like "February 13, 2026 9:30:00 AM"
    #expect(result.contains("2026"))
    #expect(result.contains("February") || result.contains("02"))
    #expect(result.contains("13"))
  }

  @Test("handles fractional seconds")
  func fractionalSeconds() throws {
    let result = try #require(formatDateForAppleScript("2026-02-13T09:30:00.123Z"))
    #expect(result.contains("2026"))
  }

  @Test("accepts bare dates")
  func bareDate() throws {
    // Midnight UTC renders in the local timezone, so only assert the year.
    let result = try #require(formatDateForAppleScript("2026-02-13"))
    #expect(result.contains("2026"))
  }

  @Test("returns nil for invalid dates")
  func invalidDate() {
    #expect(formatDateForAppleScript("not-a-date") == nil)
    #expect(formatDateForAppleScript("2026-13-45T99:99:99Z") == nil)
    #expect(formatDateForAppleScript("") == nil)
  }

  // MARK: - formatISO8601

  @Test("appends Z to bare ISO dates")
  func appendsZ() {
    #expect(formatISO8601("2026-02-13T09:34:00") == "2026-02-13T09:34:00Z")
  }

  @Test("preserves existing Z suffix")
  func preservesZ() {
    #expect(formatISO8601("2026-02-13T09:34:00Z") == "2026-02-13T09:34:00Z")
  }

  @Test("preserves positive UTC offset")
  func preservesPositiveOffset() {
    #expect(formatISO8601("2026-02-13T09:34:00+05:30") == "2026-02-13T09:34:00+05:30")
  }

  @Test("preserves negative UTC offset")
  func preservesNegativeOffset() {
    #expect(formatISO8601("2026-02-13T04:34:00-05:00") == "2026-02-13T04:34:00-05:00")
  }

  @Test("trims whitespace")
  func trimsWhitespace() {
    #expect(formatISO8601("  2026-02-13T09:34:00  ") == "2026-02-13T09:34:00Z")
  }
}
