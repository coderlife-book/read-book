# ReadBook macOS Reader V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS 26+ personal TXT novel reader that looks like a desktop widget, supports paginated and continuous reading, preserves position, manages multiple local books, and can switch between Dock-visible and widget-style operation.

**Architecture:** Use a Swift Package with a testable `ReadBookCore` library target and a native `ReadBook` SwiftUI executable target. Core owns models, TXT decoding, chapter parsing, local library persistence, reading position, settings, and TextKit pagination; the app target owns SwiftUI/AppKit views, the widget-like window, menu bar presence, drag/drop, and keyboard/trackpad interaction. Package the release executable into a normal `.app` bundle with a small local build script so no third-party project generator is required.

**Tech Stack:** Swift 6, SwiftUI, AppKit, TextKit 1 (`NSTextStorage`/`NSLayoutManager`/`NSTextContainer`), Foundation, CoreFoundation, XCTest, Swift Package Manager.

**Spec:** `docs/superpowers/specs/2026-08-31-macos-reader-design.md`

## Global Constraints

- Minimum supported OS: macOS 26.
- Primary architecture: SwiftUI by default; use AppKit where precise window/application/text behavior is required.
- Backend: none.
- Network: none.
- Imported source format in V1: `.txt` only.
- Imported books are copied into ReadBook-managed local storage and normalized to UTF-8.
- Canonical reading position is UTF-16 offset, never page number.
- Reading modes are manual: paginated and continuous scrolling.
- Paginated layout must use actual TextKit measurement; fixed character-count pagination is prohibited.
- V1 must remain fully local/offline and must not add Supabase, iCloud, accounts, EPUB/PDF/MOBI, TTS, AI features, notes, highlights, full-text search, cover management, tags, iOS, or WidgetKit.
- Default reader window: approximately 360 x 260 pt; minimum approximately 280 x 180 pt.
- Default app-presence mode: widget-style (`NSApplication.ActivationPolicy.accessory`) with menu bar entry; user can switch to normal Dock-visible mode.
- Imported novel content and per-book metadata must be recoverable independently from derived caches.

---

## File Map

The implementation should converge on this structure:

```text
Package.swift
README.md
Scripts/
  build-app.sh
Sources/
  ReadBookCore/
    Models/
      BookPosition.swift
      Chapter.swift
      BookMetadata.swift
      ReaderPreferences.swift
    Storage/
      AppPaths.swift
      JSONFileStore.swift
      LibraryRepository.swift
    Import/
      TextDecoder.swift
      ChapterParser.swift
    Reader/
      ReaderSession.swift
      ReaderTextStyle.swift
      PaginationEngine.swift
      PageCache.swift
    Settings/
      PreferencesStore.swift
  ReadBook/
    App/
      ReadBookApp.swift
      AppModel.swift
    Reader/
      ReaderRootView.swift
      PaginatedReaderView.swift
      PagedTextView.swift
      ContinuousReaderView.swift
      ContinuousTextView.swift
      ReaderToolbar.swift
    Library/
      LibraryPopoverView.swift
      ChapterListView.swift
      ImportDropHandler.swift
    Settings/
      SettingsView.swift
      ThemePalette.swift
    Window/
      WindowAccessor.swift
      WindowCoordinator.swift
      WindowRegistry.swift
      HorizontalScrollPager.swift
Tests/
  ReadBookCoreTests/
    ModelsTests.swift
    ChapterParserTests.swift
    TextDecoderTests.swift
    LibraryRepositoryTests.swift
    PreferencesStoreTests.swift
    PaginationEngineTests.swift
    ReaderSessionTests.swift
    Fixtures/
      utf8-novel.txt
      chapter-patterns.txt
      large-novel-generator.swift
```

`ReadBookCore` must not import SwiftUI. It may import AppKit only in the TextKit pagination files. App-target files may import both SwiftUI and AppKit.

---

### Task 1: Bootstrap the package, core models, and local `.app` packaging

**Files:**
- Create: `Package.swift`
- Create: `Sources/ReadBookCore/Models/BookPosition.swift`
- Create: `Sources/ReadBookCore/Models/Chapter.swift`
- Create: `Sources/ReadBookCore/Models/BookMetadata.swift`
- Create: `Sources/ReadBookCore/Models/ReaderPreferences.swift`
- Create: `Sources/ReadBook/App/ReadBookApp.swift`
- Create: `Scripts/build-app.sh`
- Create: `Tests/ReadBookCoreTests/ModelsTests.swift`

**Interfaces:**
- Produces: `BookPosition`, `Chapter`, `BookMetadata`, `LibraryIndex`, `ReadingMode`, `ReaderTheme`, `AppPresenceMode`, `ReaderPreferences`.
- Produces build commands: `swift test`, `swift run ReadBook`, `Scripts/build-app.sh`.

- [ ] **Step 1: Create the package manifest and failing model tests**

Create `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReadBook",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ReadBookCore", targets: ["ReadBookCore"]),
        .executable(name: "ReadBook", targets: ["ReadBook"]),
    ],
    targets: [
        .target(name: "ReadBookCore"),
        .executableTarget(name: "ReadBook", dependencies: ["ReadBookCore"]),
        .testTarget(name: "ReadBookCoreTests", dependencies: ["ReadBookCore"]),
    ]
)
```

Create `Tests/ReadBookCoreTests/ModelsTests.swift`:

```swift
import XCTest
@testable import ReadBookCore

final class ModelsTests: XCTestCase {
    func testBookPositionClampsIntoUTF16Bounds() {
        XCTAssertEqual(BookPosition(utf16Offset: -4).clamped(to: 10).utf16Offset, 0)
        XCTAssertEqual(BookPosition(utf16Offset: 7).clamped(to: 10).utf16Offset, 7)
        XCTAssertEqual(BookPosition(utf16Offset: 99).clamped(to: 10).utf16Offset, 10)
    }

    func testLibraryIndexRoundTripsThroughJSON() throws {
        let id = UUID()
        let value = LibraryIndex(schemaVersion: 1, bookIDs: [id], lastOpenedBookID: id)
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(LibraryIndex.self, from: data), value)
    }

    func testDefaultPreferencesMatchProductDefaults() {
        let p = ReaderPreferences.defaults
        XCTAssertEqual(p.readingMode, .paginated)
        XCTAssertEqual(p.fontFamily, "PingFang SC")
        XCTAssertEqual(p.fontSize, 17)
        XCTAssertEqual(p.lineSpacing, 8)
        XCTAssertEqual(p.paragraphSpacing, 9)
        XCTAssertEqual(p.theme, .soft)
        XCTAssertEqual(p.appPresenceMode, .widgetStyle)
    }
}
```

- [ ] **Step 2: Run tests and verify they fail because the core model types do not exist**

Run:

```bash
swift test --filter ModelsTests
```

Expected: compilation failure naming `BookPosition`, `LibraryIndex`, or `ReaderPreferences` as missing.

- [ ] **Step 3: Implement the core models**

Create `Sources/ReadBookCore/Models/BookPosition.swift`:

```swift
import Foundation

public struct BookPosition: Codable, Equatable, Sendable {
    public var utf16Offset: Int

    public init(utf16Offset: Int) {
        self.utf16Offset = utf16Offset
    }

    public static let zero = BookPosition(utf16Offset: 0)

    public func clamped(to utf16Length: Int) -> BookPosition {
        BookPosition(utf16Offset: min(max(utf16Offset, 0), max(utf16Length, 0)))
    }
}
```

Create `Sources/ReadBookCore/Models/Chapter.swift`:

```swift
import Foundation

public struct Chapter: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var utf16Offset: Int

    public init(id: UUID = UUID(), title: String, utf16Offset: Int) {
        self.id = id
        self.title = title
        self.utf16Offset = utf16Offset
    }
}
```

Create `Sources/ReadBookCore/Models/ReaderPreferences.swift`:

```swift
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
```

Create `Sources/ReadBookCore/Models/BookMetadata.swift`:

```swift
import Foundation

public enum ImportedTextEncoding: String, Codable, CaseIterable, Sendable {
    case utf8, utf16LittleEndian, utf16BigEndian, gb18030, big5
}

public struct BookMetadata: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public let importedAt: Date
    public var lastReadAt: Date
    public var position: BookPosition
    public let totalUTF16Length: Int
    public let sourceEncoding: ImportedTextEncoding
    public var chapters: [Chapter]

    public init(
        id: UUID = UUID(),
        title: String,
        importedAt: Date = .now,
        lastReadAt: Date = .now,
        position: BookPosition = .zero,
        totalUTF16Length: Int,
        sourceEncoding: ImportedTextEncoding,
        chapters: [Chapter]
    ) {
        self.id = id
        self.title = title
        self.importedAt = importedAt
        self.lastReadAt = lastReadAt
        self.position = position
        self.totalUTF16Length = totalUTF16Length
        self.sourceEncoding = sourceEncoding
        self.chapters = chapters
    }
}

public struct LibraryIndex: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var bookIDs: [UUID]
    public var lastOpenedBookID: UUID?

    public init(schemaVersion: Int = 1, bookIDs: [UUID] = [], lastOpenedBookID: UUID? = nil) {
        self.schemaVersion = schemaVersion
        self.bookIDs = bookIDs
        self.lastOpenedBookID = lastOpenedBookID
    }
}
```

- [ ] **Step 4: Add the minimal executable and app packaging script**

Create `Sources/ReadBook/App/ReadBookApp.swift`:

```swift
import SwiftUI

@main
struct ReadBookApp: App {
    var body: some Scene {
        Window("ReadBook", id: "reader") {
            Text("ReadBook")
                .frame(minWidth: 280, minHeight: 180)
        }
        .defaultSize(width: 360, height: 260)
    }
}
```

Create executable `Scripts/build-app.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release

APP="$ROOT/dist/ReadBook.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/ReadBook" "$APP/Contents/MacOS/ReadBook"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>ReadBook</string>
  <key>CFBundleIdentifier</key><string>com.coderlife.readbook</string>
  <key>CFBundleName</key><string>ReadBook</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

printf 'Built %s\n' "$APP"
```

Run `chmod +x Scripts/build-app.sh`.

- [ ] **Step 5: Run tests, build the executable, and package the app**

Run:

```bash
swift test --filter ModelsTests
swift build
Scripts/build-app.sh
```

Expected: all model tests pass; `dist/ReadBook.app/Contents/MacOS/ReadBook` exists.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Scripts Tests
git commit -m "feat: bootstrap ReadBook macOS app"
```

---

### Task 2: Parse Chinese chapter headings with UTF-16 offsets

**Files:**
- Create: `Sources/ReadBookCore/Import/ChapterParser.swift`
- Create: `Tests/ReadBookCoreTests/ChapterParserTests.swift`
- Create: `Tests/ReadBookCoreTests/Fixtures/chapter-patterns.txt`

**Interfaces:**
- Consumes: `Chapter`.
- Produces: `ChapterParser.parse(_ text: String) throws -> [Chapter]`.

- [ ] **Step 1: Write chapter parser tests**

Create `Tests/ReadBookCoreTests/ChapterParserTests.swift`:

```swift
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
        XCTAssertEqual(chapters[2].utf16Offset, expected)
    }

    func testRejectsLongBodyLinesThatContainChapterWords() throws {
        let text = "这是正文里提到第一章但并不是标题，因为这一整行明显是正常正文句子并且长度足够长，不应该被目录识别。"
        XCTAssertTrue(try ChapterParser().parse(text).isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests and verify failure**

```bash
swift test --filter ChapterParserTests
```

Expected: compile failure because `ChapterParser` does not exist.

- [ ] **Step 3: Implement the parser using `NSRegularExpression` so ranges are UTF-16-native**

Create `Sources/ReadBookCore/Import/ChapterParser.swift`:

```swift
import Foundation

public struct ChapterParser: Sendable {
    private static let pattern = #"(?m)^[\t 　]*(?:(?:第[零〇一二三四五六七八九十百千万两0-9０-９ ]{1,12}[章回卷部篇节])|(?:卷[零〇一二三四五六七八九十百千万两0-9０-９]{1,8})|(?:序章|楔子|番外[零〇一二三四五六七八九十0-9０-９]*|后记))[^\n]{0,40}$"#

    public init() {}

    public func parse(_ text: String) throws -> [Chapter] {
        let regex = try NSRegularExpression(pattern: Self.pattern)
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        return regex.matches(in: text, range: full).compactMap { match in
            let raw = ns.substring(with: match.range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return nil }
            return Chapter(title: raw, utf16Offset: match.range.location)
        }
    }
}
```

- [ ] **Step 4: Run chapter tests**

```bash
swift test --filter ChapterParserTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReadBookCore/Import Tests/ReadBookCoreTests/ChapterParserTests.swift Tests/ReadBookCoreTests/Fixtures
git commit -m "feat: detect Chinese novel chapters"
```

---

### Task 3: Decode UTF-8, UTF-16, GB18030/GBK, and Big5 TXT input

**Files:**
- Create: `Sources/ReadBookCore/Import/TextDecoder.swift`
- Create: `Tests/ReadBookCoreTests/TextDecoderTests.swift`

**Interfaces:**
- Consumes: `ImportedTextEncoding`.
- Produces: `DecodedText` and `TextDecoder.decode(_:override:) throws -> DecodedText`.

- [ ] **Step 1: Write decoding and normalization tests**

Create `Tests/ReadBookCoreTests/TextDecoderTests.swift`:

```swift
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

    func testEmptyInputFailsExplicitly() {
        XCTAssertThrowsError(try TextDecoder().decode(Data())) { error in
            XCTAssertEqual(error as? TextDecoderError, .emptyInput)
        }
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

```bash
swift test --filter TextDecoderTests
```

Expected: compile failure because `TextDecoder` and `TextDecoderError` do not exist.

- [ ] **Step 3: Implement decoding with BOM checks, UTF-8 preference, then Chinese legacy encodings**

Create `Sources/ReadBookCore/Import/TextDecoder.swift`:

```swift
import CoreFoundation
import Foundation

public struct DecodedText: Equatable, Sendable {
    public let text: String
    public let encoding: ImportedTextEncoding
}

public enum TextDecoderError: Error, Equatable {
    case emptyInput
    case undecodable
}

public struct TextDecoder: Sendable {
    public init() {}

    public func decode(_ data: Data, override: ImportedTextEncoding? = nil) throws -> DecodedText {
        guard !data.isEmpty else { throw TextDecoderError.emptyInput }

        if let override {
            guard let text = String(data: data, encoding: stringEncoding(for: override)) else {
                throw TextDecoderError.undecodable
            }
            return DecodedText(text: normalize(text), encoding: override)
        }

        if data.starts(with: [0xEF, 0xBB, 0xBF]),
           let text = String(data: data.dropFirst(3), encoding: .utf8) {
            return DecodedText(text: normalize(text), encoding: .utf8)
        }
        if data.starts(with: [0xFF, 0xFE]),
           let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) {
            return DecodedText(text: normalize(text), encoding: .utf16LittleEndian)
        }
        if data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) {
            return DecodedText(text: normalize(text), encoding: .utf16BigEndian)
        }
        if let text = String(data: data, encoding: .utf8) {
            return DecodedText(text: normalize(text), encoding: .utf8)
        }

        for candidate in [ImportedTextEncoding.gb18030, .big5, .utf16LittleEndian, .utf16BigEndian] {
            if let text = String(data: data, encoding: stringEncoding(for: candidate)), plausible(text) {
                return DecodedText(text: normalize(text), encoding: candidate)
            }
        }

        throw TextDecoderError.undecodable
    }

    private func stringEncoding(for encoding: ImportedTextEncoding) -> String.Encoding {
        switch encoding {
        case .utf8: return .utf8
        case .utf16LittleEndian: return .utf16LittleEndian
        case .utf16BigEndian: return .utf16BigEndian
        case .gb18030:
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            ))
        case .big5:
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.big5.rawValue)
            ))
        }
    }

    private func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{0000}", with: "")
    }

    private func plausible(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let controls = text.unicodeScalars.filter { scalar in
            scalar.value < 0x20 && scalar != "\n" && scalar != "\t"
        }.count
        return controls * 100 < max(text.unicodeScalars.count, 1)
    }
}
```

- [ ] **Step 4: Run decoding tests**

```bash
swift test --filter TextDecoderTests
```

Expected: PASS on macOS with CoreFoundation legacy encodings available.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReadBookCore/Import/TextDecoder.swift Tests/ReadBookCoreTests/TextDecoderTests.swift
git commit -m "feat: decode common Chinese TXT encodings"
```

---

### Task 4: Implement local library storage, import, rename, removal, and recovery

**Files:**
- Create: `Sources/ReadBookCore/Storage/AppPaths.swift`
- Create: `Sources/ReadBookCore/Storage/JSONFileStore.swift`
- Create: `Sources/ReadBookCore/Storage/LibraryRepository.swift`
- Create: `Tests/ReadBookCoreTests/LibraryRepositoryTests.swift`

**Interfaces:**
- Consumes: `BookMetadata`, `LibraryIndex`, `TextDecoder`, `ChapterParser`.
- Produces: `LibraryRepository.loadLibrary()`, `importBook(from:encodingOverride:)`, `loadText(bookID:)`, `savePosition(bookID:position:)`, `rename(bookID:title:)`, `remove(bookID:)`, `setLastOpenedBook(_:)`.
- Data ownership: `library.json` owns only schema version, ordered book IDs, and last-opened book ID. Each `Books/<id>/metadata.json` is authoritative for title, timestamps, position, total length, encoding, and chapter index. `content.txt` is authoritative normalized novel text.

- [ ] **Step 1: Write repository tests in a temporary application-support root**

Create `Tests/ReadBookCoreTests/LibraryRepositoryTests.swift`:

```swift
import Foundation
import XCTest
@testable import ReadBookCore

final class LibraryRepositoryTests: XCTestCase {
    func testImportCopiesNormalizedContentAndPersistsChapterMetadata() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("第一章\r\n正文\r\n第二章\r\n继续".utf8).write(to: source)

        let repo = LibraryRepository(paths: AppPaths(root: root.appendingPathComponent("Library")))
        let book = try await repo.importBook(from: source)
        let text = try await repo.loadText(bookID: book.id)
        let library = try await repo.loadLibrary()

        XCTAssertEqual(text, "第一章\n正文\n第二章\n继续")
        XCTAssertEqual(book.chapters.map(\.title), ["第一章", "第二章"])
        XCTAssertEqual(library.map(\.id), [book.id])
    }

    func testIndependentPositionsSurviveReload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("book.txt")
        try Data("第一章\nabcdefg".utf8).write(to: source)

        let paths = AppPaths(root: root.appendingPathComponent("Library"))
        let repo = LibraryRepository(paths: paths)
        let book = try await repo.importBook(from: source)
        try await repo.savePosition(bookID: book.id, position: BookPosition(utf16Offset: 5))

        let reopened = LibraryRepository(paths: paths)
        XCTAssertEqual(try await reopened.loadLibrary().first?.position.utf16Offset, 5)
    }
}
```

- [ ] **Step 2: Run repository tests and verify failure**

```bash
swift test --filter LibraryRepositoryTests
```

Expected: compilation failure for missing storage types.

- [ ] **Step 3: Implement path and atomic JSON helpers**

Create `Sources/ReadBookCore/Storage/AppPaths.swift`:

```swift
import Foundation

public struct AppPaths: Sendable {
    public let root: URL
    public var booksRoot: URL { root.appendingPathComponent("Books", isDirectory: true) }
    public var cacheRoot: URL { root.appendingPathComponent("Cache", isDirectory: true) }
    public var libraryIndexURL: URL { root.appendingPathComponent("library.json") }

    public init(root: URL? = nil) {
        if let root { self.root = root }
        else {
            self.root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ReadBook", isDirectory: true)
        }
    }

    public func bookDirectory(_ id: UUID) -> URL { booksRoot.appendingPathComponent(id.uuidString, isDirectory: true) }
    public func contentURL(_ id: UUID) -> URL { bookDirectory(id).appendingPathComponent("content.txt") }
    public func metadataURL(_ id: UUID) -> URL { bookDirectory(id).appendingPathComponent("metadata.json") }
}
```

Create `Sources/ReadBookCore/Storage/JSONFileStore.swift`:

```swift
import Foundation

struct JSONFileStore: Sendable {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try decoder.decode(type, from: Data(contentsOf: url))
    }
}
```

- [ ] **Step 4: Implement the repository actor**

Create `Sources/ReadBookCore/Storage/LibraryRepository.swift` with these exact public signatures and behavior:

```swift
import Foundation

public actor LibraryRepository {
    private let paths: AppPaths
    private let json = JSONFileStore()
    private let decoder = TextDecoder()
    private let chapterParser = ChapterParser()

    public init(paths: AppPaths = AppPaths()) {
        self.paths = paths
    }

    public func loadLibrary() throws -> [BookMetadata] {
        try ensureDirectories()
        let index = try loadIndex()
        return index.bookIDs.compactMap { id in
            try? json.read(BookMetadata.self, from: paths.metadataURL(id))
        }
    }

    public func importBook(from sourceURL: URL, encodingOverride: ImportedTextEncoding? = nil) throws -> BookMetadata {
        try ensureDirectories()
        guard sourceURL.pathExtension.lowercased() == "txt" else { throw LibraryError.unsupportedFileType }
        let decoded = try decoder.decode(Data(contentsOf: sourceURL), override: encodingOverride)
        guard !decoded.text.isEmpty else { throw LibraryError.emptyBook }

        let id = UUID()
        let dir = paths.bookDirectory(id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            try Data(decoded.text.utf8).write(to: paths.contentURL(id), options: .atomic)
            let chapters = try chapterParser.parse(decoded.text)
            let now = Date()
            let metadata = BookMetadata(
                id: id,
                title: sourceURL.deletingPathExtension().lastPathComponent,
                importedAt: now,
                lastReadAt: now,
                totalUTF16Length: (decoded.text as NSString).length,
                sourceEncoding: decoded.encoding,
                chapters: chapters
            )
            try json.write(metadata, to: paths.metadataURL(id))
            var index = try loadIndex()
            index.bookIDs.removeAll { $0 == id }
            index.bookIDs.insert(id, at: 0)
            index.lastOpenedBookID = id
            try json.write(index, to: paths.libraryIndexURL)
            return metadata
        } catch {
            try? FileManager.default.removeItem(at: dir)
            throw error
        }
    }

    public func loadText(bookID: UUID) throws -> String {
        guard let text = try? String(contentsOf: paths.contentURL(bookID), encoding: .utf8) else {
            throw LibraryError.missingContent
        }
        return text
    }

    public func savePosition(bookID: UUID, position: BookPosition, lastReadAt: Date = .now) throws {
        var metadata = try metadata(bookID)
        metadata.position = position.clamped(to: metadata.totalUTF16Length)
        metadata.lastReadAt = lastReadAt
        try json.write(metadata, to: paths.metadataURL(bookID))
    }

    public func rename(bookID: UUID, title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LibraryError.invalidTitle }
        var metadata = try metadata(bookID)
        metadata.title = trimmed
        try json.write(metadata, to: paths.metadataURL(bookID))
    }

    public func remove(bookID: UUID) throws {
        try? FileManager.default.removeItem(at: paths.bookDirectory(bookID))
        var index = try loadIndex()
        index.bookIDs.removeAll { $0 == bookID }
        if index.lastOpenedBookID == bookID { index.lastOpenedBookID = index.bookIDs.first }
        try json.write(index, to: paths.libraryIndexURL)
    }

    public func setLastOpenedBook(_ id: UUID?) throws {
        var index = try loadIndex()
        index.lastOpenedBookID = id
        try json.write(index, to: paths.libraryIndexURL)
    }

    public func lastOpenedBookID() throws -> UUID? { try loadIndex().lastOpenedBookID }

    private func metadata(_ id: UUID) throws -> BookMetadata {
        guard let value = try? json.read(BookMetadata.self, from: paths.metadataURL(id)) else {
            throw LibraryError.missingMetadata
        }
        return value
    }

    private func loadIndex() throws -> LibraryIndex {
        if !FileManager.default.fileExists(atPath: paths.libraryIndexURL.path) { return LibraryIndex() }
        return (try? json.read(LibraryIndex.self, from: paths.libraryIndexURL)) ?? recoverIndex()
    }

    private func recoverIndex() -> LibraryIndex {
        let ids = ((try? FileManager.default.contentsOfDirectory(at: paths.booksRoot, includingPropertiesForKeys: nil)) ?? [])
            .compactMap { UUID(uuidString: $0.lastPathComponent) }
            .filter { FileManager.default.fileExists(atPath: paths.metadataURL($0).path) }
        return LibraryIndex(bookIDs: ids, lastOpenedBookID: ids.first)
    }

    private func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: paths.booksRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.cacheRoot, withIntermediateDirectories: true)
    }
}

public enum LibraryError: Error, Equatable {
    case unsupportedFileType
    case emptyBook
    case missingContent
    case missingMetadata
    case invalidTitle
}
```

- [ ] **Step 5: Run repository and earlier import tests**

```bash
swift test --filter LibraryRepositoryTests
swift test --filter ChapterParserTests
swift test --filter TextDecoderTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/ReadBookCore/Storage Tests/ReadBookCoreTests/LibraryRepositoryTests.swift
git commit -m "feat: add local ReadBook library"
```

---

### Task 5: Persist reader preferences and implement layout-signature identity

**Files:**
- Create: `Sources/ReadBookCore/Settings/PreferencesStore.swift`
- Create: `Sources/ReadBookCore/Reader/ReaderTextStyle.swift`
- Create: `Tests/ReadBookCoreTests/PreferencesStoreTests.swift`

**Interfaces:**
- Consumes: `ReaderPreferences`.
- Produces: `PreferencesStore.load()`, `PreferencesStore.save(_:)`, `ReaderTextStyle`, `LayoutSignature`.

- [ ] **Step 1: Write preference and signature tests**

Create `Tests/ReadBookCoreTests/PreferencesStoreTests.swift`:

```swift
import XCTest
@testable import ReadBookCore

final class PreferencesStoreTests: XCTestCase {
    func testPreferencesRoundTrip() throws {
        let suite = "ReadBookTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PreferencesStore(defaults: defaults)
        var value = ReaderPreferences.defaults
        value.theme = .dark
        value.alwaysOnTop = true
        try store.save(value)
        XCTAssertEqual(try store.load(), value)
    }

    func testLayoutSignatureChangesForPaginationAffectingSettingsOnly() {
        let a = LayoutSignature(width: 316, height: 220, style: .default)
        var changed = ReaderTextStyle.default
        changed.fontSize = 21
        let b = LayoutSignature(width: 316, height: 220, style: changed)
        XCTAssertNotEqual(a, b)
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

```bash
swift test --filter PreferencesStoreTests
```

Expected: compile failure for missing store/style types.

- [ ] **Step 3: Implement JSON-backed UserDefaults preferences and quantized layout signature**

Create `Sources/ReadBookCore/Settings/PreferencesStore.swift`:

```swift
import Foundation

public struct PreferencesStore: Sendable {
    private let defaults: UserDefaults
    private let key = "readerPreferences.v1"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() throws -> ReaderPreferences {
        guard let data = defaults.data(forKey: key) else { return .defaults }
        return try JSONDecoder().decode(ReaderPreferences.self, from: data)
    }

    public func save(_ value: ReaderPreferences) throws {
        defaults.set(try JSONEncoder().encode(value), forKey: key)
    }
}
```

Create `Sources/ReadBookCore/Reader/ReaderTextStyle.swift`:

```swift
import Foundation

public struct ReaderTextStyle: Equatable, Sendable {
    public var fontFamily: String
    public var fontSize: Double
    public var lineSpacing: Double
    public var paragraphSpacing: Double
    public var horizontalPadding: Double
    public var verticalPadding: Double

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
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter PreferencesStoreTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReadBookCore/Settings Sources/ReadBookCore/Reader/ReaderTextStyle.swift Tests/ReadBookCoreTests/PreferencesStoreTests.swift
git commit -m "feat: persist reader preferences"
```

---

### Task 6: Build TextKit pagination and page caching

**Files:**
- Create: `Sources/ReadBookCore/Reader/PaginationEngine.swift`
- Create: `Sources/ReadBookCore/Reader/PageCache.swift`
- Create: `Tests/ReadBookCoreTests/PaginationEngineTests.swift`

**Interfaces:**
- Consumes: normalized book `NSString`, `ReaderTextStyle`, `LayoutSignature`.
- Produces: `PageRange`, `PaginationEngine.pageForward(...)`, `pageBackward(...)`, `PageCache`.

- [ ] **Step 1: Write pagination tests for continuity, bounds, and emoji-safe UTF-16 behavior**

Create `Tests/ReadBookCoreTests/PaginationEngineTests.swift`:

```swift
import XCTest
@testable import ReadBookCore

final class PaginationEngineTests: XCTestCase {
    func testForwardPagesAreContinuousAndBounded() throws {
        let text = NSString(string: String(repeating: "第一段文字。第二段文字。\n", count: 500))
        let engine = PaginationEngine()
        let style = ReaderTextStyle.default
        let first = try XCTUnwrap(engine.pageForward(text: text, from: 0, width: 316, height: 220, style: style))
        let second = try XCTUnwrap(engine.pageForward(text: text, from: first.upperBound, width: 316, height: 220, style: style))
        XCTAssertGreaterThan(first.length, 0)
        XCTAssertEqual(second.location, first.upperBound)
        XCTAssertLessThanOrEqual(second.upperBound, text.length)
    }

    func testBackwardPageEndsAtRequestedOffset() throws {
        let text = NSString(string: String(repeating: "正文🙂继续阅读。\n", count: 500))
        let engine = PaginationEngine()
        let forward = try XCTUnwrap(engine.pageForward(text: text, from: 0, width: 316, height: 220, style: .default))
        let previous = try XCTUnwrap(engine.pageBackward(text: text, endingAt: forward.upperBound, width: 316, height: 220, style: .default))
        XCTAssertEqual(previous.upperBound, forward.upperBound)
        XCTAssertGreaterThan(previous.length, 0)
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

```bash
swift test --filter PaginationEngineTests
```

Expected: compile failure because pagination types do not exist.

- [ ] **Step 3: Implement TextKit measurement over bounded UTF-16 windows**

Create `Sources/ReadBookCore/Reader/PaginationEngine.swift`:

```swift
import AppKit
import Foundation

public struct PageRange: Equatable, Hashable, Sendable {
    public let location: Int
    public let length: Int
    public var upperBound: Int { location + length }
}

public struct PaginationEngine: Sendable {
    private let probeLimit = 65_536

    public init() {}

    public func pageForward(text: NSString, from rawOffset: Int, width: Double, height: Double, style: ReaderTextStyle) -> PageRange? {
        let offset = min(max(rawOffset, 0), text.length)
        guard offset < text.length else { return nil }
        let available = min(probeLimit, text.length - offset)
        let fragment = text.substring(with: NSRange(location: offset, length: available))
        let fitting = fittingUTF16Length(fragment, width: width, height: height, style: style)
        guard fitting > 0 else { return nil }
        return PageRange(location: offset, length: fitting)
    }

    public func pageBackward(text: NSString, endingAt rawOffset: Int, width: Double, height: Double, style: ReaderTextStyle) -> PageRange? {
        let end = min(max(rawOffset, 0), text.length)
        guard end > 0 else { return nil }
        let lowerBound = max(0, end - probeLimit)
        var low = lowerBound
        var high = end - 1
        var bestStart = high

        while low <= high {
            let mid = (low + high) / 2
            let safeStart = composedBoundary(in: text, at: mid)
            let length = end - safeStart
            let fragment = text.substring(with: NSRange(location: safeStart, length: length))
            let fitting = fittingUTF16Length(fragment, width: width, height: height, style: style)
            if fitting >= length {
                bestStart = safeStart
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
        return PageRange(location: bestStart, length: end - bestStart)
    }

    private func fittingUTF16Length(_ fragment: String, width: Double, height: Double, style: ReaderTextStyle) -> Int {
        let attributed = attributedString(fragment, style: style)
        let storage = NSTextStorage(attributedString: attributed)
        let layout = NSLayoutManager()
        layout.allowsNonContiguousLayout = true
        let container = NSTextContainer(size: NSSize(width: max(width, 1), height: max(height, 1)))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        let glyphs = layout.glyphRange(for: container)
        return layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil).length
    }

    public func attributedString(_ text: String, style: ReaderTextStyle) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = style.lineSpacing
        paragraph.paragraphSpacing = style.paragraphSpacing
        let font = NSFont(name: style.fontFamily, size: style.fontSize) ?? .systemFont(ofSize: style.fontSize)
        return NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: paragraph])
    }

    private func composedBoundary(in text: NSString, at index: Int) -> Int {
        guard text.length > 0, index < text.length else { return min(index, text.length) }
        return text.rangeOfComposedCharacterSequence(at: max(index, 0)).location
    }
}
```

- [ ] **Step 4: Add page cache keyed by book/layout/start offset**

Create `Sources/ReadBookCore/Reader/PageCache.swift`:

```swift
import Foundation

public struct PageCacheKey: Hashable, Sendable {
    public let bookID: UUID
    public let signature: LayoutSignature
    public let startOffset: Int
}

public final class PageCache: @unchecked Sendable {
    private var pages: [PageCacheKey: PageRange] = [:]
    private let lock = NSLock()

    public init() {}

    public func value(for key: PageCacheKey) -> PageRange? {
        lock.lock(); defer { lock.unlock() }
        return pages[key]
    }

    public func insert(_ range: PageRange, for key: PageCacheKey) {
        lock.lock(); defer { lock.unlock() }
        pages[key] = range
    }

    public func invalidate(bookID: UUID? = nil) {
        lock.lock(); defer { lock.unlock() }
        if let bookID { pages = pages.filter { $0.key.bookID != bookID } }
        else { pages.removeAll(keepingCapacity: true) }
    }
}
```

- [ ] **Step 5: Run pagination tests and full core test suite**

```bash
swift test --filter PaginationEngineTests
swift test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/ReadBookCore/Reader Tests/ReadBookCoreTests/PaginationEngineTests.swift
git commit -m "feat: add TextKit pagination engine"
```

---

### Task 7: Implement reader session, per-book restoration, and debounced position persistence

**Files:**
- Create: `Sources/ReadBookCore/Reader/ReaderSession.swift`
- Create: `Tests/ReadBookCoreTests/ReaderSessionTests.swift`

**Interfaces:**
- Consumes: `LibraryRepository`, `PreferencesStore`, `BookPosition`, `ReadingMode`.
- Produces: `ReaderSession.open(bookID:)`, `updatePosition(_:)`, `jump(to:)`, `setReadingMode(_:)`, `flush()` and observable state.

- [ ] **Step 1: Write reader-session restoration and debounce tests**

Create `Tests/ReadBookCoreTests/ReaderSessionTests.swift`:

```swift
import Foundation
import XCTest
@testable import ReadBookCore

@MainActor
final class ReaderSessionTests: XCTestCase {
    func testOpenRestoresBookTextAndPosition() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("book.txt")
        try Data("第一章\n1234567890".utf8).write(to: source)
        let repo = LibraryRepository(paths: AppPaths(root: root.appendingPathComponent("Library")))
        let book = try await repo.importBook(from: source)
        try await repo.savePosition(bookID: book.id, position: BookPosition(utf16Offset: 4))

        let session = ReaderSession(repository: repo, saveDelayNanoseconds: 20_000_000)
        try await session.open(bookID: book.id)
        XCTAssertEqual(session.position.utf16Offset, 4)
        XCTAssertTrue(session.text.contains("1234567890"))
    }

    func testFlushPersistsLatestPosition() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("book.txt")
        try Data("第一章\n1234567890".utf8).write(to: source)
        let repo = LibraryRepository(paths: AppPaths(root: root.appendingPathComponent("Library")))
        let book = try await repo.importBook(from: source)
        let session = ReaderSession(repository: repo, saveDelayNanoseconds: 20_000_000)
        try await session.open(bookID: book.id)
        session.updatePosition(BookPosition(utf16Offset: 8))
        await session.flush()
        XCTAssertEqual(try await repo.loadLibrary().first?.position.utf16Offset, 8)
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

```bash
swift test --filter ReaderSessionTests
```

Expected: compile failure because `ReaderSession` does not exist.

- [ ] **Step 3: Implement the main-actor session with cancellable debounce**

Create `Sources/ReadBookCore/Reader/ReaderSession.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
public final class ReaderSession {
    public private(set) var currentBook: BookMetadata?
    public private(set) var text = ""
    public private(set) var position: BookPosition = .zero
    public private(set) var currentChapter: Chapter?
    public private(set) var readingMode: ReadingMode = .paginated

    private let repository: LibraryRepository
    private let saveDelayNanoseconds: UInt64
    private var saveTask: Task<Void, Never>?

    public init(repository: LibraryRepository, saveDelayNanoseconds: UInt64 = 700_000_000) {
        self.repository = repository
        self.saveDelayNanoseconds = saveDelayNanoseconds
    }

    public func open(bookID: UUID) async throws {
        await flush()
        let library = try await repository.loadLibrary()
        guard let metadata = library.first(where: { $0.id == bookID }) else { throw ReaderSessionError.bookNotFound }
        let loadedText = try await repository.loadText(bookID: bookID)
        currentBook = metadata
        text = loadedText
        position = metadata.position.clamped(to: metadata.totalUTF16Length)
        currentChapter = chapter(at: position.utf16Offset, in: metadata.chapters)
        try await repository.setLastOpenedBook(bookID)
    }

    public func updatePosition(_ newPosition: BookPosition) {
        guard let book = currentBook else { return }
        position = newPosition.clamped(to: book.totalUTF16Length)
        currentChapter = chapter(at: position.utf16Offset, in: book.chapters)
        scheduleSave()
    }

    public func jump(to chapter: Chapter) { updatePosition(BookPosition(utf16Offset: chapter.utf16Offset)) }
    public func setReadingMode(_ mode: ReadingMode) { readingMode = mode }

    public func flush() async {
        saveTask?.cancel()
        saveTask = nil
        guard let id = currentBook?.id else { return }
        try? await repository.savePosition(bookID: id, position: position)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        guard let id = currentBook?.id else { return }
        let value = position
        let repo = repository
        let delay = saveDelayNanoseconds
        saveTask = Task {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            try? await repo.savePosition(bookID: id, position: value)
        }
    }

    private func chapter(at offset: Int, in chapters: [Chapter]) -> Chapter? {
        chapters.last { $0.utf16Offset <= offset }
    }
}

public enum ReaderSessionError: Error { case bookNotFound }
```

- [ ] **Step 4: Run session tests and the full suite**

```bash
swift test --filter ReaderSessionTests
swift test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReadBookCore/Reader/ReaderSession.swift Tests/ReadBookCoreTests/ReaderSessionTests.swift
git commit -m "feat: persist reader session position"
```

---

### Task 8: Build paginated and continuous AppKit text surfaces with shared UTF-16 position

**Files:**
- Create: `Sources/ReadBook/Reader/PagedTextView.swift`
- Create: `Sources/ReadBook/Reader/PaginatedReaderView.swift`
- Create: `Sources/ReadBook/Reader/ContinuousTextView.swift`
- Create: `Sources/ReadBook/Reader/ContinuousReaderView.swift`
- Create: `Sources/ReadBook/Window/HorizontalScrollPager.swift`

**Interfaces:**
- Consumes: `ReaderSession`, `PaginationEngine`, `ReaderTextStyle`, `BookPosition`.
- Produces: two concrete reading surfaces that call `session.updatePosition` using UTF-16 offsets.

- [ ] **Step 1: Implement one-page TextKit rendering with zero internal inset**

Create `Sources/ReadBook/Reader/PagedTextView.swift`:

```swift
import AppKit
import ReadBookCore
import SwiftUI

struct PagedTextView: NSViewRepresentable {
    let text: String
    let style: ReaderTextStyle
    let textColor: NSColor

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView(frame: .zero)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        let engine = PaginationEngine()
        let attributed = NSMutableAttributedString(attributedString: engine.attributedString(text, style: style))
        attributed.addAttribute(.foregroundColor, value: textColor, range: NSRange(location: 0, length: attributed.length))
        view.textStorage?.setAttributedString(attributed)
    }
}
```

- [ ] **Step 2: Implement paginated view, click halves, keyboard arrows, and trackpad horizontal scroll threshold**

Create `Sources/ReadBook/Window/HorizontalScrollPager.swift` as an `NSViewRepresentable` wrapping an `NSView` subclass that accumulates precise `scrollWheel` `deltaX`; trigger previous/next only when `abs(accumulatedX) >= 60`, ignore when `abs(deltaY) > abs(deltaX)`, then reset accumulation for 250 ms after a page turn.

Create `Sources/ReadBook/Reader/PaginatedReaderView.swift` with this state contract:

```swift
struct PaginatedReaderView: View {
    @Bindable var session: ReaderSession
    let style: ReaderTextStyle
    let textColor: NSColor
    @State private var currentRange: PageRange?
    private let engine = PaginationEngine()

    var body: some View {
        GeometryReader { proxy in
            let innerWidth = max(proxy.size.width - style.horizontalPadding * 2, 1)
            let innerHeight = max(proxy.size.height - style.verticalPadding * 2, 1)
            ZStack {
                if let range = currentRange {
                    PagedTextView(
                        text: (session.text as NSString).substring(with: NSRange(location: range.location, length: range.length)),
                        style: style,
                        textColor: textColor
                    )
                    .padding(.horizontal, style.horizontalPadding)
                    .padding(.vertical, style.verticalPadding)
                }
                HStack(spacing: 0) {
                    Color.clear.contentShape(Rectangle()).onTapGesture { previous(width: innerWidth, height: innerHeight) }
                    Color.clear.contentShape(Rectangle()).onTapGesture { next(width: innerWidth, height: innerHeight) }
                }
                HorizontalScrollPager(
                    onPrevious: { previous(width: innerWidth, height: innerHeight) },
                    onNext: { next(width: innerWidth, height: innerHeight) }
                )
                .allowsHitTesting(false)
            }
            .focusable()
            .onKeyPress(.leftArrow) { previous(width: innerWidth, height: innerHeight); return .handled }
            .onKeyPress(.rightArrow) { next(width: innerWidth, height: innerHeight); return .handled }
            .onAppear { layout(width: innerWidth, height: innerHeight) }
            .onChange(of: session.position) { _, _ in layout(width: innerWidth, height: innerHeight) }
            .onChange(of: proxy.size) { _, _ in layout(width: innerWidth, height: innerHeight) }
        }
    }

    private func layout(width: Double, height: Double) {
        currentRange = engine.pageForward(text: session.text as NSString, from: session.position.utf16Offset, width: width, height: height, style: style)
    }

    private func next(width: Double, height: Double) {
        guard let range = currentRange,
              let next = engine.pageForward(text: session.text as NSString, from: range.upperBound, width: width, height: height, style: style) else { return }
        currentRange = next
        session.updatePosition(BookPosition(utf16Offset: next.location))
    }

    private func previous(width: Double, height: Double) {
        guard let range = currentRange,
              let previous = engine.pageBackward(text: session.text as NSString, endingAt: range.location, width: width, height: height, style: style) else { return }
        currentRange = previous
        session.updatePosition(BookPosition(utf16Offset: previous.location))
    }
}
```

During implementation, ensure the `HorizontalScrollPager` overlay receives wheel events without blocking click controls; if an overlay is required to receive events, place it behind the SwiftUI click halves in the ZStack rather than disabling hit testing.

- [ ] **Step 3: Implement continuous TextKit scrolling and top-visible UTF-16 reporting**

Create `Sources/ReadBook/Reader/ContinuousTextView.swift` as an `NSViewRepresentable` whose `makeNSView` returns `NSScrollView` containing a non-editable selectable `NSTextView`. Configure:

```swift
textView.isVerticallyResizable = true
textView.isHorizontallyResizable = false
textView.autoresizingMask = [.width]
textView.textContainer?.widthTracksTextView = true
textView.layoutManager?.allowsNonContiguousLayout = true
textView.textContainerInset = NSSize(width: style.horizontalPadding, height: style.verticalPadding)
textView.textContainer?.lineFragmentPadding = 0
scrollView.hasVerticalScroller = false
scrollView.drawsBackground = false
```

The coordinator must observe `NSView.boundsDidChangeNotification` on the clip view and report the top visible character index:

```swift
let point = NSPoint(
    x: scrollView.contentView.bounds.minX - textView.textContainerOrigin.x,
    y: scrollView.contentView.bounds.minY - textView.textContainerOrigin.y
)
let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
let character = layoutManager.characterIndexForGlyph(at: glyph)
onPositionChanged(BookPosition(utf16Offset: character))
```

When `anchor.utf16Offset` changes because the user switches mode or jumps chapters, use `glyphRange(forCharacterRange:)`, `boundingRect(forGlyphRange:in:)`, and `scrollView.contentView.scroll(to:)` to put that character near the top. Track `lastAppliedAnchor` in the coordinator so scroll callbacks do not continuously snap the view back.

- [ ] **Step 4: Wrap the continuous text view in SwiftUI**

Create `Sources/ReadBook/Reader/ContinuousReaderView.swift`:

```swift
import AppKit
import ReadBookCore
import SwiftUI

struct ContinuousReaderView: View {
    @Bindable var session: ReaderSession
    let style: ReaderTextStyle
    let textColor: NSColor

    var body: some View {
        ContinuousTextView(
            text: session.text,
            anchor: session.position,
            style: style,
            textColor: textColor,
            onPositionChanged: { session.updatePosition($0) }
        )
    }
}
```

- [ ] **Step 5: Build and manually verify both surfaces with a fixture**

Run:

```bash
swift test
swift build
swift run ReadBook
```

Temporarily wire one fixture string into the executable only for this local check, then remove that temporary fixture wiring before commit. Verify:

1. Right click-region and right arrow advance a page.
2. Left click-region and left arrow return toward the previous text.
3. Continuous mode can scroll a multi-thousand-line text smoothly.
4. The top-visible UTF-16 offset changes during scrolling.
5. An emoji-containing line does not crash page navigation.

- [ ] **Step 6: Commit**

```bash
git add Sources/ReadBook/Reader Sources/ReadBook/Window/HorizontalScrollPager.swift
git commit -m "feat: add paginated and continuous readers"
```

---

### Task 9: Build the app model, themes, library/TOC UI, import flow, and mode switching

**Files:**
- Create: `Sources/ReadBook/App/AppModel.swift`
- Create: `Sources/ReadBook/Settings/ThemePalette.swift`
- Create: `Sources/ReadBook/Reader/ReaderRootView.swift`
- Create: `Sources/ReadBook/Reader/ReaderToolbar.swift`
- Create: `Sources/ReadBook/Library/LibraryPopoverView.swift`
- Create: `Sources/ReadBook/Library/ChapterListView.swift`
- Create: `Sources/ReadBook/Library/ImportDropHandler.swift`
- Modify: `Sources/ReadBook/App/ReadBookApp.swift`

**Interfaces:**
- Consumes: repository/session/preferences and both reading surfaces.
- Produces: complete local reading flow: import -> open -> read -> switch mode -> chapter jump -> recent book switch.

- [ ] **Step 1: Implement `AppModel` as the app-target composition root**

Create `Sources/ReadBook/App/AppModel.swift`:

```swift
import Observation
import ReadBookCore

@MainActor
@Observable
final class AppModel {
    let repository: LibraryRepository
    let session: ReaderSession
    private let preferencesStore: PreferencesStore

    var books: [BookMetadata] = []
    var preferences: ReaderPreferences
    var lastErrorMessage: String?

    init(
        repository: LibraryRepository = LibraryRepository(),
        preferencesStore: PreferencesStore = PreferencesStore()
    ) {
        self.repository = repository
        self.preferencesStore = preferencesStore
        self.preferences = (try? preferencesStore.load()) ?? .defaults
        self.session = ReaderSession(repository: repository)
        self.session.setReadingMode(self.preferences.readingMode)
    }

    func start() async {
        await reloadLibrary()
        if let id = try? await repository.lastOpenedBookID() { try? await open(id) }
    }

    func reloadLibrary() async {
        books = ((try? await repository.loadLibrary()) ?? []).sorted { $0.lastReadAt > $1.lastReadAt }
    }

    func open(_ id: UUID) async throws {
        try await session.open(bookID: id)
        await reloadLibrary()
    }

    func importBook(_ url: URL, override: ImportedTextEncoding? = nil) async {
        do {
            let book = try await repository.importBook(from: url, encodingOverride: override)
            await reloadLibrary()
            try await open(book.id)
        } catch {
            lastErrorMessage = String(describing: error)
        }
    }

    func setMode(_ mode: ReadingMode) {
        preferences.readingMode = mode
        session.setReadingMode(mode)
        persistPreferences()
    }

    func persistPreferences() { try? preferencesStore.save(preferences) }
}
```

- [ ] **Step 2: Implement the three theme palettes**

Create `Sources/ReadBook/Settings/ThemePalette.swift`:

```swift
import AppKit
import ReadBookCore

struct ThemePalette {
    let background: NSColor
    let text: NSColor
    let secondaryText: NSColor

    static func resolve(_ theme: ReaderTheme) -> ThemePalette {
        switch theme {
        case .soft:
            ThemePalette(background: NSColor(calibratedWhite: 0.96, alpha: 1), text: NSColor(calibratedWhite: 0.16, alpha: 1), secondaryText: .secondaryLabelColor)
        case .light:
            ThemePalette(background: NSColor(calibratedWhite: 0.99, alpha: 1), text: NSColor(calibratedWhite: 0.10, alpha: 1), secondaryText: .secondaryLabelColor)
        case .dark:
            ThemePalette(background: NSColor(calibratedWhite: 0.12, alpha: 1), text: NSColor(calibratedWhite: 0.88, alpha: 1), secondaryText: NSColor(calibratedWhite: 0.65, alpha: 1))
        }
    }
}
```

- [ ] **Step 3: Implement chapter list with title search and recent-book popover**

`ChapterListView` must use a local `@State private var query = ""` and compute:

```swift
var filtered: [Chapter] {
    query.isEmpty ? chapters : chapters.filter { $0.title.localizedCaseInsensitiveContains(query) }
}
```

Each chapter row calls `session.jump(to: chapter)`.

`LibraryPopoverView` must show two tabs using a `Picker` with `.segmented` style: `目录` and `最近阅读`. Recent books show title plus integer progress computed as:

```swift
Int((Double(book.position.utf16Offset) / Double(max(book.totalUTF16Length, 1))) * 100)
```

Provide `+ 导入 TXT` at the bottom. Rename uses an inline `TextField`; removal calls `repository.remove(bookID:)`, reloads library, and if the removed book is current, opens the next available book or leaves the reader empty.

- [ ] **Step 4: Implement toolbar and root reader composition**

`ReaderToolbar` must expose controls for library/TOC, mode switch, pin, and settings. Keep it overlayed rather than reserving a permanent toolbar height.

`ReaderRootView` must:

1. Compute `ReaderTextStyle` from `model.preferences`.
2. Resolve the selected `ThemePalette`.
3. Show an import-empty-state when no book is open.
4. Show `PaginatedReaderView` when `.paginated` and `ContinuousReaderView` when `.continuous`.
5. Preserve the same `session.position` when switching modes.
6. Fade toolbar/progress chrome based on `.onHover`.
7. Show current chapter at bottom-left and percentage at bottom-right while hovered.
8. Use a rounded rectangle background with approximately 26 pt corner radius.

The content switch should be structurally equivalent to:

```swift
Group {
    switch model.session.readingMode {
    case .paginated:
        PaginatedReaderView(session: model.session, style: style, textColor: palette.text)
    case .continuous:
        ContinuousReaderView(session: model.session, style: style, textColor: palette.text)
    }
}
```

- [ ] **Step 5: Add file picker and drag/drop import**

Create `ImportDropHandler.swift` with a reusable function that accepts only file URLs whose path extension is `txt`.

In `ReaderRootView`, add `.fileImporter(isPresented:..., allowedContentTypes: [.plainText], allowsMultipleSelection: false)` and call `await model.importBook(url)`.

Add `.onDrop(of: [.fileURL], isTargeted: ...)` and load the URL using `NSItemProvider.loadItem`; reject non-`.txt` paths before import.

Add `Command + O` in the app command menu by toggling the same file-importer state through an app-model flag or notification owned by `AppModel`.

- [ ] **Step 6: Wire the real root view into the app**

Replace the placeholder `Text("ReadBook")` in `ReadBookApp.swift` with one shared `@State`/`@StateObject` equivalent model instance and `ReaderRootView(model: model)`. Start the model once using `.task { await model.start() }`.

- [ ] **Step 7: Build and manually verify the end-to-end local flow**

Run:

```bash
swift test
swift run ReadBook
```

Verify with at least two TXT books:

1. Import both.
2. Switch recent books and confirm independent positions.
3. Search for a chapter title and jump.
4. Switch paginated -> continuous -> paginated and remain at the same logical text neighborhood.
5. Quit/relaunch and restore the last book.

- [ ] **Step 8: Commit**

```bash
git add Sources/ReadBook/App Sources/ReadBook/Reader Sources/ReadBook/Library Sources/ReadBook/Settings
git commit -m "feat: add local reader workflow"
```

---

### Task 10: Implement widget-like NSWindow behavior, menu bar entry, Dock mode, and settings

**Files:**
- Create: `Sources/ReadBook/Window/WindowAccessor.swift`
- Create: `Sources/ReadBook/Window/WindowCoordinator.swift`
- Create: `Sources/ReadBook/Window/WindowRegistry.swift`
- Create: `Sources/ReadBook/Settings/SettingsView.swift`
- Modify: `Sources/ReadBook/App/ReadBookApp.swift`
- Modify: `Sources/ReadBook/Reader/ReaderToolbar.swift`

**Interfaces:**
- Consumes: `AppModel.preferences.alwaysOnTop`, `appPresenceMode`.
- Produces: draggable/resizable titleless reader window, persisted frame, floating mode, menu bar show/hide, Dock visibility switching, settings UI.

- [ ] **Step 1: Add a window registry and accessor**

`WindowRegistry` must be `@MainActor` and keep a weak reference to the reader `NSWindow`. Provide:

```swift
func register(_ window: NSWindow)
func showReader()
func hideReader()
func toggleReader()
func setAlwaysOnTop(_ enabled: Bool)
func setAppPresence(_ mode: AppPresenceMode)
```

`setAlwaysOnTop` sets `window.level = enabled ? .floating : .normal`.

`setAppPresence` calls:

```swift
NSApp.setActivationPolicy(mode == .widgetStyle ? .accessory : .regular)
if mode == .normal { NSApp.activate(ignoringOtherApps: true) }
```

Create `WindowAccessor` as an `NSViewRepresentable` whose `viewDidMoveToWindow`/async callback registers the containing window.

- [ ] **Step 2: Configure the widget-like window and persist its frame**

`WindowCoordinator.configure(_:)` must set:

```swift
window.minSize = NSSize(width: 280, height: 180)
window.titleVisibility = .hidden
window.titlebarAppearsTransparent = true
window.isMovableByWindowBackground = true
window.styleMask.insert([.titled, .resizable, .closable, .fullSizeContentView])
window.standardWindowButton(.closeButton)?.isHidden = true
window.standardWindowButton(.miniaturizeButton)?.isHidden = true
window.standardWindowButton(.zoomButton)?.isHidden = true
window.setFrameAutosaveName("ReadBook.ReaderWindow")
```

Set the coordinator as `NSWindowDelegate`. In `windowShouldClose`, call `window.orderOut(nil)` and return `false` so Cmd+W hides instead of destroying the only reader scene.

- [ ] **Step 3: Add the menu bar scene**

Add to `ReadBookApp.body`:

```swift
MenuBarExtra("ReadBook", systemImage: "book.closed") {
    Button("显示 / 隐藏阅读器") { windowRegistry.toggleReader() }
    Divider()
    ForEach(model.books.prefix(6)) { book in
        Button(book.title) { Task { try? await model.open(book.id); windowRegistry.showReader() } }
    }
    Divider()
    Button("导入 TXT…") { model.requestImport() }
    SettingsLink { Text("设置…") }
    Divider()
    Button("退出 ReadBook") {
        Task { await model.session.flush(); NSApp.terminate(nil) }
    }
}
```

Use one shared model and registry across `Window`, `MenuBarExtra`, and `Settings` scenes.

- [ ] **Step 4: Implement settings UI and immediate persistence**

`SettingsView` must contain:

- Font family Picker: `PingFang SC`, `Songti SC`, `STKaiti`, `System`.
- Font size Slider constrained to 12...30.
- Line spacing Slider constrained to 0...16.
- Theme Picker: soft/light/dark.
- App presence Picker: widget-style/normal.
- Toggle for always-on-top.

Each change updates `model.preferences`, calls `model.persistPreferences()`, and invokes registry methods when it affects window level or activation policy.

- [ ] **Step 5: Apply restored presence/window behavior on startup**

After `model.start()` and window registration:

```swift
windowRegistry.setAlwaysOnTop(model.preferences.alwaysOnTop)
windowRegistry.setAppPresence(model.preferences.appPresenceMode)
```

The frame is restored by `setFrameAutosaveName`.

- [ ] **Step 6: Run and manually verify macOS-specific behavior**

Run:

```bash
swift test
swift run ReadBook
```

Verify:

1. Default window is roughly 360 x 260 and cannot shrink below 280 x 180.
2. No visible traffic-light buttons or traditional title chrome.
3. Window drags from its background and resizes normally.
4. Pin toggles floating level.
5. Widget-style mode hides Dock icon but leaves menu bar entry.
6. Normal mode restores Dock icon.
7. Menu bar can hide/show the reader.
8. Window size/position survive relaunch.

- [ ] **Step 7: Commit**

```bash
git add Sources/ReadBook/Window Sources/ReadBook/Settings Sources/ReadBook/App Sources/ReadBook/Reader/ReaderToolbar.swift
git commit -m "feat: add widget-style macOS window behavior"
```

---

### Task 11: Harden errors, lifecycle saves, large-book performance, and release documentation

**Files:**
- Modify: `Sources/ReadBook/App/AppModel.swift`
- Modify: `Sources/ReadBook/Reader/ReaderRootView.swift`
- Modify: `Sources/ReadBookCore/Storage/LibraryRepository.swift`
- Modify: `Sources/ReadBookCore/Reader/PaginationEngine.swift`
- Create: `Tests/ReadBookCoreTests/Fixtures/large-novel-generator.swift`
- Create: `README.md`

**Interfaces:**
- Consumes all previous tasks.
- Produces V1 Definition-of-Done validation and local install/run instructions.

- [ ] **Step 1: Add explicit user-facing import/storage error mapping**

In `AppModel`, replace raw `String(describing:)` presentation with an error mapper that yields Chinese messages:

```swift
func message(for error: Error) -> String {
    switch error {
    case TextDecoderError.emptyInput, LibraryError.emptyBook:
        return "这个 TXT 文件没有可阅读的内容。"
    case TextDecoderError.undecodable:
        return "无法识别文本编码。请重新导入并手动选择编码。"
    case LibraryError.unsupportedFileType:
        return "目前只支持导入 .txt 小说。"
    case LibraryError.missingContent:
        return "本地小说文件缺失，无法继续阅读。"
    default:
        return "读取或保存失败，请稍后重试。"
    }
}
```

When decoding fails, show an alert/sheet with encoding picker values from `ImportedTextEncoding.allCases` and retry `model.importBook(url, override: selectedEncoding)`.

- [ ] **Step 2: Flush position on lifecycle transitions**

In the root app/view, observe `scenePhase`. On `.inactive` and `.background`, call:

```swift
Task { await model.session.flush() }
```

Before book switching, removal of current book, and app termination, call `await session.flush()`.

- [ ] **Step 3: Add large-book fixture generation and a measurable pagination guard**

Create `Tests/ReadBookCoreTests/Fixtures/large-novel-generator.swift`:

```swift
import Foundation

let chapter = "第一章 测试\n" + String(repeating: "这是一段用于性能验证的中文小说正文。\n", count: 200)
let text = String(repeating: chapter, count: 1200)
try Data(text.utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
```

Add one XCTest performance test to `PaginationEngineTests` that builds a multi-million-character `NSString`, then measures only first-page layout:

```swift
func testFirstPageLayoutDoesNotRequireWholeBookPagination() {
    let text = NSString(string: String(repeating: "长篇中文正文测试。\n", count: 300_000))
    measure {
        _ = PaginationEngine().pageForward(text: text, from: text.length / 2, width: 316, height: 220, style: .default)
    }
}
```

The test is a regression guard for local-page probing; it must not enumerate pages from offset zero.

- [ ] **Step 4: Verify metadata recovery behavior**

Extend `LibraryRepositoryTests` with two tests:

1. Delete/corrupt `library.json` while leaving valid book directories; `loadLibrary()` reconstructs an index from metadata files and preserves readable books.
2. Delete one book's `metadata.json`; `loadLibrary()` skips that broken entry without deleting `content.txt`.

Do not silently delete novel content during recovery.

- [ ] **Step 5: Write README with local build/install workflow**

Create `README.md` containing:

```markdown
# ReadBook

A small native macOS TXT novel reader designed to live on the desktop like a widget.

## Requirements

- macOS 26+
- Apple Silicon Mac recommended
- Xcode / Swift toolchain with Swift 6 support

## Run from source

```bash
swift test
swift run ReadBook
```

## Build a local app bundle

```bash
Scripts/build-app.sh
open dist/ReadBook.app
```

Imported books are stored under:

```text
~/Library/Application Support/ReadBook/
```

V1 is local-only and does not use a backend or network service.
```

Also document the V1 interactions: import TXT, click/arrow page navigation, manual paginated/continuous switch, chapter search, recent books, pin, theme/font settings, menu bar access, and Dock-mode switch.

- [ ] **Step 6: Run final automated verification**

Run:

```bash
swift test
swift build -c release
Scripts/build-app.sh
```

Expected: all tests pass, release build succeeds, and `dist/ReadBook.app` is produced.

- [ ] **Step 7: Run the V1 manual acceptance checklist**

Use at least one UTF-8 TXT and one GB18030/GBK TXT. Verify every item:

```text
[ ] File-picker TXT import
[ ] Drag/drop TXT import
[ ] UTF-8 Chinese text is correct
[ ] GB18030/GBK Chinese text is correct
[ ] Imported source survives deletion/move of original file
[ ] Multiple books appear in recent list
[ ] Independent per-book positions restore
[ ] Chapters auto-detect
[ ] Chapter title search works
[ ] Chapter jump works
[ ] Paginated reading works
[ ] Left/right click navigation works
[ ] Left/right arrow navigation works
[ ] Continuous vertical scrolling works
[ ] Manual reading-mode switch preserves logical position
[ ] Font size changes without losing logical position
[ ] Line spacing changes without losing logical position
[ ] Font family changes without losing logical position
[ ] Soft/light/dark themes work
[ ] Window position and size restore
[ ] Always-on-top works
[ ] Widget-style mode hides Dock icon
[ ] Normal mode shows Dock icon
[ ] Menu bar entry remains usable in widget-style mode
[ ] Relaunch restores last book and position
[ ] Rename works
[ ] Remove works
[ ] No-chapter TXT remains readable
[ ] Corrupt library index does not destroy imported content
```

- [ ] **Step 8: Commit**

```bash
git add Sources Tests README.md Scripts
git commit -m "chore: harden ReadBook V1 release"
```

---

## Implementation Order and Review Gates

Execute Tasks 1 through 11 in order. Each task is a reviewer gate and should end with its stated tests plus commit before starting the next task. Do not combine Tasks 6-10 into a single large UI commit: pagination, session position, reader surfaces, workflow UI, and window behavior are intentionally separate because each can regress independently.

## Final Spec Coverage Check

- Product shape / macOS 26 / SwiftUI + AppKit: Tasks 1, 10.
- Widget-like 360 x 260 window / 280 x 180 minimum / resize / drag / hidden chrome: Task 10.
- Desktop vs always-on-top: Task 10.
- Dock-hidden widget-style vs normal app mode: Task 10.
- Menu bar entry: Task 10.
- Paginated reader / click / arrows / horizontal trackpad scrolling: Tasks 6 and 8.
- Continuous reader / mouse and trackpad scrolling / keyboard native text scrolling: Task 8.
- Manual mode switch / shared UTF-16 position: Tasks 7-9.
- Multiple books / recent reading: Tasks 4 and 9.
- Copy-based local library / normalized UTF-8: Tasks 3-4.
- UTF-8 / UTF-16 / GB18030 / Big5 decoding and manual override: Tasks 3 and 11.
- Chapter recognition / persisted index / chapter search and jump: Tasks 2, 4, 9.
- Typography defaults / adjustable font and spacing: Tasks 5, 9, 10.
- Soft / light / dark themes: Tasks 9-10.
- Debounced reading-position persistence and lifecycle flush: Tasks 7 and 11.
- TextKit pagination / layout invalidation identity / local page probing: Tasks 5-6.
- Multi-million-character responsiveness guard: Tasks 6 and 11.
- Error handling / corrupt index recovery / no-chapter handling: Tasks 4 and 11.
- Rename / remove: Tasks 4 and 9.
- Local packaging and README: Tasks 1 and 11.
- Explicit V1 exclusions: enforced by Global Constraints; no task adds excluded functionality.
