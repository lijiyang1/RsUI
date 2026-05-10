import Foundation
import WinUI

extension MainWindow {
    func frame(for tab: MainWindowTab) -> PageTransitionHost {
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

    func showFrame(for tab: MainWindowTab) -> PageTransitionHost {
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

    func hideAllTabFrames() {
        for frame in tabFramesByID.values {
            frame.visibility = .collapsed
        }
        visibleTabFrameID = nil
    }

    func removeClosedTabFrames(activeIDs: Set<ObjectIdentifier>) {
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
}
