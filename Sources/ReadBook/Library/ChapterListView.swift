import ReadBookCore
import SwiftUI

struct ChapterListView: View {
    let chapters: [Chapter]
    let currentChapterID: UUID?
    let onSelect: (Chapter) -> Void

    @State private var query = ""

    private var filtered: [Chapter] {
        query.isEmpty
            ? chapters
            : chapters.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 10) {
            TextField("搜索章节", text: $query)
                .textFieldStyle(.roundedBorder)

            if chapters.isEmpty {
                ContentUnavailableView("未识别到章节", systemImage: "text.page")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(filtered) { chapter in
                                Button {
                                    onSelect(chapter)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: chapter.id == currentChapterID ? "location.fill" : "circle")
                                            .font(.system(size: 8))
                                            .opacity(chapter.id == currentChapterID ? 1 : 0.25)
                                        Text(chapter.title)
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.vertical, 5)
                                }
                                .buttonStyle(.plain)
                                .id(chapter.id)
                            }
                        }
                    }
                    .onAppear {
                        scrollToCurrentChapter(using: proxy)
                    }
                    .onChange(of: currentChapterID) { _, _ in
                        guard query.isEmpty else { return }
                        scrollToCurrentChapter(using: proxy)
                    }
                }
            }
        }
        .padding(12)
    }

    static func initialScrollTarget(chapters: [Chapter], currentChapterID: UUID?) -> UUID? {
        guard let currentChapterID,
              chapters.contains(where: { $0.id == currentChapterID }) else {
            return nil
        }
        return currentChapterID
    }

    private func scrollToCurrentChapter(using proxy: ScrollViewProxy) {
        guard query.isEmpty,
              let target = Self.initialScrollTarget(
                chapters: chapters,
                currentChapterID: currentChapterID
              ) else { return }

        // Wait one run-loop turn so LazyVStack has registered its IDs before
        // asking ScrollViewReader to place the current chapter in the center.
        DispatchQueue.main.async {
            proxy.scrollTo(target, anchor: .center)
        }
    }
}
