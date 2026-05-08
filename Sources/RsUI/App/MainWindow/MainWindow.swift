import Foundation
import Observation
import WindowsFoundation
import UWP
import WinAppSDK
import WinUI
import WinSDK
import RsHelper

fileprivate func tr(_ keyAndValue: String) -> String {
    return App.context.tr(keyAndValue)
}

fileprivate extension WindowPosition {
    var windowRect: RectInt32 {
        return RectInt32(
            x: Int32(windowX),
            y: Int32(windowY),
            width: Int32(windowWidth),
            height: Int32(windowHeight)
        )
    }
}

/// 主窗口类，管理整个应用的导航和 UI 布局
private final class PageViewParts {
    var contentBorder: Border?
    var headerBorder: Border?
}

class MainWindow: Window {
    // MARK: - 属性
    private var viewModel: MainWindowViewModel! = MainWindowViewModel()
    private var isSyncingSelection = false
    private var isSyncingTabSelection = false

    // Splitter state
    private var splitterBorder: Border!
    private var isDraggingSplitter = false
    private var dragStartX: Double = 0
    private var dragStartPaneLength: Double = 0
    private let splitterWidth: Double = 6

    private var openInNewTabRequested: Bool = false

    /// UI 主要组件
    private static func makeNavButton(glyph: String, action: @escaping () -> Void) -> Button {
        let icon = FontIcon()
        icon.glyph = glyph
        icon.fontSize = 12
        let btn = Button()
        btn.content = icon
        btn.width = 28
        btn.height = 28
        btn.minWidth = 0
        btn.minHeight = 0
        btn.verticalAlignment = .center
        btn.padding = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        btn.isEnabled = false
        btn.allowFocusOnInteraction = false

        let transparent = SolidColorBrush(Colors.transparent)
        let hoverBrush = SolidColorBrush(UWP.Color(a: 0x18, r: 0x80, g: 0x80, b: 0x80))
        let pressedBrush = SolidColorBrush(UWP.Color(a: 0x30, r: 0x80, g: 0x80, b: 0x80))
        for key in ["ButtonBackground", "ButtonBackgroundDisabled"] {
            _ = btn.resources.insert(key, transparent)
        }
        _ = btn.resources.insert("ButtonBackgroundPointerOver", hoverBrush)
        _ = btn.resources.insert("ButtonBackgroundPressed", pressedBrush)
        for key in ["ButtonBorderBrush", "ButtonBorderBrushPointerOver",
                     "ButtonBorderBrushPressed", "ButtonBorderBrushDisabled"] {
            _ = btn.resources.insert(key, transparent)
        }

        btn.click.addHandler { _, _ in action() }
        return btn
    }

    private lazy var backButton: Button = MainWindow.makeNavButton(glyph: "\u{E72B}") { [weak self] in
        guard let self else { return }
        self.viewModel.goBack(MainWindow.makeSlideTransition(effect: .fromLeft))
        self.renderSelectedTab()
    }
    private lazy var forwardButton: Button = MainWindow.makeNavButton(glyph: "\u{E72A}") { [weak self] in
        guard let self else { return }
        self.viewModel.goForward(MainWindow.makeSlideTransition(effect: .fromRight))
        self.renderSelectedTab()
    }
    private lazy var searchBox: AutoSuggestBox? = {
        // let box = AutoSuggestBox()
        // box.width = 360
        // box.height = 32
        // box.minWidth = 280
        // box.verticalAlignment = .center
        // return box
        return nil
    } ()
    private lazy var titleBarRightHeader = {
        let panel = StackPanel()
        panel.orientation = .horizontal
        return panel
    } ()
    private lazy var titleBar = {
        let bar = TitleBar()
        bar.height = 48
        bar.isBackButtonVisible = false
        bar.isPaneToggleButtonVisible = true

        if let iconPath = App.context.iconPath {
            let bitmap = BitmapImage()
            bitmap.uriSource = Uri(iconPath)

            let iconSource = ImageIconSource()
            iconSource.imageSource = bitmap
            bar.iconSource = iconSource
        }

        let barContentStackPanel = StackPanel()
        barContentStackPanel.orientation = .horizontal
        barContentStackPanel.spacing = 20
        let navButtons = StackPanel()
        navButtons.orientation = .horizontal
        navButtons.spacing = 2
        navButtons.children.append(self.backButton)
        navButtons.children.append(self.forwardButton)
        barContentStackPanel.children.append(navButtons)
        bar.content = barContentStackPanel

        if let searchBox {
            barContentStackPanel.children.append(searchBox)
        }

        bar.rightHeader = titleBarRightHeader

        bar.paneToggleRequested.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.navigationView.isPaneOpen.toggle()
        }

        return bar
    } ()
    private lazy var tabView: TabView = {
        let tabs = TabView()
        tabs.isAddTabButtonVisible = true
        tabs.tabWidthMode = .equal
        tabs.closeButtonOverlayMode = .onPointerOver
        return tabs
    } ()
    private lazy var tabContentHost = Grid()
    private lazy var navigationContentRoot: Grid = {
        let grid = Grid()

        let tabRow = RowDefinition()
        tabRow.height = GridLength(value: 1, gridUnitType: .auto)
        let contentRow = RowDefinition()
        contentRow.height = GridLength(value: 1, gridUnitType: .star)
        grid.rowDefinitions.append(tabRow)
        grid.rowDefinitions.append(contentRow)

        grid.children.append(tabView)
        try? Grid.setRow(tabView, 0)

        grid.children.append(tabContentHost)
        try? Grid.setRow(tabContentHost, 1)

        return grid
    } ()
    private var tabItemsByID: [ObjectIdentifier: TabViewItem] = [:]
    private var tabFramesByID: [ObjectIdentifier: PageTransitionHost] = [:]
    private var tabPageViewPartsByID: [ObjectIdentifier: PageViewParts] = [:]
    private var tabStripIDs: [ObjectIdentifier] = []
    private var tabTitlesByID: [ObjectIdentifier: String] = [:]
    private var tabClosableByID: [ObjectIdentifier: Bool] = [:]
    private var visibleTabFrameID: ObjectIdentifier?
    private var isFirstNavigation = true
    private lazy var navigationView = {
        let nav = NavigationView()
        nav.paneDisplayMode = .left
        nav.isSettingsVisible = true
        nav.isBackButtonVisible = .collapsed
        nav.isPaneToggleButtonVisible = false
        nav.paneDisplayMode = .auto

        let length = viewModel.windowLayout.navigationViewOpenPaneLength
        nav.compactModeThresholdWidth = 0
        nav.expandedModeThresholdWidth = length + viewModel.windowLayout.navigationViewExpandedModeThresholdContentWidth
        nav.isPaneOpen = viewModel.windowLayout.navigationViewPaneOpen
        nav.openPaneLength = length        
        nav.content = navigationContentRoot

        return nav
    } ()

    // MARK: - 初始化
    override init() {
        super.init()

        setupWindow()
        setupContent()

        startObserving()
    }

    private static func makeSlideTransition(effect: SlideNavigationTransitionEffect) -> NavigationTransitionInfo {
        let transition = SlideNavigationTransitionInfo()
        transition.effect = effect
        return transition
    }

    func navigate(to page: Page, transitionInfoOverride: NavigationTransitionInfo? = nil) {
        let inNewTab = openInNewTabRequested
        openInNewTabRequested = false
        navigate(to: page, transitionInfoOverride: transitionInfoOverride, inNewTab: inNewTab)
    }

    private func navigate(to page: Page, transitionInfoOverride: NavigationTransitionInfo? = nil, inNewTab: Bool) {
        viewModel.navigate(
            to: page,
            transitionInfoOverride: transitionInfoOverride,
            inNewTab: inNewTab
        )
        renderSelectedTab()
    }

    func navigate(to url: URL, transitionInfoOverride: NavigationTransitionInfo? = nil) -> Bool {
        let inNewTab = openInNewTabRequested
        openInNewTabRequested = false
        return navigate(to: url, transitionInfoOverride: transitionInfoOverride, inNewTab: inNewTab)
    }

    @discardableResult
    private func navigate(to url: URL, transitionInfoOverride: NavigationTransitionInfo? = nil, inNewTab: Bool) -> Bool {
        if !inNewTab, viewModel.currentPage?.url == url {
            return true
        }

        if url == SettingsPage.url {
            navigate(to: SettingsPage(), transitionInfoOverride: transitionInfoOverride, inNewTab: inNewTab)
            return true
        } else {
            let context = WindowContext(owner: self)
            for module in App.context.modules {
                if let page = module.navigationRequested(for: url, in: context) {
                    navigate(to: page, transitionInfoOverride: transitionInfoOverride, inNewTab: inNewTab)
                    return true
                }
            }
        }
        return false
    }
 
    /// 配置窗口基本属性
    private func setupWindow() {
        self.extendsContentIntoTitleBar = true
        self.appWindow.titleBar.preferredHeightOption = .tall
                
        // 设置 Mica 背景
        let micaBackdrop = MicaBackdrop()
        micaBackdrop.kind = .base
        self.systemBackdrop = micaBackdrop

        self.sizeChanged.addHandler { [weak self] _, _ in
            self?.trackWindowSize()
        }
        self.closed.addHandler { [weak self] _, _ in
            guard let self else { return }

            // TODO: appWindow.changed事件不工作，此处窗口最大化时记录有缺陷。其实也可以不保存，恢复窗口在中间即可。
            self.trackWindowPosition()
            self.viewModel.windowLayout.navigationViewPaneOpen = self.navigationView.isPaneOpen
            self.viewModel.windowLayout.navigationViewOpenPaneLength = self.navigationView.openPaneLength
            self.viewModel = nil
        }
        restoreWindowRect()
    }

    /// 初始化主要的 UI 布局
    private func setupContent() {
        let root = Grid()

        // 设置行定义
        let titleRowDef = RowDefinition()
        titleRowDef.height = GridLength(value: 1, gridUnitType: .auto)
        root.rowDefinitions.append(titleRowDef)
        
        let contentRowDef = RowDefinition()
        contentRowDef.height = GridLength(value: 1, gridUnitType: .star)
        root.rowDefinitions.append(contentRowDef)
        
        root.children.append(titleBar)
        try? Grid.setRow(titleBar, 0)
        try? setTitleBar(titleBar)
        
        navigationView.selectionChanged.addHandler { [weak self] _, args in
            guard let self, let args, !self.isSyncingSelection else { return }

            if args.isSettingsSelected {
                navigate(to: SettingsPage(), transitionInfoOverride: SuppressNavigationTransitionInfo())
            } else if
                let item = args.selectedItem as? NavigationViewItem,
                let tag = item.tag,
                let str = tag as? HString,
                let url = URL(string: String(hString: str)) {
                _ = navigate(to: url, transitionInfoOverride: SuppressNavigationTransitionInfo())
            }
        }

        tabView.selectionChanged.addHandler { [weak self] sender, args in
            guard let self, !self.isSyncingTabSelection else { return }
            guard let item = self.selectedTabViewItem(sender: sender, args: args) else { return }
            guard let tab = self.tab(for: item) else { return }
            self.switchToTab(tab)
        }

        tabView.tabCloseRequested.addHandler { [weak self] _, args in
            guard let self, let args, let item = args.tab else { return }
            self.closeTab(for: item)
        }

        tabView.addTabButtonClick.addHandler { [weak self] _, _ in
            self?.openNewTabFromTabStrip()
        }

        navigationView.paneClosed.addHandler { [weak self] _, _ in
            self?.splitterBorder.visibility = .collapsed
        }
        navigationView.paneOpened.addHandler { [weak self] _, _ in
            self?.splitterBorder.visibility = .visible
        }

        // Wrap NavigationView with splitter overlay
        let navWrapper = Grid()
        navWrapper.children.append(navigationView)
        splitterBorder = makeSplitterBorder()
        navWrapper.children.append(splitterBorder)
        try? Canvas.setZIndex(splitterBorder, 10)

        root.children.append(navWrapper)
        try? Grid.setRow(navWrapper, 1)

        self.content = root
    }

    private func startObserving() { 
        let env = Observations {
            (App.context.theme, App.context.language)
        }
        Task { [weak self] in
            for await _ in env {
                await MainActor.run { [weak self] in
                    self?.applyAppearance()
                }
            }
        }

        let route = Observations {
            self.viewModel.navigationRevision
        }
        Task { [weak self] in
            for await _ in route {
                await MainActor.run { [weak self] in
                    self?.renderSelectedTab()
                }
            }
        }
    }

    private func renderSelectedTab() {
        syncTabItems()
        updateTabStripVisibility()

        guard let tab = viewModel.selectedTab, let page = tab.currentPage else {
            navigationView.header = nil
            hideAllTabFrames()
            navigationView.selectedItem = nil
            backButton.isEnabled = false
            forwardButton.isEnabled = false
            return
        }

        navigationView.header = nil
        updateTabItemState(for: tab)
        let frame = showFrame(for: tab)

        if tab.needsRender {
            let effectiveTransitionInfo: NavigationTransitionInfo?
            if isFirstNavigation {
                effectiveTransitionInfo = SuppressNavigationTransitionInfo()
                isFirstNavigation = false
            } else {
                effectiveTransitionInfo = tab.navigationTransitionInfo
            }
            frame.transition(
                to: makePageView(page, for: tab),
                transitionInfo: effectiveTransitionInfo
            )
            tab.needsRender = false
        }

        let tabItem = tabViewItem(for: tab)
        if tabView.selectedItem as? TabViewItem !== tabItem {
            isSyncingTabSelection = true
            tabView.selectedItem = tabItem
            isSyncingTabSelection = false
        }

        syncNavigationSelection(for: page.url)
        backButton.isEnabled = !tab.backwardPages.isEmpty
        forwardButton.isEnabled = !tab.forwardPages.isEmpty
    }

    private func syncTabItems() {
        guard let items = tabView.tabItems else { return }

        let ids = viewModel.tabs.map { ObjectIdentifier($0) }
        let activeIDs = Set(ids)
        tabItemsByID = tabItemsByID.filter { activeIDs.contains($0.key) }
        tabTitlesByID = tabTitlesByID.filter { activeIDs.contains($0.key) }
        tabClosableByID = tabClosableByID.filter { activeIDs.contains($0.key) }
        tabPageViewPartsByID = tabPageViewPartsByID.filter { activeIDs.contains($0.key) }
        removeClosedTabFrames(activeIDs: activeIDs)

        guard ids != tabStripIDs else {
            return
        }

        while items.size > viewModel.tabs.count {
            items.removeAt(items.size - 1)
        }

        for (index, tab) in viewModel.tabs.enumerated() {
            let tabItem = tabViewItem(for: tab)
            if UInt32(index) < items.size, let item = items.getAt(UInt32(index)) as? TabViewItem, item === tabItem {
                continue
            }

            if UInt32(index) < items.size {
                items.removeAt(UInt32(index))
            }
            items.insertAt(UInt32(index), tabItem)
        }
        tabStripIDs = ids
        updateAllTabItemCloseStates()
    }

    private func updateTabStripVisibility() {
        tabView.visibility = viewModel.tabs.count <= 1 ? .collapsed : .visible
    }

    private func openNewTabFromTabStrip() {
        if let url = firstNavigationItemURL() {
            openInNewTabRequested = true
            _ = navigate(to: url, transitionInfoOverride: SuppressNavigationTransitionInfo())
        } else {
            openInNewTabRequested = true
            navigate(to: SettingsPage(), transitionInfoOverride: SuppressNavigationTransitionInfo())
        }
    }

    private func tabViewItem(for tab: MainWindowTab) -> TabViewItem {
        let id = ObjectIdentifier(tab)
        if let item = tabItemsByID[id] {
            return item
        }

        let item = TabViewItem()
        item.tapped.addHandler { [weak self, weak item] _, _ in
            guard let self, let item, let tab = self.tab(for: item) else { return }
            self.switchToTab(tab)
        }
        item.closeRequested.addHandler { [weak self, weak item] _, _ in
            guard let self, let item else { return }
            self.closeTab(for: item)
        }
        tabItemsByID[id] = item
        updateTabItemState(for: tab)
        return item
    }

    private func updateTabItemState(for tab: MainWindowTab) {
        let id = ObjectIdentifier(tab)
        guard let item = tabItemsByID[id] else { return }

        let newTitle = title(for: tab.currentPage)
        if tabTitlesByID[id] != newTitle {
            item.header = newTitle
            tabTitlesByID[id] = newTitle
        }

        let canClose = viewModel.tabs.count > 1
        if tabClosableByID[id] != canClose {
            item.isClosable = canClose
            tabClosableByID[id] = canClose
        }
    }

    private func updateAllTabItemCloseStates() {
        for tab in viewModel.tabs {
            updateTabItemState(for: tab)
        }
    }

    private func frame(for tab: MainWindowTab) -> PageTransitionHost {
        let id = ObjectIdentifier(tab)
        if let frame = tabFramesByID[id] {
            return frame
        }

        let frame = PageTransitionHost()
        frame.visibility = .collapsed
        tabFramesByID[id] = frame
        tabContentHost.children.append(frame)
        return frame
    }

    private func showFrame(for tab: MainWindowTab) -> PageTransitionHost {
        let id = ObjectIdentifier(tab)
        let selectedFrame = frame(for: tab)
        guard visibleTabFrameID != id else {
            return selectedFrame
        }

        for (frameID, frame) in tabFramesByID {
            frame.visibility = frameID == id ? .visible : .collapsed
        }
        visibleTabFrameID = id
        return selectedFrame
    }

    private func hideAllTabFrames() {
        for frame in tabFramesByID.values {
            frame.visibility = .collapsed
        }
        visibleTabFrameID = nil
    }

    private func removeClosedTabFrames(activeIDs: Set<ObjectIdentifier>) {
        let closedIDs = tabFramesByID.keys.filter { !activeIDs.contains($0) }
        for id in closedIDs {
            guard let frame = tabFramesByID.removeValue(forKey: id) else { continue }
            removeTabFrame(frame)
            if visibleTabFrameID == id {
                visibleTabFrameID = nil
            }
        }
    }

    private func removeTabFrame(_ frame: PageTransitionHost) {
        var idx: UInt32 = 0
        if tabContentHost.children.indexOf(frame, &idx) {
            tabContentHost.children.removeAt(idx)
        }
    }

    private func tab(for item: TabViewItem) -> MainWindowTab? {
        for tab in viewModel.tabs {
            if tabItemsByID[ObjectIdentifier(tab)] === item {
                return tab
            }
        }
        return nil
    }

    private func selectedTabViewItem(sender: Any?, args: SelectionChangedEventArgs?) -> TabViewItem? {
        if
            let args,
            let addedItems = args.addedItems,
            addedItems.size > 0,
            let item = addedItems.getAt(0) as? TabViewItem {
            return item
        }

        if let tabView = sender as? TabView {
            return tabView.selectedItem as? TabViewItem
        }

        return tabView.selectedItem as? TabViewItem
    }

    private func switchToTab(_ tab: MainWindowTab) {
        guard viewModel.selectedTab !== tab else { return }
        viewModel.select(tab: tab)
        renderSelectedTab()
    }

    private func closeTab(for item: TabViewItem) {
        guard let tab = tab(for: item) else { return }
        viewModel.close(tab: tab)
        renderSelectedTab()
    }

    private func firstNavigationItemURL() -> URL? {
        return firstNavigationItemURL(in: navigationView.menuItems)
            ?? firstNavigationItemURL(in: navigationView.footerMenuItems)
    }

    private func firstNavigationItemURL(in items: AnyIVector<Any?>?) -> URL? {
        guard let items else { return nil }

        for item in items {
            guard let navItem = item as? NavigationViewItem else { continue }
            if
                let tag = navItem.tag,
                let str = tag as? HString,
                let url = URL(string: String(hString: str)) {
                return url
            }
            if let url = firstNavigationItemURL(in: navItem.menuItems) {
                return url
            }
        }

        return nil
    }

    private func title(for page: Page?) -> String {
        guard let page else { return tr("New Tab") }
        if let text = page.header as? String, !text.isEmpty {
            return text
        }

        let host = page.url.host ?? page.url.absoluteString
        return host.isEmpty ? page.url.absoluteString : host
    }

    private func makePageView(_ page: Page, for tab: MainWindowTab) -> UIElement {
        let tabID = ObjectIdentifier(tab)
        let parts = tabPageViewPartsByID[tabID] ?? PageViewParts()
        parts.contentBorder?.child = nil
        parts.headerBorder?.child = nil
        parts.contentBorder = nil
        parts.headerBorder = nil
        tabPageViewPartsByID[tabID] = parts

        guard let header = page.header else {
            return page.content
        }

        let grid = Grid()
        let autoRow = RowDefinition()
        autoRow.height = GridLength(value: 0, gridUnitType: .auto)
        let starRow = RowDefinition()
        starRow.height = GridLength(value: 1, gridUnitType: .star)
        grid.rowDefinitions.append(autoRow)
        grid.rowDefinitions.append(starRow)

        // Row 0: header, margin matches NavigationViewHeaderMargin (56,44,0,0)
        let headerBorder = Border()
        headerBorder.margin = Thickness(left: 56, top: 44, right: 0, bottom: 0)
        if let text = header as? String {
            let tb = TextBlock()
            tb.text = text
            tb.fontSize = 28
            tb.fontWeight = FontWeights.semiBold
            tb.textWrapping = .wrap
            headerBorder.child = tb
        } else if let view = header as? UIElement {
            headerBorder.child = view
            parts.headerBorder = headerBorder
        } else {
            return page.content
        }

        // Row 1: content
        let contentBorder = Border()
        contentBorder.child = page.content
        parts.contentBorder = contentBorder

        try? Grid.setRow(headerBorder, 0)
        try? Grid.setRow(contentBorder, 1)
        grid.children.append(headerBorder)
        grid.children.append(contentBorder)
        return grid
    }

    private func syncNavigationSelection(for url: URL) {
        isSyncingSelection = true
        defer { isSyncingSelection = false }
        
        navigationView.selectItem(with: url)
    }

    private func captureOpenInNewTabRequested(_ args: PointerRoutedEventArgs?) {
        guard let args = args else { return }
        let rawValue = Int(args.keyModifiers.rawValue)
        openInNewTabRequested = (rawValue & 0x1) != 0
        print("ctrl was \(openInNewTabRequested ? "" : "not") pressed when navigationView was clicked")
    }

    private func appendNavigationItem(_ item: NavigationViewItemBase, _ isFooter: Bool) {
        item.pointerPressed.addHandler { [weak self, weak item] _, args in
            guard let self else { return }
            self.captureOpenInNewTabRequested(args)
            guard self.openInNewTabRequested, let item else { return }
            self.openSelectedNavigationItemInNewTabIfNeeded(item, args)
        }
        if isFooter {
            navigationView.footerMenuItems.append(item)
        } else {
            navigationView.menuItems.append(item)
        }
    }

    private func openSelectedNavigationItemInNewTabIfNeeded(_ item: NavigationViewItemBase, _ args: PointerRoutedEventArgs?) {
        guard isNavigationItemSelected(item), let url = url(for: item) else { return }

        args?.handled = true
        openInNewTabRequested = false

        let queued = (try? dispatcherQueue?.tryEnqueue { [weak self] in
            guard let self else { return }
            _ = self.navigate(
                to: url,
                transitionInfoOverride: SuppressNavigationTransitionInfo(),
                inNewTab: true
            )
        }) ?? false

        if !queued {
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = self.navigate(
                    to: url,
                    transitionInfoOverride: SuppressNavigationTransitionInfo(),
                    inNewTab: true
                )
            }
        }
    }

    private func isNavigationItemSelected(_ item: NavigationViewItemBase) -> Bool {
        guard let selectedItem = navigationView.selectedItem as? NavigationViewItemBase else { return false }
        return selectedItem === item
    }

    private func url(for item: NavigationViewItemBase) -> URL? {
        guard
            let navItem = item as? NavigationViewItem,
            let tag = navItem.tag,
            let str = tag as? HString
        else {
            return nil
        }

        return URL(string: String(hString: str))
    }

    private func applyAppearance() {
        // For min/max/close buttons. 目前不支持材质效果，但比逐个设置按钮颜色简单，并且容易由框架修正。
        self.appWindow.titleBar.preferredTheme = App.context.theme.titleBarTheme

        self.title = tr(App.context.productName)
        titleBar.title = self.title
        searchBox?.placeholderText = tr("searchControlsAndSamples")

        let context = WindowContext(owner: self)
        titleBarRightHeader.children.clear()
        navigationView.menuItems.clear()
        navigationView.footerMenuItems.clear()
        for module in App.context.modules {
            if let item = module.titleBarRightHeaderItemRequired(in: context) {
                titleBarRightHeader.children.append(item)
            }
            for item in module.navigationViewMenuItemsRequired(in: context) {
                appendNavigationItem(item, false)
            }
            for item in module.navigationViewFooterMenuItemsRequired(in: context) {
                appendNavigationItem(item, true)
            }
        }

        if let page = viewModel.currentPage {
            navigate(to: page)
        } else if let lastURL = viewModel.routePreferences.lastPageURL, navigate(to: lastURL) {
            return
        } else {
            navigationView.selectFirstItem()
        }
    }
    
    private func restoreWindowRect() {
        guard let hwnd = self.appWindow, let presenter = hwnd.presenter as? OverlappedPresenter
        else { return }

        let maximized = viewModel.windowPosition.isMaximized //moveAndResize will cause pref changed in event, so need to reserve here
        try? hwnd.moveAndResize(viewModel.windowPosition.windowRect)
        if maximized {
            try? presenter.maximize()
        }
    }

    private func trackWindowSize() {
        guard let hwnd = self.appWindow, let presenter = hwnd.presenter as? OverlappedPresenter else { return }

        if presenter.state == .restored {
            viewModel.windowPosition.windowWidth = Int(hwnd.size.width)
            viewModel.windowPosition.windowHeight = Int(hwnd.size.height)
            viewModel.windowPosition.isMaximized = false
        } else if presenter.state == .maximized {
            viewModel.windowPosition.isMaximized = true
        }
    }

    private func trackWindowPosition() {
        guard let hwnd = self.appWindow, let presenter = hwnd.presenter as? OverlappedPresenter
        else { return }

        if presenter.state == .restored {
            viewModel.windowPosition.windowX = Int(hwnd.position.x)
            viewModel.windowPosition.windowY = Int(hwnd.position.y)
        }
    }

    // MARK: - Splitter Methods

    private func makeSplitterBorder() -> Border {
        let b = Border()
        b.width = splitterWidth
        b.verticalAlignment = .stretch
        b.horizontalAlignment = .left
        b.background = SolidColorBrush(UWP.Color(a: 0, r: 0, g: 0, b: 0)) // transparent hit area
        b.margin = Thickness(
            left: navigationView.openPaneLength - splitterWidth / 2,
            top: 0, right: 0, bottom: 0
        )
        b.visibility = viewModel.windowLayout.navigationViewPaneOpen ? .visible : .collapsed
        b.protectedCursor = try? InputSystemCursor.create(.sizeWestEast)

        setupSplitterPointerEvents(b)
        return b
    }

    private func setupSplitterPointerEvents(_ splitter: Border) {
        splitter.pointerPressed.addHandler { [weak self] _, args in
            guard let self, let args else { return }
            let point = try? args.getCurrentPoint(nil) // window-relative
            self.isDraggingSplitter = true
            self.dragStartX = Double(point?.position.x ?? 0)
            self.dragStartPaneLength = self.navigationView.openPaneLength
            _ = try? self.splitterBorder.capturePointer(args.pointer)
            args.handled = true
        }

        splitter.pointerMoved.addHandler { [weak self] _, args in
            guard let self, self.isDraggingSplitter, let args else { return }
            let point = try? args.getCurrentPoint(nil) // window-relative
            let currentX = Double(point?.position.x ?? 0)
            let delta = currentX - self.dragStartX
            let newLength = min(self.viewModel.windowLayout.navigationViewMaxPaneLength, max(self.viewModel.windowLayout.navigationViewMinPaneLength, self.dragStartPaneLength + delta))
            self.applyPaneLength(newLength)
            args.handled = true
        }

        splitter.pointerReleased.addHandler { [weak self] _, args in
            guard let self, let args else { return }
            self.isDraggingSplitter = false
            try? self.splitterBorder.releasePointerCapture(args.pointer)
            args.handled = true
        }

        splitter.pointerCaptureLost.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.isDraggingSplitter = false
        }
    }

    private func applyPaneLength(_ length: Double) {
        navigationView.openPaneLength = length
        navigationView.expandedModeThresholdWidth = length + viewModel.windowLayout.navigationViewExpandedModeThresholdContentWidth
        splitterBorder.margin = Thickness(
            left: length - splitterWidth / 2,
            top: 0, right: 0, bottom: 0
        )
    }
}
