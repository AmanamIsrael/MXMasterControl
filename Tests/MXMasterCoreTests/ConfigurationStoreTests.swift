import Foundation
import Testing

@testable import MXMasterCore

@Test func configurationStoreRoundTripsVersionedDesiredState() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = ConfigurationStore(fileURL: directory.appendingPathComponent("config.json"))
  let expected = MXMasterConfiguration(
    dpi: 1200,
    smartShiftMode: .ratchet,
    smartShiftThreshold: 14,
    wheelInverted: true
  )

  try store.save(expected)
  #expect(try store.load() == expected)
}

@Test func configurationStoreRejectsUnknownFutureSchema() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = ConfigurationStore(fileURL: directory.appendingPathComponent("config.json"))
  try store.save(MXMasterConfiguration(schemaVersion: 99))

  #expect(throws: ConfigurationStoreError.unsupportedSchema(99)) {
    try store.load()
  }
}
