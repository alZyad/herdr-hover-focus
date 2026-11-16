import AppKit

signal(SIGPIPE, SIG_IGN)

let follower = Follower(verbose: CommandLine.arguments.contains("--verbose"))
var tap: CFMachPort?

if !CGPreflightListenEventAccess() {
    CGRequestListenEventAccess()
}

tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: CGEventMask(1 << CGEventType.mouseMoved.rawValue),
    callback: { _, type, event, _ in
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .mouseMoved:
            follower.mouseMoved(to: event.location)
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    },
    userInfo: nil
)

guard let tap else {
    FileHandle.standardError.write(Data("[herdr-hover-focus] Input Monitoring permission missing\n".utf8))
    exit(1)
}

CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
