import CoreFoundation
import Foundation
import XCTest
@testable import ReadBookCore

final class TextDecoderTests: XCTestCase {
    func testUTF8AndLineEndingNormalization() throws {
        let data = Data("第一章\r\n正文\r第二行".utf8)
        let result = try TextDecoder().decode(data)
        XCTAssertEqual(result.encoding, .utf8)
        XCTAssertEqual(result.text, "第一章\n正文\n第二行")
    }

    func testGB18030DecodesChineseText() throws {
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        ))
        let source = "第一章 罗兰与夜莺"
        let data = try XCTUnwrap(source.data(using: encoding))
        let result = try TextDecoder().decode(data)
        XCTAssertEqual(result.text, source)
        XCTAssertEqual(result.encoding, .gb18030)
    }

    func testBig5DoesNotGetMisclassifiedAsGB18030() throws {
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.big5.rawValue)
        ))
        let source = "第一章 羅蘭與夜鶯\n第二章 邊境小鎮"
        let data = try XCTUnwrap(source.data(using: encoding))
        let result = try TextDecoder().decode(data)
        XCTAssertEqual(result.text, source)
        XCTAssertEqual(result.encoding, .big5)
    }

    func testUTF16BOMIsDetected() throws {
        let source = "第一章\n正文"
        var data = Data([0xFF, 0xFE])
        data.append(try XCTUnwrap(source.data(using: .utf16LittleEndian)))
        let result = try TextDecoder().decode(data)
        XCTAssertEqual(result.text, source)
        XCTAssertEqual(result.encoding, .utf16LittleEndian)
    }

    func testEmptyInputFailsExplicitly() {
        XCTAssertThrowsError(try TextDecoder().decode(Data())) { error in
            XCTAssertEqual(error as? TextDecoderError, .emptyInput)
        }
    }
}
