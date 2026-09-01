import Observation
import ReadBookCore

@MainActor
@Observable
final class ReaderTitlebarState {
    var title = "ReadBook"
    var readingMode: ReadingMode = .paginated
    var alwaysOnTop = false
    var isVisible = false
    var isLibraryPresented = false

    @ObservationIgnored var onModeChange: ((ReadingMode) -> Void)?
    @ObservationIgnored var onPin: (() -> Void)?

    func toggleLibrary() {
        isLibraryPresented.toggle()
    }

    func toggleReadingMode() {
        onModeChange?(readingMode == .paginated ? .continuous : .paginated)
    }

    func togglePin() {
        onPin?()
    }
}
