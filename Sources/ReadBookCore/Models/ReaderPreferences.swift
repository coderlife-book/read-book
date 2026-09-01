import Foundation

public enum ReadingMode: String, Codable, Sendable { case paginated, continuous }
public enum ReaderTheme: String, Codable, Sendable { case soft, light, dark }
public enum AppPresenceMode: String, Codable, Sendable { case widgetStyle, normal }
public enum BossModeProfile: String, Codable, Sendable { case floatingReading, concealed }
public enum ReaderWindowAppearance: String, Codable, Sendable { case card, frameless, transparent }

public struct ReaderPreferences: Codable, Equatable, Sendable {
    public var readingMode: ReadingMode
    public var fontFamily: String
    public var fontSize: Double
    public var lineSpacing: Double
    public var paragraphSpacing: Double
    public var theme: ReaderTheme
    public var textColorHex: String?
    public var alwaysOnTop: Bool
    public var appPresenceMode: AppPresenceMode
    public var bossModeEnabled: Bool
    public var bossModeProfile: BossModeProfile
    public var windowAppearance: ReaderWindowAppearance
    public var framelessBackgroundOpacity: Double
    public var speechRate: Double {
        didSet { speechRate = Self.clampSpeechRate(speechRate) }
    }

    public init(
        readingMode: ReadingMode,
        fontFamily: String,
        fontSize: Double,
        lineSpacing: Double,
        paragraphSpacing: Double,
        theme: ReaderTheme,
        textColorHex: String? = nil,
        alwaysOnTop: Bool,
        appPresenceMode: AppPresenceMode,
        bossModeEnabled: Bool = false,
        bossModeProfile: BossModeProfile = .floatingReading,
        windowAppearance: ReaderWindowAppearance = .card,
        framelessBackgroundOpacity: Double = 0.18,
        speechRate: Double = 1.0
    ) {
        self.readingMode = readingMode
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.paragraphSpacing = paragraphSpacing
        self.theme = theme
        self.textColorHex = textColorHex
        self.alwaysOnTop = alwaysOnTop
        self.appPresenceMode = appPresenceMode
        self.bossModeEnabled = bossModeEnabled
        self.bossModeProfile = bossModeProfile
        self.windowAppearance = windowAppearance
        self.framelessBackgroundOpacity = Self.clampFramelessOpacity(framelessBackgroundOpacity)
        self.speechRate = Self.clampSpeechRate(speechRate)
    }

    private enum CodingKeys: String, CodingKey {
        case readingMode
        case fontFamily
        case fontSize
        case lineSpacing
        case paragraphSpacing
        case theme
        case textColorHex
        case alwaysOnTop
        case appPresenceMode
        case bossModeEnabled
        case bossModeProfile
        case windowAppearance
        case framelessBackgroundOpacity
        case speechRate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        readingMode = try container.decode(ReadingMode.self, forKey: .readingMode)
        fontFamily = try container.decode(String.self, forKey: .fontFamily)
        fontSize = try container.decode(Double.self, forKey: .fontSize)
        lineSpacing = try container.decode(Double.self, forKey: .lineSpacing)
        paragraphSpacing = try container.decode(Double.self, forKey: .paragraphSpacing)
        theme = try container.decode(ReaderTheme.self, forKey: .theme)
        textColorHex = try container.decodeIfPresent(String.self, forKey: .textColorHex)
        alwaysOnTop = try container.decode(Bool.self, forKey: .alwaysOnTop)
        appPresenceMode = try container.decode(AppPresenceMode.self, forKey: .appPresenceMode)
        bossModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .bossModeEnabled) ?? false
        bossModeProfile = try container.decodeIfPresent(BossModeProfile.self, forKey: .bossModeProfile) ?? .floatingReading
        windowAppearance = try container.decodeIfPresent(ReaderWindowAppearance.self, forKey: .windowAppearance) ?? .card
        framelessBackgroundOpacity = Self.clampFramelessOpacity(
            try container.decodeIfPresent(Double.self, forKey: .framelessBackgroundOpacity) ?? 0.18
        )
        speechRate = Self.clampSpeechRate(
            try container.decodeIfPresent(Double.self, forKey: .speechRate) ?? 1.0
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(readingMode, forKey: .readingMode)
        try container.encode(fontFamily, forKey: .fontFamily)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(lineSpacing, forKey: .lineSpacing)
        try container.encode(paragraphSpacing, forKey: .paragraphSpacing)
        try container.encode(theme, forKey: .theme)
        try container.encodeIfPresent(textColorHex, forKey: .textColorHex)
        try container.encode(alwaysOnTop, forKey: .alwaysOnTop)
        try container.encode(appPresenceMode, forKey: .appPresenceMode)
        try container.encode(bossModeEnabled, forKey: .bossModeEnabled)
        try container.encode(bossModeProfile, forKey: .bossModeProfile)
        try container.encode(windowAppearance, forKey: .windowAppearance)
        try container.encode(framelessBackgroundOpacity, forKey: .framelessBackgroundOpacity)
        try container.encode(speechRate, forKey: .speechRate)
    }

    private static func clampFramelessOpacity(_ value: Double) -> Double {
        min(max(value, 0), 0.60)
    }

    private static func clampSpeechRate(_ value: Double) -> Double {
        min(max(value, 0.5), 1.5)
    }

    public static let defaults = ReaderPreferences(
        readingMode: .paginated,
        fontFamily: "PingFang SC",
        fontSize: 17,
        lineSpacing: 8,
        paragraphSpacing: 9,
        theme: .soft,
        textColorHex: nil,
        alwaysOnTop: false,
        appPresenceMode: .normal,
        bossModeEnabled: false,
        bossModeProfile: .floatingReading,
        windowAppearance: .card,
        framelessBackgroundOpacity: 0.18
    )
}
