import Foundation
import Testing

@testable import osaurus_mail

@Suite("Plugin Manifest")
struct ManifestTests {

  /// Call the public entry point and extract the manifest JSON.
  private func loadManifest() throws -> [String: Any] {
    guard let apiPtr = osaurus_plugin_entry() else {
      throw ManifestError.entryPointFailed
    }

    // The API struct layout: free_string, init, destroy, get_manifest, invoke
    // Each is an optional function pointer (8 bytes on 64-bit).
    // get_manifest is at offset 3 (index 3).
    let fnPtrSize = MemoryLayout<UnsafeRawPointer?>.stride

    // Call init to get a context
    let initPtr = apiPtr.load(
      fromByteOffset: fnPtrSize * 1, as: (@convention(c) () -> UnsafeMutableRawPointer?).self)
    let ctx = initPtr()

    // Call get_manifest
    let getManifestPtr = apiPtr.load(
      fromByteOffset: fnPtrSize * 3,
      as: (@convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?).self)
    guard let cStr = getManifestPtr(ctx) else {
      throw ManifestError.nilManifest
    }
    let jsonStr = String(cString: cStr)

    // Free the string
    let freeStringPtr = apiPtr.load(
      fromByteOffset: fnPtrSize * 0, as: (@convention(c) (UnsafePointer<CChar>?) -> Void).self)
    freeStringPtr(cStr)

    // Destroy context
    let destroyPtr = apiPtr.load(
      fromByteOffset: fnPtrSize * 2, as: (@convention(c) (UnsafeMutableRawPointer?) -> Void).self)
    destroyPtr(ctx)

    guard let data = jsonStr.data(using: .utf8),
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw ManifestError.invalidJSON
    }

    return obj
  }

  /// Call the public entry point's `invoke` function pointer and parse the JSON result.
  private func invoke(type: String, id: String, payload: String) throws -> [String: Any] {
    guard let apiPtr = osaurus_plugin_entry() else {
      throw ManifestError.entryPointFailed
    }
    let fnPtrSize = MemoryLayout<UnsafeRawPointer?>.stride

    let initPtr = apiPtr.load(
      fromByteOffset: fnPtrSize * 1, as: (@convention(c) () -> UnsafeMutableRawPointer?).self)
    let ctx = initPtr()

    // invoke is at offset 4: (ctx, type, id, payload) -> char*
    let invokePtr = apiPtr.load(
      fromByteOffset: fnPtrSize * 4,
      as: (@convention(c) (
        UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?,
        UnsafePointer<CChar>?
      ) -> UnsafePointer<CChar>?).self)

    let result = type.withCString { t in
      id.withCString { i in
        payload.withCString { p in invokePtr(ctx, t, i, p) }
      }
    }
    guard let cStr = result else {
      throw ManifestError.nilManifest
    }
    let jsonStr = String(cString: cStr)

    let freeStringPtr = apiPtr.load(
      fromByteOffset: fnPtrSize * 0, as: (@convention(c) (UnsafePointer<CChar>?) -> Void).self)
    freeStringPtr(cStr)

    let destroyPtr = apiPtr.load(
      fromByteOffset: fnPtrSize * 2, as: (@convention(c) (UnsafeMutableRawPointer?) -> Void).self)
    destroyPtr(ctx)

    guard let data = jsonStr.data(using: .utf8),
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw ManifestError.invalidJSON
    }
    return obj
  }

  enum ManifestError: Error {
    case entryPointFailed
    case nilManifest
    case invalidJSON
  }

  @Test("manifest is valid JSON with correct plugin_id")
  func pluginID() throws {
    let manifest = try loadManifest()
    #expect(manifest["plugin_id"] as? String == "osaurus.mail")
  }

  @Test("manifest has correct version")
  func version() throws {
    let manifest = try loadManifest()
    #expect(manifest["version"] as? String == "0.1.0")
  }

  @Test("manifest display name is Mail")
  func displayName() throws {
    let manifest = try loadManifest()
    #expect(manifest["name"] as? String == "Mail")
  }

  @Test("every tool declares an id and a description")
  func everyToolHasIdAndDescription() throws {
    let manifest = try loadManifest()
    let capabilities = manifest["capabilities"] as? [String: Any]
    let tools = capabilities?["tools"] as? [[String: Any]] ?? []

    #expect(!tools.isEmpty, "manifest should declare at least one tool")
    for tool in tools {
      let id = tool["id"] as? String
      #expect(id != nil && !(id!).isEmpty, "every tool must have a non-empty id")
      let description = tool["description"] as? String
      #expect(
        description != nil && !(description!).isEmpty,
        "tool '\(id ?? "unknown")' must have a non-empty description")
    }
  }

  @Test("unknown capability type returns a canonical failure envelope")
  func unknownCapabilityFallback() throws {
    let validKinds: Set<String> = ["invalid_args", "execution_error", "not_found", "unavailable"]
    let obj = try invoke(type: "resource", id: "whatever", payload: "{}")

    #expect(obj["ok"] as? Bool == false)
    let kind = obj["kind"] as? String
    #expect(kind != nil && validKinds.contains(kind!))
    #expect(kind == "invalid_args")
    #expect(obj["retryable"] as? Bool == false)
  }

  @Test("unknown tool returns a canonical failure envelope")
  func unknownToolFallback() throws {
    let validKinds: Set<String> = ["invalid_args", "execution_error", "not_found", "unavailable"]
    let obj = try invoke(type: "tool", id: "does_not_exist", payload: "{}")

    #expect(obj["ok"] as? Bool == false)
    let kind = obj["kind"] as? String
    #expect(kind != nil && validKinds.contains(kind!))
    #expect(kind == "not_found")
    #expect(obj["retryable"] as? Bool == false)
  }

  @Test("manifest declares all 9 tools")
  func toolCount() throws {
    let manifest = try loadManifest()
    let capabilities = manifest["capabilities"] as? [String: Any]
    let tools = capabilities?["tools"] as? [[String: Any]]
    #expect(tools?.count == 9)
  }

  @Test("manifest tool IDs match expected set")
  func toolIDs() throws {
    let manifest = try loadManifest()
    let capabilities = manifest["capabilities"] as? [String: Any]
    let tools = capabilities?["tools"] as? [[String: Any]] ?? []
    let ids = Set(tools.compactMap { $0["id"] as? String })

    let expected: Set<String> = [
      "list_mailboxes", "list_messages", "read_message", "search_messages",
      "compose_message", "reply_to_message", "move_message",
      "set_message_status", "get_thread",
    ]
    #expect(ids == expected)
  }

  @Test("all tools declare automation requirement")
  func automationRequirement() throws {
    let manifest = try loadManifest()
    let capabilities = manifest["capabilities"] as? [String: Any]
    let tools = capabilities?["tools"] as? [[String: Any]] ?? []

    for tool in tools {
      let requirements = tool["requirements"] as? [String] ?? []
      #expect(
        requirements.contains("automation"),
        "Tool '\(tool["id"] ?? "unknown")' missing automation requirement")
    }
  }

  @Test("read-only tools have auto permission, write tools have ask")
  func permissionPolicies() throws {
    let manifest = try loadManifest()
    let capabilities = manifest["capabilities"] as? [String: Any]
    let tools = capabilities?["tools"] as? [[String: Any]] ?? []

    let autoTools: Set<String> = [
      "list_mailboxes", "list_messages", "search_messages", "set_message_status",
    ]
    let askTools: Set<String> = [
      "read_message", "compose_message", "reply_to_message", "move_message", "get_thread",
    ]

    for tool in tools {
      let id = tool["id"] as? String ?? ""
      let policy = tool["permission_policy"] as? String ?? ""
      if autoTools.contains(id) {
        #expect(policy == "auto", "Tool '\(id)' should have auto permission")
      } else if askTools.contains(id) {
        #expect(policy == "ask", "Tool '\(id)' should have ask permission")
      }
    }
  }

  @Test("tools with required parameters declare them")
  func requiredParameters() throws {
    let manifest = try loadManifest()
    let capabilities = manifest["capabilities"] as? [String: Any]
    let tools = capabilities?["tools"] as? [[String: Any]] ?? []

    let toolMap = Dictionary(uniqueKeysWithValues: tools.map { ($0["id"] as! String, $0) })

    // list_messages requires mailbox_path
    let lmParams = toolMap["list_messages"]?["parameters"] as? [String: Any]
    let lmRequired = lmParams?["required"] as? [String] ?? []
    #expect(lmRequired.contains("mailbox_path"))

    // read_message requires message_id
    let rmParams = toolMap["read_message"]?["parameters"] as? [String: Any]
    let rmRequired = rmParams?["required"] as? [String] ?? []
    #expect(rmRequired.contains("message_id"))

    // search_messages requires query
    let smParams = toolMap["search_messages"]?["parameters"] as? [String: Any]
    let smRequired = smParams?["required"] as? [String] ?? []
    #expect(smRequired.contains("query"))

    // compose_message requires to, subject
    let cmParams = toolMap["compose_message"]?["parameters"] as? [String: Any]
    let cmRequired = cmParams?["required"] as? [String] ?? []
    #expect(cmRequired.contains("to"))
    #expect(cmRequired.contains("subject"))

    // move_message requires message_id, destination_mailbox_path
    let mmParams = toolMap["move_message"]?["parameters"] as? [String: Any]
    let mmRequired = mmParams?["required"] as? [String] ?? []
    #expect(mmRequired.contains("message_id"))
    #expect(mmRequired.contains("destination_mailbox_path"))
  }
}
