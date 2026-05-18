import Foundation
import WindowsFoundation
import UWP
import WinUI

extension MainWindow {
    func setupContent() {
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

        configureNavigationViewSelection()
        configureTabViewEvents()
        if MainWindow.isTabTearOffMergeEnabled {
            setupTabDragHint()
        }
        configurePaneEvents()

        let navWrapper = makeNavigationWrapper()
        root.children.append(navWrapper)
        try? Grid.setRow(navWrapper, 1)

        self.content = root
    }

    private func configureNavigationViewSelection() {
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
    }

    private func configureTabViewEvents() {
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

        guard MainWindow.isTabTearOffMergeEnabled else { return }

        // Source: record which tab is being dragged and expose it via static state for cross-window drop.
        tabView.tabDragStarting.addHandler { [weak self] _, args in
            guard let self, let args, let item = args.tab else { return }
            guard let tab = self.tab(for: item) else { return }
            guard let url = tab.currentPage?.url else { return }
            self.draggingTabForDrop = tab
            MainWindow.activeDrag = DragState(sourceWindowID: ObjectIdentifier(self), tabURL: url)
        }

        // Source: flag that the tab was physically dropped outside (vs drag cancelled by Escape).
        tabView.tabDroppedOutside.addHandler { [weak self] _, _ in
            self?.dragDroppedOutside = true
        }

        // Source: decide outcome once drag completes.
        tabView.tabDragCompleted.addHandler { [weak self] _, args in
            guard let self, let args else { return }
            let wasDroppedOutside = self.dragDroppedOutside
            defer {
                self.dragDroppedOutside = false
                self.draggingTabForDrop = nil
                MainWindow.activeDrag = nil
            }
            guard let tab = self.draggingTabForDrop else { return }
            guard self.viewModel.tabs.count > 1 else { return }
            guard self.viewModel.tabs.contains(where: { $0 === tab }) else { return }

            if args.dropResult == .none {
                guard wasDroppedOutside else { return }
                let url = tab.currentPage?.url
                self.viewModel.close(tab: tab)
                self.renderSelectedTab()
                if let url { MainWindow.openDetachedWindow(navigatingTo: url) }
            } else {
                self.viewModel.close(tab: tab)
                self.renderSelectedTab()
            }
        }

        // Destination: accept tab drops from other windows' TabViews.
        tabView.dragOver.addHandler { [weak self] _, args in
            guard let self, let args else { return }
            guard let drag = MainWindow.activeDrag, drag.sourceWindowID != ObjectIdentifier(self) else { return }
            args.acceptedOperation = .move
        }
        tabView.drop.addHandler { [weak self] _, _ in
            guard let self else { return }
            guard let drag = MainWindow.activeDrag, drag.sourceWindowID != ObjectIdentifier(self) else { return }
            _ = self.navigate(to: drag.tabURL, mode: .newTab, transitionInfoOverride: SuppressNavigationTransitionInfo())
        }
    }

    private func configurePaneEvents() {
        navigationView.paneClosed.addHandler { [weak self] _, _ in
            self?.splitterBorder.visibility = .collapsed
        }
        navigationView.paneOpened.addHandler { [weak self] _, _ in
            self?.splitterBorder.visibility = .visible
        }
    }

    private func makeNavigationWrapper() -> Grid {
        let navWrapper = Grid()
        navWrapper.children.append(navigationView)
        splitterBorder = makeSplitterBorder()
        navWrapper.children.append(splitterBorder)
        try? Canvas.setZIndex(splitterBorder, 10)
        return navWrapper
    }
}
