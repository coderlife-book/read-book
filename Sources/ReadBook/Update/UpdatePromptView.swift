import ReadBookCore
import SwiftUI

struct UpdatePromptView: View {
    @Bindable var controller: UpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 26))
                Text("ReadBook 更新")
                    .font(.headline)
                Spacer()
            }

            content
        }
        .padding(22)
        .frame(width: 430)
    }

    @ViewBuilder
    private var content: some View {
        switch controller.state {
        case .idle, .checking:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("正在检查更新…")
            }

        case .upToDate(let version):
            Text("当前已经是最新版本 v\(version.description)。")
            actionRow(primary: "好", primaryAction: controller.dismiss)

        case .available(let release):
            if let version = release.latestVersion {
                Text("发现新版本 v\(version.description)")
                    .font(.system(size: 15, weight: .semibold))
            }
            if !release.releaseNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView {
                    Text(release.releaseNotes)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 190)
                .padding(10)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                Button("稍后") { controller.dismiss() }
                Spacer()
                Button("下载并安装") {
                    Task { await controller.downloadAndInstall() }
                }
                .keyboardShortcut(.defaultAction)
            }

        case .downloading(let release):
            HStack(spacing: 10) {
                ProgressView()
                Text("正在下载 v\(release.latestVersion?.description ?? "新版本")…")
            }
            Text("下载完成后会先校验文件，再询问系统替换当前 ReadBook。")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .validating:
            HStack(spacing: 10) {
                ProgressView()
                Text("正在校验更新包…")
            }
            Text("正在检查完整性、版本和签名，请稍候。")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .installing(let version):
            HStack(spacing: 10) {
                ProgressView()
                Text("正在安装 v\(version.description)，ReadBook 将自动重新打开…")
            }

        case .error(let message):
            Text(message)
                .foregroundStyle(.red)
            HStack {
                Button("关闭") { controller.dismiss() }
                Spacer()
                Button("重新检查") {
                    Task { await controller.check(manual: true) }
                }
            }
        }
    }

    private func actionRow(primary: String, primaryAction: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            Button(primary, action: primaryAction)
                .keyboardShortcut(.defaultAction)
        }
    }
}
