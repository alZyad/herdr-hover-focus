import AppKit

signal(SIGPIPE, SIG_IGN)

let follower = Follower(verbose: CommandLine.arguments.contains("--verbose"))

let monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { event in
    guard let location = event.cgEvent?.location else { return }
    follower.mouseMoved(to: location)
}

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
