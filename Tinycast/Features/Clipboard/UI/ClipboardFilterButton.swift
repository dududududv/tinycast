import SwiftUI

/// The clipboard header's type filter control: it states the active filter and toggles its menu.
struct ClipboardFilterButton: View {
    let filter: ClipboardFilter
    let isOpen: Bool
    let action: () -> Void
    let onSelect: (ClipboardFilter) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.xs) {
                    ForEach(ClipboardFilter.allCases, id: \.self) { value in
                        Button { onSelect(value) } label: {
                            Text(shortTitle(value))
                                .font(Theme.Typography.bar)
                                .padding(.horizontal, Theme.Spacing.lg)
                                .frame(height: Theme.Size.barButtonHeight)
                                .foregroundStyle(value == filter ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                                .background(value == filter ? Theme.Colors.selection : .clear,
                                            in: RoundedRectangle(cornerRadius: Theme.Radius.menu))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(value == filter ? [.isSelected] : [])
                    }
            }
            .fixedSize()
            HeaderMenuButton(
                title: filter.title,
                systemImage: filter.systemImage,
                isOpen: isOpen,
                help: "Filter by type  ⌘P",
                action: action)
        }
    }

    private func shortTitle(_ value: ClipboardFilter) -> String {
        switch value {
        case .all: "全部"
        case .text: "文本"
        case .image: "图片"
        case .link: "链接"
        case .email: "邮箱"
        case .pinned: "收藏"
        }
    }
}
