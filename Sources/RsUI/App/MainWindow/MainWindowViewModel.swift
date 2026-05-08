import Foundation
import Observation
import WinUI
import RsHelper

class MainWindowTab {
    var backwardPages: [Page] = []
    var forwardPages: [Page] = []
    var currentPage: Page? = nil
    var navigationTransitionInfo: NavigationTransitionInfo? = nil
    var needsRender: Bool = false

    init(page: Page, transitionInfoOverride: NavigationTransitionInfo? = nil) {
        navigate(to: page, transitionInfoOverride: transitionInfoOverride)
    }

    func navigate(to page: Page, transitionInfoOverride: NavigationTransitionInfo? = nil, maxHistoryPages: Int) {
        navigationTransitionInfo = transitionInfoOverride
        needsRender = true
        if currentPage === page {
            currentPage = page
        } else {
            if let previousPage = currentPage {
                backwardPages.append(previousPage)
                if backwardPages.count > maxHistoryPages {
                    backwardPages.removeFirst()
                }
            }
            currentPage = page
            forwardPages.removeAll()
        }
    }

    func navigate(to page: Page, transitionInfoOverride: NavigationTransitionInfo? = nil) {
        navigationTransitionInfo = transitionInfoOverride
        currentPage = page
        needsRender = true
    }

    func goBack(_ transitionInfoOverride: NavigationTransitionInfo? = nil) {
        guard !backwardPages.isEmpty else { return }

        navigationTransitionInfo = transitionInfoOverride
        needsRender = true
        if let page = currentPage {
            forwardPages.append(page)
        }
        currentPage = backwardPages.removeLast()
    }

    func goForward(_ transitionInfoOverride: NavigationTransitionInfo? = nil) {
        guard !forwardPages.isEmpty else { return }

        navigationTransitionInfo = transitionInfoOverride
        needsRender = true
        if let page = currentPage {
            backwardPages.append(page)
        }
        currentPage = forwardPages.removeLast()
    }
}

@Observable
class MainWindowViewModel {
    var windowPosition: WindowPosition
    var windowLayout: WindowLayout
    var routePreferences: RoutePreferences

    var tabs: [MainWindowTab] = []
    var selectedTab: MainWindowTab? = nil
    var navigationRevision: Int = 0

    var backwardPages: [Page] = []
    var forwardPages: [Page] = []
    var currentPage: Page? {
        selectedTab?.currentPage
    }
    var navigationTransitionInfo: NavigationTransitionInfo? {
        selectedTab?.navigationTransitionInfo
    }

    init() {
        windowPosition = App.context.preferences.load(for: WindowPosition.self)
        windowLayout = App.context.preferences.load(for: WindowLayout.self)
        routePreferences = App.context.preferences.load(for: RoutePreferences.self)
    }

    deinit {
        App.context.preferences.save(windowPosition)
        App.context.preferences.save(windowLayout)
        App.context.preferences.save(routePreferences)
    }

    @discardableResult
    func navigate(to page: Page, transitionInfoOverride: NavigationTransitionInfo? = nil, inNewTab: Bool = false) -> MainWindowTab {
        let tab: MainWindowTab
        if inNewTab || selectedTab == nil {
            tab = addTab(for: page, transitionInfoOverride: transitionInfoOverride)
        } else {
            tab = selectedTab!
            tab.navigate(
                to: page,
                transitionInfoOverride: transitionInfoOverride,
                maxHistoryPages: routePreferences.maxHistoryPages
            )
        }

        selectedTab = tab
        routePreferences.lastPageURL = page.url
        syncLegacyHistory()
        navigationRevision += 1
        return tab
    }

    func goBack(_ transitionInfoOverride: NavigationTransitionInfo? = nil) {
        guard let selectedTab, !selectedTab.backwardPages.isEmpty else { return }

        selectedTab.goBack(transitionInfoOverride)
        routePreferences.lastPageURL = currentPage?.url
        syncLegacyHistory()
        navigationRevision += 1
    }

    func goForward(_ transitionInfoOverride: NavigationTransitionInfo? = nil) {
        guard let selectedTab, !selectedTab.forwardPages.isEmpty else { return }

        selectedTab.goForward(transitionInfoOverride)
        routePreferences.lastPageURL = currentPage?.url
        syncLegacyHistory()
        navigationRevision += 1
    }

    func select(tab: MainWindowTab) {
        guard tabs.contains(where: { $0 === tab }) else { return }
        selectedTab = tab
        routePreferences.lastPageURL = tab.currentPage?.url
        syncLegacyHistory()
        navigationRevision += 1
    }

    func close(tab: MainWindowTab) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0 === tab }) else { return }

        let wasSelected = selectedTab === tab
        tabs.remove(at: index)
        if wasSelected {
            selectedTab = tabs[min(index, tabs.count - 1)]
            routePreferences.lastPageURL = selectedTab?.currentPage?.url
        }
        syncLegacyHistory()
        navigationRevision += 1
    }

    func dumpHistory() {
        for (index, page) in (selectedTab?.backwardPages ?? []).enumerated() {
            log.info("\(index) <===\(page.url)")
        }
        log.info("-----------------------------------------------")
        log.info("====\(currentPage?.url.absoluteString ?? "nil")")
        log.info("-----------------------------------------------")
        for (index, page) in (selectedTab?.forwardPages ?? []).enumerated() {
            log.info("\(index) ===>\(page.url)")
        }
    }

    private func addTab(for page: Page, transitionInfoOverride: NavigationTransitionInfo?) -> MainWindowTab {
        let tab = MainWindowTab(page: page, transitionInfoOverride: transitionInfoOverride)
        tabs.append(tab)
        return tab
    }

    private func syncLegacyHistory() {
        backwardPages = selectedTab?.backwardPages ?? []
        forwardPages = selectedTab?.forwardPages ?? []
    }
}
