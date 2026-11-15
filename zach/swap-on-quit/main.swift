// swap-on-quit: installs staged fork builds into /Applications whenever their app is not running,
// so the next launch opens the new build. Two apps, each watched on its own:
//   iTerm2       ~/Documents/iTerm2-builds/staged/iTerm.app             -> /Applications/iTerm.app
//   Claude Dock  ~/Documents/iTerm2-builds/staged-claude-dock/Claude Dock.app -> /Applications/Claude Dock.app
// A staged build installs the moment its app quits, or at once when the app is not running.
// Each app is installed only by its own watcher; quitting one never touches the other.
//
//   swap-on-quit                          keep running (LaunchAgent com.zach.iterm2-fork-swap)
//   swap-on-quit --once [--app claude-dock]   wait for that app (default iTerm2) to quit, install once, exit
//   swap-on-quit --status                 show what is running, staged and installed, for both apps
//
// Staged builds and their BUILD_ID files are written by zach/update.sh (Claude Dock by
// zach/claude-dock/rebrand.sh). The replaced app is kept in previous/ (iTerm2) or
// previous-claude-dock/ (Claude Dock) for rollback.

import Darwin
import Foundation

let home = FileManager.default.homeDirectoryForCurrentUser.path
let builds = "\(home)/Documents/iTerm2-builds"
let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
let ping = "\(home)/.claude/skills/work-on/bin/ping-zach"

struct Target {
    let key: String            // --app value
    let name: String           // in logs and notifications
    let stagedApp: String
    let stagedID: String
    let installedID: String
    let previousDir: String
    let installedApp: String   // the app in /Applications
    let executableSuffix: String
}

let iTerm2 = Target(key: "iterm2",
                    name: "iTerm2",
                    stagedApp: "\(builds)/staged/iTerm.app",
                    stagedID: "\(builds)/staged/BUILD_ID",
                    installedID: "\(builds)/installed-BUILD_ID",
                    previousDir: "\(builds)/previous",
                    installedApp: "/Applications/iTerm.app",
                    executableSuffix: "/Applications/iTerm.app/Contents/MacOS/iTerm2")

let claudeDock = Target(key: "claude-dock",
                        name: "Claude Dock",
                        stagedApp: "\(builds)/staged-claude-dock/Claude Dock.app",
                        stagedID: "\(builds)/staged-claude-dock/BUILD_ID",
                        installedID: "\(builds)/installed-claude-dock-BUILD_ID",
                        previousDir: "\(builds)/previous-claude-dock",
                        installedApp: "/Applications/Claude Dock.app",
                        executableSuffix: "/Applications/Claude Dock.app/Contents/MacOS/ClaudeDock")

let targets = [iTerm2, claudeDock]

let logLock = NSLock()
func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    logLock.lock()
    FileHandle.standardError.write("\(stamp) \(message)\n".data(using: .utf8)!)
    logLock.unlock()
}

func read(_ path: String) -> String? {
    (try? String(contentsOfFile: path, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
}

// A staged build is pending when it exists and differs from what was last installed.
func pendingBuildID(_ t: Target) -> String? {
    guard FileManager.default.fileExists(atPath: "\(t.stagedApp)/Contents/Info.plist"),
          let id = read(t.stagedID), !id.isEmpty else {
        return nil
    }
    return id == read(t.installedID) ? nil : id
}

// PID of the target app running from /Applications, if any.
func runningPID(_ t: Target) -> pid_t? {
    let count = proc_listallpids(nil, 0)
    guard count > 0 else { return nil }
    var pids = [pid_t](repeating: 0, count: Int(count) * 2)
    let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
    var path = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
    for pid in pids.prefix(Int(max(filled, 0))) where pid > 0 {
        if proc_pidpath(pid, &path, UInt32(path.count)) > 0,
           String(cString: path).hasSuffix(t.executableSuffix) {
            return pid
        }
    }
    return nil
}

// Blocks until the process exits (returns at once if it already has).
func waitForExit(_ pid: pid_t) {
    let kq = kqueue()
    guard kq >= 0 else { return }
    defer { close(kq) }
    var change = kevent(ident: UInt(pid), filter: Int16(EVFILT_PROC), flags: UInt16(EV_ADD | EV_ONESHOT),
                        fflags: NOTE_EXIT, data: 0, udata: nil)
    var event = kevent()
    while true {
        let n = kevent(kq, &change, 1, &event, 1, nil)
        if n >= 0 || errno != EINTR { return }
    }
}

func notify(_ t: Target, _ message: String) {
    log("\(t.name): \(message)")
    guard FileManager.default.isExecutableFile(atPath: ping) else { return }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: ping)
    task.arguments = ["--mac", t.key == iTerm2.key ? "iTerm2 fork: \(message)" : "\(t.name): \(message)"]
    try? task.run()
    task.waitUntilExit()
}

func install(_ t: Target, _ id: String) throws {
    let fm = FileManager.default
    try fm.createDirectory(atPath: t.previousDir, withIntermediateDirectories: true)
    let previousApp = "\(t.previousDir)/\((t.installedApp as NSString).lastPathComponent)"
    if fm.fileExists(atPath: previousApp) {
        // Keep it if it can't be removed (e.g. the stock app, which macOS protects).
        do {
            try fm.removeItem(atPath: previousApp)
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let base = ((t.installedApp as NSString).lastPathComponent as NSString).deletingPathExtension
            try fm.moveItem(atPath: previousApp, toPath: "\(t.previousDir)/\(base)-\(stamp).app")
        }
    }
    if fm.fileExists(atPath: t.installedApp) {
        try fm.moveItem(atPath: t.installedApp, toPath: previousApp)
    }
    do {
        try fm.moveItem(atPath: t.stagedApp, toPath: t.installedApp)
    } catch {
        if !fm.fileExists(atPath: t.installedApp), fm.fileExists(atPath: previousApp) {
            try? fm.moveItem(atPath: previousApp, toPath: t.installedApp)
        }
        throw error
    }
    try id.write(toFile: t.installedID, atomically: true, encoding: .utf8)
    let register = Process()
    register.executableURL = URL(fileURLWithPath: lsregister)
    register.arguments = ["-f", t.installedApp]
    try? register.run()
    register.waitUntilExit()
    log("installed \(id) at \(t.installedApp)")
}

// Returns true when a build was installed.
func installIfPossible(_ t: Target) -> Bool {
    guard let id = pendingBuildID(t) else { return false }
    if let pid = runningPID(t) {
        log("\(t.name) build \(id) staged; waiting for \(t.name) (pid \(pid)) to quit")
        waitForExit(pid)
    }
    guard runningPID(t) == nil, let current = pendingBuildID(t) else { return false }
    do {
        try install(t, current)
        return true
    } catch {
        notify(t, "could not install build \(current): \(error.localizedDescription). Still on the previous build.")
        return false
    }
}

// The watcher for one app: unchanged from the single-app helper, one per thread so a wait on one
// app never delays the other.
func watch(_ t: Target) -> Never {
    var lastFailure: Date?
    while true {
        if let failed = lastFailure, Date().timeIntervalSince(failed) < 600 {
            // After a failed install, wait ten minutes before retrying.
        } else if pendingBuildID(t) != nil {
            lastFailure = installIfPossible(t) || pendingBuildID(t) == nil ? nil : Date()
        }
        Thread.sleep(forTimeInterval: 15)
    }
}

let arguments = CommandLine.arguments

if arguments.contains("--status") {
    for t in targets {
        print("\(t.name) running: \(runningPID(t).map { "pid \($0)" } ?? "no")")
        print("\(t.name) staged build: \(read(t.stagedID) ?? "none")")
        print("\(t.name) installed build: \(read(t.installedID) ?? (t.key == iTerm2.key ? "none (stock app)" : "none"))")
        print("\(t.name) pending install: \(pendingBuildID(t) ?? "none")")
    }
    exit(0)
}

func selectedTarget() -> Target {
    guard let i = arguments.firstIndex(of: "--app") else { return iTerm2 }
    guard i + 1 < arguments.count, let t = targets.first(where: { $0.key == arguments[i + 1] }) else {
        FileHandle.standardError.write("usage: swap-on-quit [--status | --once [--app iterm2|claude-dock]]\n".data(using: .utf8)!)
        exit(64)
    }
    return t
}

if arguments.contains("--once") {
    let t = selectedTarget()
    if pendingBuildID(t) == nil {
        log("no staged \(t.name) build to install")
        exit(0)
    }
    exit(installIfPossible(t) ? 0 : 1)
}

log("watching for staged builds: \(targets.map(\.name).joined(separator: ", "))")
for t in targets.dropFirst() {
    Thread.detachNewThread { watch(t) }
}
watch(targets[0])
