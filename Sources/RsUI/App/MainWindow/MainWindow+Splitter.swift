import UWP
import WinAppSDK
import WinUI

extension MainWindow {
    func makeSplitterBorder() -> Border {
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
