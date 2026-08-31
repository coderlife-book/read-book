import XCTest
@testable import ReadBookCore

final class ChapterParserTests: XCTestCase {
    func testRecognizesCommonChineseChapterFormsAndUsesUTF16Offsets() throws {
        let text = """
        序章
        开始
        第一章 风雪
        内容🙂
        第 502 章 新世界
        内容
        第12回 夜谈
        内容
        卷一 北境
        内容
        番外2
        """

        let chapters = try ChapterParser().parse(text)
        XCTAssertEqual(chapters.map(\.title), ["序章", "第一章 风雪", "第 502 章 新世界", "第12回 夜谈", "卷一 北境", "番外2"])

        let ns = text as NSString
        let expected = ns.range(of: "第 502 章 新世界").location
        let chapter502 = try XCTUnwrap(chapters.first { $0.title == "第 502 章 新世界" })
        XCTAssertEqual(chapter502.utf16Offset, expected)
    }

    func testRecognizesVolumeAndSpecialHeadings() throws {
        let text = "第一卷 北境\n正文\n楔子\n正文\n后记\n"
        XCTAssertEqual(try ChapterParser().parse(text).map(\.title), ["第一卷 北境", "楔子", "后记"])
    }

    func testRejectsLongBodyLinesThatContainChapterWords() throws {
        let text = "这是正文里提到第一章但并不是标题，因为这一整行明显是正常正文句子并且长度足够长，不应该被目录识别。"
        XCTAssertTrue(try ChapterParser().parse(text).isEmpty)
    }
}
