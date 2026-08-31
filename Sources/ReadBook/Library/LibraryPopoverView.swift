import ReadBookCore
import SwiftUI

struct LibraryPopoverView: View {
    @Bindable var model: AppModel

    private enum Tab: String, CaseIterable, Identifiable {
        case chapters = "目录"
        case recent = "最近阅读"
        var id: Self { self }
    }

    @State private var tab: Tab = .chapters
    @State private var editingBookID: UUID?
    @State private var renameText = ""
    @State private var pendingDelete: BookMetadata?

    var body: some View {
        VStack(spacing: 8) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { tab in Text(tab.rawValue).tag(tab) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.top, .horizontal], 12)

            Group {
                switch tab {
                case .chapters:
                    ChapterListView(
                        chapters: model.currentBook?.chapters ?? [],
                        currentChapterID: model.currentChapter?.id,
                        onSelect: { model.jump(to: $0) }
                    )
                case .recent:
                    recentBooks
                }
            }
            .frame(width: 320, height: 330)

            Divider()
            Button {
                model.requestImport()
            } label: {
                Label("导入 TXT", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .confirmationDialog(
            "从书库删除这本小说？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let book = pendingDelete else { return }
                Task { await model.remove(bookID: book.id) }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        }
    }

    private var recentBooks: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(model.books) { book in
                    HStack(spacing: 8) {
                        if editingBookID == book.id {
                            TextField("书名", text: $renameText)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { commitRename(book) }
                            Button("完成") { commitRename(book) }
                                .buttonStyle(.borderless)
                        } else {
                            Button {
                                Task { try? await model.open(book.id) }
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(book.title).lineLimit(1)
                                        Spacer()
                                        Text("\(progress(book))%")
                                            .foregroundStyle(.secondary)
                                    }
                                    if model.currentBook?.id == book.id {
                                        Text("正在阅读")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 7)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("重命名") {
                                    editingBookID = book.id
                                    renameText = book.title
                                }
                                Button("从书库删除", role: .destructive) {
                                    pendingDelete = book
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func progress(_ book: BookMetadata) -> Int {
        guard book.totalUTF16Length > 0 else { return 0 }
        let offset = model.currentBook?.id == book.id ? model.position.utf16Offset : book.position.utf16Offset
        return min(max(Int((Double(offset) / Double(book.totalUTF16Length)) * 100), 0), 100)
    }

    private func commitRename(_ book: BookMetadata) {
        let title = renameText
        editingBookID = nil
        Task { await model.rename(bookID: book.id, title: title) }
    }
}
