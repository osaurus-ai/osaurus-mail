import Foundation
import Testing

@testable import osaurus_mail

@Suite("Date Formatting")
struct DateFormattingTests {

  // MARK: - appleScriptDateBinding

  @Test("binds the date from numeric components, never a locale-dependent literal")
  func bindsNumericComponents() throws {
    let script = try #require(appleScriptDateBinding("sinceDate", iso8601: "2026-02-13T09:30:00Z"))
    #expect(script.contains("set sinceDate to current date"))
    #expect(script.contains("set year of sinceDate to 2026"))
    #expect(script.contains("set month of sinceDate to "))
    #expect(script.contains("set day of sinceDate to "))
    #expect(script.contains("set time of sinceDate to "))
    // issue #13: `date "February 13, 2026 …"` only compiles on English systems
    #expect(!script.contains("date \""))
    #expect(!script.contains("February"))
  }

  @Test("resets day to 1 before setting year and month")
  func resetsDayFirst() throws {
    let script = try #require(appleScriptDateBinding("d", iso8601: "2026-03-31T12:00:00Z"))
    let lines = script.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    let reset = try #require(lines.firstIndex(of: "set day of d to 1"))
    let year = try #require(lines.firstIndex(of: "set year of d to 2026"))
    let month = try #require(lines.firstIndex { $0.hasPrefix("set month of d to ") })
    let day = try #require(lines.lastIndex { $0.hasPrefix("set day of d to ") })
    #expect(reset < year && year < month && month < day)
  }

  @Test("expresses the instant in the local time zone")
  func usesLocalTimeZone() throws {
    let script = try #require(appleScriptDateBinding("d", iso8601: "2026-02-13T09:30:00Z"))
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .current
    let date = try #require(parseISO8601Date("2026-02-13T09:30:00Z"))
    let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    let seconds = c.hour! * 3600 + c.minute! * 60 + c.second!
    #expect(script.contains("set year of d to \(c.year!)"))
    #expect(script.contains("set month of d to \(c.month!)"))
    #expect(script.contains("set day of d to \(c.day!)"))
    #expect(script.contains("set time of d to \(seconds)"))
  }

  @Test("handles fractional seconds")
  func fractionalSeconds() throws {
    let script = try #require(appleScriptDateBinding("d", iso8601: "2026-02-13T09:30:00.123Z"))
    #expect(script.contains("set year of d to 2026"))
  }

  @Test("accepts bare dates")
  func bareDate() throws {
    // Midnight UTC renders in the local timezone, so only assert the year.
    let script = try #require(appleScriptDateBinding("d", iso8601: "2026-02-13"))
    #expect(script.contains("set year of d to 2026"))
  }

  @Test("returns nil for invalid dates")
  func invalidDate() {
    #expect(appleScriptDateBinding("d", iso8601: "not-a-date") == nil)
    #expect(appleScriptDateBinding("d", iso8601: "2026-13-45T99:99:99Z") == nil)
    #expect(appleScriptDateBinding("d", iso8601: "") == nil)
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
