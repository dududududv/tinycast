import AppKit
import SwiftUI

struct ClipboardPanelView: View {
    @Environment(AppCore.self) private var core
    @Environment(PaletteState.self) private var state
    @Environment(ClipboardStore.self) private var store
    @FocusState private var searchFocused: Bool
    @State private var scroll = ScrollIntent(kind: .top)
    @State private var menu: Menu?
    @State private var menuSelection = 0

    private enum Menu { case actions, filters }

    private var screen: ClipboardScreen {
        ClipboardScreen(store: store, core: core, vm: state,
                        openActions: { toggle(.actions) },
                        scrollToFollow: { scroll = ScrollIntent(kind: .follow) })
    }

    private var selection: Int { min(max(0, state.selection), max(0, screen.rows.count - 1)) }

    private var menuContent: PopoverMenuContent? {
        switch menu {
        case .actions: return screen.actions(at: selection)
        case .filters:
            return PopoverMenuContent(items: ClipboardFilter.allCases.map { filter in
                PopoverMenuItem(title: filter.title, systemImage: filter.systemImage) {
                    state.clipboardFilter = filter
                }
            })
        case nil: return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            screen.body(selection: selection, scroll: scroll)
                .frame(minHeight: 0, maxHeight: .infinity)
            HStack {
                Text("\(screen.rows.count) 条记录")
                Spacer()
                Text("← → 选择    ↵ 粘贴    ⌘↵ 复制    esc 关闭")
            }
            .font(Theme.Typography.rowTrailing)
            .foregroundStyle(Theme.Colors.textTertiary)
            .padding(.horizontal, Theme.Spacing.panelInset)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: "clipboardPanel")
        .background(Theme.Colors.panelScrim)
        .background(VisualEffectView())
        .overlay {
            if menu != nil {
                Color.clear.contentShape(Rectangle()).onTapGesture { closeMenu() }
            }
        }
        .overlay(alignment: .topTrailing) {
            if let content = menuContent {
                PopoverMenu(
                    header: content.header, items: content.items, selection: $menuSelection,
                    onActivate: activateMenu)
                .padding(.top, Theme.Size.headerHeight + Theme.Spacing.xl)
                .padding(.trailing, Theme.Spacing.panelInset)
            }
        }
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: Theme.Radius.panel, topTrailingRadius: Theme.Radius.panel,
            style: .continuous))
        .onChange(of: state.focusToken, initial: true) {
            closeMenu()
            searchFocused = true
        }
        .onChange(of: state.query) { resetSelection() }
        .onChange(of: state.clipboardFilter) { resetSelection() }
        .onChange(of: screen.rows.count) { state.selection = selection }
        .onChange(of: menu) { state.menuOpen = menu != nil }
        .onChange(of: state.pinChordToken) { _ = screen.pin(at: selection) }
        .onChange(of: state.favoriteSlotToken) {
            if let index = state.favoriteSlotIndex { _ = screen.activatePinned(at: index) }
        }
        .onKeyPress(.escape) {
            if menu != nil { closeMenu() } else { core.paletteCoordinator.hidePalette() }
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat]) { press in
            let delta = press.key == .leftArrow || press.key == .upArrow ? -1 : 1
            if menu != nil {
                let count = menuContent?.items.count ?? 0
                menuSelection = min(max(0, menuSelection + delta), max(0, count - 1))
            } else {
                if !state.query.isEmpty && (press.key == .leftArrow || press.key == .rightArrow) {
                    return .ignored
                }
                state.selection = min(max(0, selection + delta), max(0, screen.rows.count - 1))
                scroll = ScrollIntent(kind: .follow)
            }
            return .handled
        }
        .onKeyPress(keys: [.return], phases: .down) { press in
            if press.modifiers.contains(.command) {
                _ = screen.secondary(at: selection)
            } else if press.modifiers.contains(.option) {
                _ = screen.pasteKeepingWindowOpen(at: selection)
            } else if menu != nil {
                activateMenu(menuSelection)
            } else {
                return .ignored
            }
            return .handled
        }
        .onKeyPress(keys: ["k", "K", "p", "P", "x", "X"]) { press in
            if press.modifiers.contains(.command) {
                if press.characters.lowercased() == "k" { toggle(.actions); return .handled }
                if press.characters.lowercased() == "p" { toggle(.filters); return .handled }
            }
            if press.modifiers.contains(.control), press.characters.lowercased() == "x" {
                if press.modifiers.contains(.shift) { screen.deleteAll() } else { screen.delete(at: selection) }
                return .handled
            }
            return .ignored
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.xl) {
            headerActions.disabled(true).hidden().allowsHitTesting(false).accessibilityHidden(true)
            Spacer(minLength: 0)
            searchControls
            Spacer(minLength: 0)
            headerActions
        }
        .frame(height: Theme.Size.headerHeight)
        .padding(.horizontal, Theme.Spacing.panelInset)
        .padding(.top, Theme.Spacing.md)
    }

    private var searchControls: some View {
        @Bindable var state = state
        return HStack(spacing: Theme.Spacing.xl) {
            HStack(spacing: Theme.Spacing.md) {
                SymbolImage(name: "magnifyingglass", size: Theme.Size.noteGlyph)
                    .foregroundStyle(Theme.Colors.textTertiary)
                TextField("搜索剪贴板", text: $state.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("clipboardPanel")) } action: {
                        state.searchFieldFrame = $0
                    }
                    .onSubmit {
                        if menu != nil { activateMenu(menuSelection) } else { screen.activate(at: selection) }
                    }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .frame(width: Theme.Size.clipboardSearchWidth, height: Theme.Size.menuButton)
            .background(Theme.Colors.cardFill, in: RoundedRectangle(cornerRadius: Theme.Radius.row))
            ClipboardFilterButton(
                filter: state.clipboardFilter, isOpen: menu == .filters,
                action: { toggle(.filters) },
                onSelect: { state.clipboardFilter = $0; closeMenu() })
        }
    }

    private var headerActions: some View {
        HStack(spacing: Theme.Spacing.xl) {
            BarButton(action: { toggle(.actions) }) {
                SymbolImage(name: "ellipsis", size: Theme.Size.noteGlyph)
            }
            .help("操作 · ⌘K").accessibilityLabel("操作")
            BarButton(action: { core.settingsCoordinator.showSettings() }) {
                SymbolImage(name: "gearshape", size: Theme.Size.noteGlyph)
            }
            .help("设置").accessibilityLabel("设置")
            BarButton(action: { core.paletteCoordinator.hidePalette() }) {
                SymbolImage(name: "xmark", size: Theme.Size.noteGlyph)
            }
            .help("关闭剪贴板 · esc").accessibilityLabel("关闭剪贴板")
        }
        .fixedSize()
    }

    private func toggle(_ requested: Menu) {
        if menu == requested { closeMenu(); return }
        if requested == .actions && screen.rows.isEmpty { return }
        menu = requested
        menuSelection = requested == .filters
            ? ClipboardFilter.allCases.firstIndex(of: state.clipboardFilter) ?? 0 : 0
    }

    private func closeMenu() {
        menu = nil
        state.menuOpen = false
    }

    private func activateMenu(_ index: Int) {
        guard let content = menuContent, content.items.indices.contains(index) else { return }
        closeMenu()
        content.items[index].action()
    }

    private func resetSelection() {
        state.selection = 0
        scroll = ScrollIntent(kind: .top)
    }
}

struct ClipboardList: View {
    let results: [ClipboardItem]
    let selectedID: ClipboardItem.ID?
    let scroll: ScrollIntent
    let onSelect: (ClipboardItem) -> Void
    let onActivate: () -> Void
    let onPin: (ClipboardItem) -> Void
    let onCopy: (ClipboardItem) -> Void
    let onActions: (ClipboardItem) -> Void
    @Environment(ClipboardStore.self) private var store

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: Theme.Spacing.lg) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                            ClipboardCard(
                                item: item, selected: item.id == selectedID, index: index,
                                imageURL: store.imageURL(for: item),
                                onSelect: { onSelect(item) },
                                onActivate: { onSelect(item); onActivate() },
                                onPin: { onPin(item) }, onCopy: { onCopy(item) }
                            )
                            .frame(width: Theme.Size.clipboardCardWidth)
                            .frame(height: max(0, geometry.size.height - Theme.Spacing.panelInset * 2))
                            .id(item.id)
                            .onRightClick { onActions(item) }
                        }
                    }
                    .padding(Theme.Spacing.panelInset)
                }
                .scrollIndicators(.hidden)
                .scrollEdgeEffectStyle(.none, for: .all)
                .onChange(of: scroll, initial: true) {
                    let target = scroll.kind == .top ? results.first?.id : selectedID
                    if let target { proxy.scrollTo(target, anchor: scroll.kind == .top ? .leading : nil) }
                }
            }
        }
    }
}

private struct ClipboardCard: View {
    let item: ClipboardItem
    let selected: Bool
    let index: Int
    let imageURL: URL?
    let onSelect: () -> Void
    let onActivate: () -> Void
    let onPin: () -> Void
    let onCopy: () -> Void
    @Environment(PaletteState.self) private var palette
    @State private var hovered = false
    @State private var summary = ""
    @State private var thumbnail: NSImage?

    private var tint: Color {
        item.kind == .image ? Theme.Colors.clipboardImage : Theme.Colors.clipboardText
    }

    private var kindTitle: String {
        if item.kind == .image { return "图片" }
        switch item.textForm {
        case .link: return "链接"
        case .email: return "邮箱"
        default: return "文本"
        }
    }

    private var sourceURL: URL? {
        IconCache.observeStyle()
        return item.sourceBundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    }

    private var timestamp: String {
        let time = item.createdAt.formatted(.verbatim(
            "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            locale: Locale(identifier: "zh_CN"), timeZone: .current, calendar: Calendar(identifier: .gregorian)))
        guard !Calendar.current.isDateInToday(item.createdAt) else { return time }
        let date = item.createdAt.formatted(.verbatim(
            "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)",
            locale: Locale(identifier: "zh_CN"), timeZone: .current, calendar: Calendar(identifier: .gregorian)))
        return "\(date) \(time)"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            preview.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).clipped()
            footer
        }
        .background(selected ? Theme.Colors.selection : Theme.Colors.cardFill)
        .overlay {
            if hovered && !selected { Theme.Colors.rowHover.allowsHitTesting(false) }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
                .strokeBorder(selected ? Theme.Colors.brand : Theme.Colors.cardStroke, lineWidth: selected ? 2 : 1)
                .allowsHitTesting(false)
        }
        .armedHover($hovered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(kindTitle)，\(sourceURL?.deletingPathExtension().lastPathComponent ?? "未知来源")")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityAction(named: "选择", onSelect)
        .accessibilityAction(named: "粘贴", onActivate)
        .task(id: item.id) { await loadPreview() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text(kindTitle).font(Theme.Typography.sectionHeader).foregroundStyle(tint)
                Spacer(minLength: Theme.Spacing.md)
                sourceIcon
            }
            HStack(spacing: Theme.Spacing.md) {
                Text(timestamp).monospacedDigit().lineLimit(1)
                Spacer(minLength: 0)
                Text(sourceURL?.deletingPathExtension().lastPathComponent ?? "未知来源")
                    .lineLimit(1).truncationMode(.middle)
            }
            .font(Theme.Typography.rowTrailing)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .padding(Theme.Spacing.xl)
        .background(Theme.Colors.cardFill)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onActivate)
        .onTapGesture(perform: onSelect)
    }

    @ViewBuilder
    private var sourceIcon: some View {
        if let sourceURL {
            Image(nsImage: IconCache.icon(forFile: sourceURL.path))
                .resizable().frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
        } else {
            SymbolImage(name: "doc.on.clipboard", size: Theme.Size.rowIcon)
        }
    }

    @ViewBuilder
    private var preview: some View {
        Group {
            if item.kind == .image {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFit()
                } else {
                    SymbolImage(name: "photo", size: Theme.Size.dialogIcon)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView(.vertical) {
                    Text(selected ? item.text ?? "" : String((item.text ?? "").prefix(4000)))
                        .font(.system(.subheadline, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .scrollEdgeEffectStyle(.none, for: .all)
            }
        }
        .padding(Theme.Spacing.xl)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onActivate)
        .onTapGesture(perform: onSelect)
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if item.isPinned, palette.commandHeld, let digit = FavoriteSlots.digit(at: index) {
                Text("⌘\(String(digit))").foregroundStyle(tint)
            } else {
                Text("\(index + 1)").foregroundStyle(Theme.Colors.textTertiary)
            }
            Spacer(minLength: Theme.Spacing.xs)
            Text(summary).lineLimit(1).foregroundStyle(Theme.Colors.textSecondary)
            Spacer(minLength: Theme.Spacing.xs)
            BarButton(action: onPin) {
                SymbolImage(name: item.isPinned ? "pin.fill" : "pin", size: Theme.Size.noteGlyph)
                    .foregroundStyle(item.isPinned ? tint : Theme.Colors.textSecondary)
            }
            .help(item.isPinned ? "取消收藏 · ⌘." : "收藏 · ⌘.")
            .accessibilityLabel(item.isPinned ? "取消收藏" : "收藏")
            BarButton(action: onCopy) {
                SymbolImage(name: "doc.on.doc", size: Theme.Size.noteGlyph)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .help("复制 · ⌘↵")
            .accessibilityLabel("复制")
        }
        .font(Theme.Typography.rowTrailing)
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.sm)
    }

    private func loadPreview() async {
        let text = item.text
        let url = imageURL
        let details = await Task.detached(priority: .utility) {
            if let text { return "\(text.count.formatted()) 个字符" }
            guard let url, let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                return "图片不可用"
            }
            return Int64(bytes).formatted(.byteCount(style: .file))
        }.value
        guard !Task.isCancelled else { return }
        summary = details
        if let url {
            let loaded = await ImageThumbnail.loadAsync(url, maxPixel: Theme.Size.clipboardThumbnailPixels)
            guard !Task.isCancelled else { return }
            thumbnail = loaded
        }
    }
}

/// Coarse date buckets for sectioning, ordered newest-first by raw value.
enum DateBucket: Int {
    case today, yesterday, thisWeek, thisMonth, earlier

    var title: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This Week"
        case .thisMonth: return "This Month"
        case .earlier: return "Earlier"
        }
    }

    init(for date: Date, now: Date = Date(), calendar: Calendar = .current) {
        if calendar.isDateInToday(date) {
            self = .today
        } else if calendar.isDateInYesterday(date) {
            self = .yesterday
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            self = .thisWeek
        } else if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            self = .thisMonth
        } else {
            self = .earlier
        }
    }
}
