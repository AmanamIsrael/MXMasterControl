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
    wheelInverted: true,
    controlBindings: [MouseControlBinding(control: .smartShift, action: .missionControl)],
    gestureNavigationEnabled: true
  )

  try store.save(expected)
  #expect(try store.load() == expected)
}

@Test func configurationStoreMigratesSchemaOneWithoutActionFields() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = ConfigurationStore(fileURL: directory.appendingPathComponent("config.json"))
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try Data(#"{"schemaVersion":1,"dpi":1000}"#.utf8).write(to: store.fileURL)

  let migrated = try store.load()
  #expect(migrated.schemaVersion == MXMasterConfiguration.currentSchemaVersion)
  #expect(migrated.dpi == 1000)
  #expect(migrated.controlBindings.isEmpty)
  #expect(!migrated.gestureNavigationEnabled)
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
