import AppKit

struct Grid {
    let origin: CGPoint
    let cellSize: CGSize
    let cols: Int
    let rows: Int

    func cell(at point: CGPoint) -> (col: Int, row: Int)? {
        let col = Int(floor((point.x - origin.x) / cellSize.width))
        let row = Int(floor((point.y - origin.y) / cellSize.height))
        guard (0..<cols).contains(col), (0..<rows).contains(row) else { return nil }
        return (col, row)
    }
}

struct GhosttyPadding {
    var left: CGFloat = 2
    var right: CGFloat = 2
    var top: CGFloat = 2
    var bottom: CGFloat = 2

    static func load() -> GhosttyPadding {
        var padding = GhosttyPadding()
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Ghostty.bundleId) else { return padding }
        let process = Process()
        process.executableURL = app.appendingPathComponent("Contents/MacOS/ghostty")
        process.arguments = ["+show-config"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return padding }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let values = parts[1].split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard let first = values.first else { continue }
            let second = values.count > 1 ? values[1] : first
            switch parts[0] {
            case "window-padding-x": (padding.left, padding.right) = (first, second)
            case "window-padding-y": (padding.top, padding.bottom) = (first, second)
            default: break
            }
        }
        return padding
    }
}

enum Ghostty {
    static let bundleId = "com.mitchellh.ghostty"

    static var pid: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.processIdentifier
    }

    static var isFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleId
    }
}

struct Window {
    let pid: pid_t
    let bounds: CGRect

    static func onScreen() -> [Window] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let rawBounds = info[kCGWindowBounds as String],
                  let bounds = CGRect(dictionaryRepresentation: rawBounds as! CFDictionary)
            else { return nil }
            return Window(pid: pid, bounds: bounds)
        }
    }

    var scale: CGFloat {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return 1 }
        let center = CGPoint(x: bounds.midX, y: primaryHeight - bounds.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }?.backingScaleFactor ?? 1
    }

    func grid(for size: winsize, padding: GhosttyPadding) -> Grid? {
        guard size.ws_col > 0, size.ws_row > 0, size.ws_xpixel > 0, size.ws_ypixel > 0 else { return nil }
        let scale = self.scale
        let surfaceWidth = CGFloat(size.ws_xpixel) / scale + padding.left + padding.right
        let surfaceHeight = CGFloat(size.ws_ypixel) / scale + padding.top + padding.bottom
        guard abs(bounds.width - surfaceWidth) <= 2, bounds.height >= surfaceHeight - 2 else { return nil }
        let cellSize = CGSize(
            width: floor(CGFloat(size.ws_xpixel) / CGFloat(size.ws_col)) / scale,
            height: floor(CGFloat(size.ws_ypixel) / CGFloat(size.ws_row)) / scale
        )
        let origin = CGPoint(x: bounds.minX + padding.left, y: bounds.maxY - surfaceHeight + padding.top)
        return Grid(origin: origin, cellSize: cellSize, cols: Int(size.ws_col), rows: Int(size.ws_row))
    }
}

enum HerdrClients {
    static func ttys(under ancestor: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0 else { return [] }
        let stride = MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 32)
        size = procs.count * stride
        guard sysctl(&mib, u_int(mib.count), &procs, &size, nil, 0) == 0 else { return [] }
        procs.removeLast(procs.count - size / stride)

        let parent = Dictionary(procs.map { ($0.kp_proc.p_pid, $0.kp_eproc.e_ppid) }, uniquingKeysWith: { first, _ in first })
        func descends(_ pid: pid_t) -> Bool {
            var current = pid
            for _ in 0..<32 {
                guard let next = parent[current], next > 1 else { return false }
                if next == ancestor { return true }
                current = next
            }
            return false
        }

        return procs.compactMap { proc in
            let name = withUnsafeBytes(of: proc.kp_proc.p_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            guard name == "herdr",
                  proc.kp_eproc.e_tdev != -1,
                  descends(proc.kp_proc.p_pid),
                  let device = devname(proc.kp_eproc.e_tdev, S_IFCHR)
            else { return nil }
            return "/dev/" + String(cString: device)
        }
    }

    static func size(of tty: String) -> winsize? {
        let fd = open(tty, O_RDONLY | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var size = winsize()
        return ioctl(fd, TIOCGWINSZ, &size) == 0 ? size : nil
    }
}
