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
                        }
                    }
                }
            }
        }
        .padding(12)
    }
}
