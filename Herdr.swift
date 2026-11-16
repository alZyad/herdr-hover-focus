import Foundation

struct CellRect: Decodable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    func contains(col: Int, row: Int) -> Bool {
        col >= x && col < x + width && row >= y && row < y + height
    }
}

struct PaneLayout: Decodable {
    struct Pane: Decodable {
        let paneId: String
        let rect: CellRect
    }

    let zoomed: Bool
    let area: CellRect
    let focusedPaneId: String?
    let panes: [Pane]
}

enum Herdr {
    static let socketPath = ProcessInfo.processInfo.environment["HERDR_SOCKET"]
        ?? NSHomeDirectory() + "/.config/herdr/herdr.sock"

    static let tabBarAtBottom: Bool = {
        let path = NSHomeDirectory() + "/.config/herdr/config.toml"
        guard let config = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
        return config.range(of: #"(?m)^\s*tab_bar_position\s*=\s*"bottom""#, options: .regularExpression) != nil
    }()

    static func layout() -> PaneLayout? {
        struct Response: Decodable {
            struct Result: Decodable { let layout: PaneLayout }
            let result: Result
        }
        guard let data = request(method: "pane.layout", params: [:]) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(Response.self, from: data).result.layout
    }

    static func focus(paneId: String) -> Bool {
        guard let data = request(method: "pane.focus", params: ["pane_id": paneId]),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return json["result"] != nil
    }

    private static func request(method: String, params: [String: Any]) -> Data? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var timeout = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes)
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }

        let body: [String: Any] = ["id": "hover-focus", "method": method, "params": params]
        guard var payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        payload.append(0x0A)
        let sent = payload.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard sent == payload.count else { return nil }

        var response = Data()
        var chunk = [UInt8](repeating: 0, count: 16_384)
        while !response.contains(0x0A) {
            let count = read(fd, &chunk, chunk.count)
            guard count > 0 else { break }
            response.append(contentsOf: chunk[0..<count])
        }
        return response.isEmpty ? nil : response
    }
}
