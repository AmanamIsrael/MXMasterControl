import Foundation

public enum SmartShiftMode: UInt8, Codable, CaseIterable, Sendable {
  case freeSpin = 1
  case ratchet = 2

  public var title: String {
    switch self {
    case .freeSpin: "Free Spin"
    case .ratchet: "Ratchet"
    }
  }
}

public struct MXMasterConfiguration: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public var schemaVersion: Int
  public var dpi: UInt16?
  public var smartShiftMode: SmartShiftMode?
  public var smartShiftThreshold: UInt8?
  public var wheelInverted: Bool?

  public init(
    schemaVersion: Int = Self.currentSchemaVersion,
    dpi: UInt16? = nil,
    smartShiftMode: SmartShiftMode? = nil,
    smartShiftThreshold: UInt8? = nil,
    wheelInverted: Bool? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.dpi = dpi
    self.smartShiftMode = smartShiftMode
    self.smartShiftThreshold = smartShiftThreshold
    self.wheelInverted = wheelInverted
  }
}

public enum ConfigurationStoreError: LocalizedError, Equatable {
  case unsupportedSchema(Int)

  public var errorDescription: String? {
    switch self {
    case .unsupportedSchema(let version):
      "Configuration schema \(version) is newer than this app supports."
    }
  }
}

public struct ConfigurationStore: Sendable {
  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public func load() throws -> MXMasterConfiguration {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return MXMasterConfiguration()
    }
    let config = try JSONDecoder().decode(
      MXMasterConfiguration.self,
      from: Data(contentsOf: fileURL)
    )
    guard config.schemaVersion <= MXMasterConfiguration.currentSchemaVersion else {
      throw ConfigurationStoreError.unsupportedSchema(config.schemaVersion)
    }
    return config
  }

  public func save(_ configuration: MXMasterConfiguration) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(configuration).write(to: fileURL, options: .atomic)
  }
}
