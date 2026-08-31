import Foundation

public struct ReaderTextStyle: Equatable, Sendable {
    public var fontFamily: String
    public var fontSize: Double
    public var lineSpacing: Double
    public var paragraphSpacing: Double
    public var horizontalPadding: Double
    public var verticalPadding: Double

    public init(
        fontFamily: String,
        fontSize: Double,
        lineSpacing: Double,
        paragraphSpacing: Double,
        horizontalPadding: Double,
        verticalPadding: Double
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.paragraphSpacing = paragraphSpacing
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    public static let `default` = ReaderTextStyle(
        fontFamily: "PingFang SC",
        fontSize: 17,
        lineSpacing: 8,
        paragraphSpacing: 9,
        horizontalPadding: 22,
        verticalPadding: 20
    )
}

public struct LayoutSignature: Hashable, Sendable {
    public let widthHalfPoints: Int
    public let heightHalfPoints: Int
    public let fontFamily: String
    public let fontSizeTenths: Int
    public let lineSpacingTenths: Int
    public let paragraphSpacingTenths: Int
    public let horizontalPaddingTenths: Int
    public let verticalPaddingTenths: Int

    public init(width: Double, height: Double, style: ReaderTextStyle) {
        widthHalfPoints = Int((width * 2).rounded())
        heightHalfPoints = Int((height * 2).rounded())
        fontFamily = style.fontFamily
        fontSizeTenths = Int((style.fontSize * 10).rounded())
        lineSpacingTenths = Int((style.lineSpacing * 10).rounded())
        paragraphSpacingTenths = Int((style.paragraphSpacing * 10).rounded())
        horizontalPaddingTenths = Int((style.horizontalPadding * 10).rounded())
        verticalPaddingTenths = Int((style.verticalPadding * 10).rounded())
    }
}
