import AppKit

final class Cached<Value> {
    private let ttl: TimeInterval
    private let load: () -> Value
    private var stored: (value: Value, at: TimeInterval)?

    init(ttl: TimeInterval, load: @escaping () -> Value) {
        self.ttl = ttl
        self.load = load
    }

    var value: Value {
        let now = ProcessInfo.processInfo.systemUptime
        if let stored, now - stored.at < ttl { return stored.value }
        let value = load()
        stored = (value, now)
        return value
    }

    func invalidate() {
        stored = nil
    }
}

final class Follower {
    private static let mobileWidthThreshold = 64

    private let verbose: Bool
    private let padding = GhosttyPadding.load()
    private let ghosttyPid = Cached(ttl: 5) { Ghostty.pid }
    private let windows = Cached(ttl: 0.25) { Window.onScreen() }
    private let layout = Cached(ttl: 0.25) { Herdr.layout() }
    private lazy var ttys = Cached(ttl: 2) { [unowned self] in
        ghosttyPid.value.map { HerdrClients.ttys(under: $0) } ?? []
    }
    private lazy var sizes = Cached(ttl: 0.25) { [unowned self] in
        ttys.value.compactMap(HerdrClients.size(of:))
    }

    init(verbose: Bool) {
        self.verbose = verbose
        log("padding \(padding)")
    }

    func mouseMoved(to point: CGPoint) {
        guard Ghostty.isFrontmost,
              let grid = grid(under: point),
              grid.cols > Self.mobileWidthThreshold,
              let cell = grid.cell(at: point),
              let layout = layout.value,
              !layout.zoomed
        else { return }

        let colOffset = grid.cols - layout.area.width
        let rowOffset = Herdr.tabBarAtBottom ? 0 : grid.rows - layout.area.height
        let col = cell.col - colOffset + layout.area.x
        let row = cell.row - rowOffset + layout.area.y

        guard let pane = layout.panes.first(where: { $0.rect.contains(col: col, row: row) }),
              pane.paneId != layout.focusedPaneId
        else { return }

        let focused = Herdr.focus(paneId: pane.paneId)
        self.layout.invalidate()
        log("focus \(pane.paneId) at cell \(cell) -> \(focused ? "ok" : "failed")")
    }

    private func grid(under point: CGPoint) -> Grid? {
        guard let ghosttyPid = ghosttyPid.value else { return nil }
        for window in windows.value where window.bounds.contains(point) {
            guard window.pid == ghosttyPid else { return nil }
            for size in sizes.value {
                if let grid = window.grid(for: size, padding: padding) { return grid }
            }
        }
        return nil
    }

    private func log(_ message: String) {
        guard verbose else { return }
        FileHandle.standardError.write(Data("[herdr-hover-focus] \(message)\n".utf8))
    }
}
