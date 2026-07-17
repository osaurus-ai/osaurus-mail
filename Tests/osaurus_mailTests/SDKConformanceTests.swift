import Foundation
import OsaurusPluginKit
import OsaurusPluginTestSupport
import Testing

@testable import osaurus_mail

@Suite("SDK Conformance")
struct SDKConformanceTests {

  @Test("manifest passes SDK registry conformance")
  func manifestConformance() throws {
    try ManifestConformance.assertConformant(mailManifestJSON)
  }

  @Test("v2 entry point returns a conformant plugin API table")
  func abiConformanceV2() throws {
    try ABIConformance.assertEntryConformance(
      osaurus_plugin_entry_v2(nil), manifestJSON: mailManifestJSON)
  }

  @Test("legacy v1 entry point returns a conformant plugin API table")
  func abiConformanceV1() throws {
    try ABIConformance.assertEntryConformance(
      osaurus_plugin_entry(), manifestJSON: mailManifestJSON)
  }

  @Test("invalid-parameter failures render the canonical failure envelope")
  func canonicalFailureShape() throws {
    try assertCanonicalFailure(
      MailPluginError.invalidParameter.json(message: "bad argument"), kind: .invalidArgs)
    try assertCanonicalFailure(
      canonicalErrorEnvelope(
        kind: "not_found", message: "Unknown tool: nope", retryable: false, code: "unknown_tool"),
      kind: .notFound)
  }
}
