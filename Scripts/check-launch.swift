// Test machines only: temporarily replaces Board's preferences, then restores them.
// Run: swift Scripts/check-launch.swift --test-machine /path/to/test/Board.app
import AppKit
import CoreGraphics

struct CheckFailure: Error, CustomStringConvertible { let description: String }
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw CheckFailure(description:message) }
}
func waitUntil(_ check: () -> Bool) -> Bool {
    let deadline = Date()+8
    repeat {
        if check() { return true }
        RunLoop.current.run(until:Date()+0.1)
    } while Date() < deadline
    return check()
}
func checkLaunches() throws {
    try require(CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--test-machine",
                "usage: swift Scripts/check-launch.swift --test-machine /path/to/test/Board.app")
    let path = URL(fileURLWithPath:CommandLine.arguments[2]).resolvingSymlinksInPath()
    let identifier = "com.tommyent.Board"
    try require(path.path != "/Applications/Board.app" && Bundle(url:path)?.bundleIdentifier == identifier,
                "Supply a built test copy, outside /Applications/Board.app")
    try require(NSRunningApplication.runningApplications(withBundleIdentifier:identifier).isEmpty,
                "Quit Board on the test machine before running this check")
    let defaults = UserDefaults(suiteName:identifier)!
    let original = defaults.persistentDomain(forName:identifier)
    let originalFront = NSWorkspace.shared.frontmostApplication
    var running: NSRunningApplication?
    func stop() {
        guard let app = running else { return }
        app.terminate()
        if !waitUntil({app.isTerminated}) { app.forceTerminate(); _ = waitUntil { app.isTerminated } }
        running = nil
    }
    defer {
        stop()
        defaults.removePersistentDomain(forName:identifier)
        if let original { defaults.setPersistentDomain(original,forName:identifier) }
        defaults.synchronize()
        originalFront?.activate()
    }
    for (name, complete) in [("first-run",false),("onboarding-complete-permission-missing",true)] {
        let data = try JSONSerialization.data(withJSONObject:["onboardingComplete":complete,"muted":true])
        defaults.setPersistentDomain(["appSettings.v1":data],forName:identifier)
        defaults.synchronize()
        let frontBefore = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        let open = Process(); open.executableURL = URL(fileURLWithPath:"/usr/bin/open")
        open.arguments = ["-g",path.path]; try open.run(); open.waitUntilExit()
        try require(open.terminationStatus == 0,"open failed")
        try require(waitUntil {
            running = NSRunningApplication.runningApplications(withBundleIdentifier:identifier).first
            return running != nil
        },"Board did not launch")
        let app = running!
        try require(app.bundleURL?.resolvingSymlinksInPath() == path,"A different Board copy launched")
        func settingsWindows() -> [[String:Any]] {
            let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly,kCGNullWindowID) as? [[String:Any]] ?? []
            return windows.filter { window in
                guard window[kCGWindowOwnerPID as String] as? Int32 == app.processIdentifier,
                      window[kCGWindowLayer as String] as? Int == 0,
                      let bounds = window[kCGWindowBounds as String] as? [String:CGFloat] else { return false }
                // Window names can be redacted without Screen Recording; this is Settings' initial size.
                return window[kCGWindowName as String] as? String == "Board — Settings"
                    || (bounds["Width"] == 890 && bounds["Height"] == 740)
            }
        }
        let opened = waitUntil { !settingsWindows().isEmpty }
        let front = NSWorkspace.shared.frontmostApplication
        print("\(name): settingsOpened=\(opened) boardTookFront=\(front?.processIdentifier == app.processIdentifier) frontBefore=\(frontBefore) frontAfter=\(front?.bundleIdentifier ?? "unknown")")
        try require(opened,"Settings did not open for \(name)")
        stop()
    }
}
do { try checkLaunches() }
catch { fputs("\(error)\n",stderr); exit(1) }
