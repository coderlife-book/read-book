import Foundation

public enum ReadingMode: String, Codable, Sendable { case paginated, continuous }
public enum ReaderTheme: String, Codable, Sendable { case soft, light, dark }
public enum AppPresenceMode: String, Codable, Sendable { case widgetStyle, normal }

public struct ReaderPreferences: Codable, Equatable, Sendable {
    public var readingMode: ReadingMode
    public var fontFamily: String
    public var fontSize: Double
    public var lineSpacing: Double
    public var paragraphSpacing: Double
    public var theme: ReaderTheme
    public var alwaysOnTop: Bool
    public var appPresenceMode: AppPresenceMode

    public init(
        readingMode: ReadingMode,
        fontFamily: String,
        fontSize: Double,
        lineSpacing: Double,
        paragraphSpacing: Double,
        theme: ReaderTheme,
        alwaysOnTop: Bool,
        appPresenceMode: AppPresenceMode
    ) {
        self.readingMode = readingMode
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.paragraphSpacing = paragraphSpacing
        self.theme = theme
        self.alwaysOnTop = alwaysOnTop
        self.appPresenceMode = appPresenceMode
    }

    public static let defaults = ReaderPreferences(
        readingMode: .paginated,
        fontFamily: "PingFang SC",
        fontSize: 17,
        lineSpacing: 8,
        paragraphSpacing: 9,
        theme: .soft,
        alwaysOnTop: false,
        appPresenceMode: .widgetStyle
    )
}
