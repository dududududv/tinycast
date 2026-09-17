import SwiftUI

struct OSSUploadView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let coordinator: OSSUploadCoordinator
    let entries: [OSSUploadHistoryEntry]
    let showUploadCard: Bool
    let uploadCardSelected: Bool
    let selectedID: OSSUploadHistoryEntry.ID?
    let scroll: ScrollIntent
    let isUploading: Bool
    let completedCount: Int
    let totalCount: Int
    let currentFileName: String?
    let onSelectUpload: () -> Void
    let onChooseFiles: () -> Void
    let onPasteFiles: () -> Void
    let onUploadActions: () -> Void
    let onSelectEntry: (OSSUploadHistoryEntry) -> Void
    let onActivateEntry: (OSSUploadHistoryEntry) -> Void
    let onEntryActions: (OSSUploadHistoryEntry) -> Void

    private var selectedRowID: String? {
        uploadCardSelected ? "oss-upload" : selectedID?.uuidString
    }

    private var firstRowSelected: Bool {
        showUploadCard ? uploadCardSelected : selectedID == entries.first?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    transferStatus
                        .animation(reduceMotion ? nil : Theme.Motion.feedback, value: coordinator.isUploading)
                    if showUploadCard {
                        SectionHeader(title: "Upload", isFirst: true)
                        OSSUploadCard(
                            selected: uploadCardSelected, isUploading: isUploading,
                            completedCount: completedCount, totalCount: totalCount,
                            currentFileName: currentFileName, onSelect: onSelectUpload,
                            onChooseFiles: onChooseFiles, onPasteFiles: onPasteFiles,
                            onActions: onUploadActions
                        )
                        .selectionFrame(uploadCardSelected)
                        .id("oss-upload")
                    }
                    if !entries.isEmpty {
                        SectionHeader(title: "History", isFirst: !showUploadCard)
                        ForEach(entries, id: \.scrollID) { entry in
                            OSSUploadHistoryRow(entry: entry, selected: entry.id == selectedID)
                                .selectionFrame(entry.id == selectedID)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelectEntry(entry) }
                                .simultaneousGesture(
                                    TapGesture(count: 2).onEnded {
                                        onSelectEntry(entry)
                                        onActivateEntry(entry)
                                    }
                                )
                                .onRightClick { onEntryActions(entry) }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedRowID, atOrigin: firstRowSelected, proxy: proxy)
        }
    }

    @ViewBuilder
    private var transferStatus: some View {
        if coordinator.isUploading || !coordinator.summary.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if coordinator.isUploading {
                    HStack {
                        Text(coordinator.currentFileName ?? "准备上传…")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(coordinator.isCancelling ? "正在取消…" : "取消上传", action: coordinator.cancelUpload)
                            .disabled(coordinator.isCancelling)
                    }
                    if coordinator.expectedBytes > 0 {
                        ProgressView(
                            value: min(Double(coordinator.sentBytes) / Double(coordinator.expectedBytes), 1))
                            .transaction { $0.animation = nil }
                        Text(progressDetail)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                } else {
                    Text(coordinator.summary)
                    HStack {
                        if coordinator.retryCount > 0 {
                            Button("重试未完成（\(coordinator.retryCount)）", action: coordinator.retryFailed)
                        }
                        if !coordinator.completedLinks.isEmpty {
                            Button("复制本次链接", action: coordinator.copyCompletedLinks)
                        }
                    }
                    ForEach(Array(coordinator.failureMessages.enumerated()), id: \.offset) { _, message in
                        Text(message)
                            .foregroundStyle(Theme.Colors.destructive)
                            .lineLimit(2)
                            .help(message)
                    }
                }
            }
            .font(Theme.Typography.rowTrailing)
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.cardFill, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .padding(.bottom, Theme.Spacing.sm)
            .id(coordinator.isUploading)
            .transition(.asymmetric(insertion: .opacity, removal: .identity))
        }
    }

    private var progressDetail: String {
        let sent = ByteCountFormatter.string(fromByteCount: coordinator.sentBytes, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: coordinator.expectedBytes, countStyle: .file)
        let status = coordinator.sentBytes >= coordinator.expectedBytes ? "等待服务器确认" : "上传中"
        return "\(sent) / \(total) · \(status)"
    }
}

private struct OSSUploadCard: View {
    let selected: Bool
    let isUploading: Bool
    let completedCount: Int
    let totalCount: Int
    let currentFileName: String?
    let onSelect: () -> Void
    let onChooseFiles: () -> Void
    let onPasteFiles: () -> Void
    let onActions: () -> Void
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return Theme.Colors.cardFill
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.xl) {
            RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous)
                .fill(Theme.Colors.controlSurface)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                .overlay {
                    if isUploading {
                        ProgressView().controlSize(.small)
                    } else {
                        SymbolImage(
                            name: "icloud.and.arrow.up", size: Theme.Size.menuIcon
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(isUploading ? progressTitle : "Upload files")
                    .font(Theme.Typography.rowTitle.weight(.semibold))
                    .lineLimit(1)
                Text(
                    isUploading
                        ? currentFileName ?? String(localized: "Preparing…")
                        : "支持 ⌘V 粘贴截图、Finder 文件，或选择文件。"
                )
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
            Spacer(minLength: Theme.Spacing.xl)
            HStack(spacing: Theme.Spacing.sm) {
                uploadButton("Paste", symbol: "doc.on.clipboard") {
                    onSelect()
                    onPasteFiles()
                }
                uploadButton("Choose…", symbol: "folder") {
                    onSelect()
                    onChooseFiles()
                }
            }
            .disabled(isUploading)
            .opacity(isUploading ? 0.45 : 1)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(fill)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .stroke(Theme.Colors.cardStroke)
                }
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onRightClick {
            onSelect()
            onActions()
        }
        .armedHover($hovered)
        .padding(.bottom, Theme.Spacing.xs)
    }

    private var progressTitle: String {
        String(localized: "Uploading \(min(completedCount + 1, totalCount)) of \(totalCount)")
    }

    private func uploadButton(
        _ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                SymbolImage(name: symbol, size: Theme.Size.menuIcon)
                Text(title)
            }
            .font(Theme.Typography.bar)
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(height: Theme.Size.barButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.keyCap, style: .continuous)
                    .fill(Theme.Colors.controlSurface))
        }
        .buttonStyle(.plain)
    }
}

private struct OSSUploadHistoryRow: View {
    let entry: OSSUploadHistoryEntry
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous)
                .fill(Theme.Colors.controlSurface)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                .overlay {
                    SymbolImage(name: "doc", size: Theme.Size.menuIcon)
                        .foregroundStyle(.secondary)
                }
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(entry.fileName)
                    .font(Theme.Typography.rowTitle)
                    .lineLimit(1)
                Text(entry.objectKey)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Theme.Spacing.xl)
            VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                Text(entry.uploadedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(linkStatus)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(entry.isExpired(at: Date()) ? Theme.Colors.destructive : .secondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(fill)
        )
        .armedHover($hovered)
    }

    private var linkStatus: String {
        guard let expiresAt = entry.expiresAt else { return String(localized: "Public") }
        guard !entry.isExpired(at: Date()) else { return String(localized: "Expired") }
        return String(
            localized:
                "Expires \(expiresAt.formatted(date: .abbreviated, time: .shortened))")
    }
}
