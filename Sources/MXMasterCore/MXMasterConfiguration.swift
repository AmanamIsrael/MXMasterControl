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
  public static let currentSchemaVersion = 2

  public var schemaVersion: Int
  public var dpi: UInt16?
  public var smartShiftMode: SmartShiftMode?
  public var smartShiftThreshold: UInt8?
  public var wheelInverted: Bool?
  public var controlBindings: [MouseControlBinding]
  public var gestureNavigationEnabled: Bool
  public var gestureActions: GestureActions

  public init(
    schemaVersion: Int = Self.currentSchemaVersion,
    dpi: UInt16? = nil,
    smartShiftMode: SmartShiftMode? = nil,
    smartShiftThreshold: UInt8? = nil,
    wheelInverted: Bool? = nil,
    controlBindings: [MouseControlBinding] = [],
    gestureNavigationEnabled: Bool = false,
    gestureActions: GestureActions = GestureActions()
  ) {
    self.schemaVersion = schemaVersion
    self.dpi = dpi
    self.smartShiftMode = smartShiftMode
    self.smartShiftThreshold = smartShiftThreshold
    self.wheelInverted = wheelInverted
    self.controlBindings = controlBindings
    self.gestureNavigationEnabled = gestureNavigationEnabled
    self.gestureActions = gestureActions
  }

  public func action(for control: MouseControl) -> MouseAction {
    controlBindings.last(where: { $0.control == control })?.action ?? .systemDefault
  }

  public mutating func setAction(_ action: MouseAction, for control: MouseControl) {
    controlBindings.removeAll(where: { $0.control == control })
    if action != .systemDefault {
      controlBindings.append(MouseControlBinding(control: control, action: action))
    }
  }

  public var requiresAccessibility: Bool {
    if controlBindings.contains(where: { $0.action.postsKeyboardEvent }) { return true }
    guard gestureNavigationEnabled else { return false }
    return [
      gestureActions.click,
      gestureActions.up,
      gestureActions.down,
      gestureActions.left,
      gestureActions.right,
    ].contains(where: \.postsKeyboardEvent)
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case dpi
    case smartShiftMode
    case smartShiftThreshold
    case wheelInverted
    case controlBindings
    case gestureNavigationEnabled
    case gestureActions
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    dpi = try container.decodeIfPresent(UInt16.self, forKey: .dpi)
    smartShiftMode = try container.decodeIfPresent(SmartShiftMode.self, forKey: .smartShiftMode)
    smartShiftThreshold = try container.decodeIfPresent(UInt8.self, forKey: .smartShiftThreshold)
    wheelInverted = try container.decodeIfPresent(Bool.self, forKey: .wheelInverted)
    controlBindings =
      try container.decodeIfPresent([MouseControlBinding].self, forKey: .controlBindings) ?? []
    gestureNavigationEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .gestureNavigationEnabled) ?? false
    gestureActions =
      try container.decodeIfPresent(GestureActions.self, forKey: .gestureActions)
      ?? GestureActions()
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
    var config = try JSONDecoder().decode(
      MXMasterConfiguration.self,
      from: Data(contentsOf: fileURL)
    )
    guard config.schemaVersion <= MXMasterConfiguration.currentSchemaVersion else {
      throw ConfigurationStoreError.unsupportedSchema(config.schemaVersion)
    }
    config.schemaVersion = MXMasterConfiguration.currentSchemaVersion
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
