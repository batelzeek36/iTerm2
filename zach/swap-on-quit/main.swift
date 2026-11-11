// swap-on-quit: installs the staged iTerm2 fork build into /Applications whenever iTerm2 is
// not running, so the next launch opens the new build.
//
//   swap-on-quit           keep running (LaunchAgent com.zach.iterm2-fork-swap)
//   swap-on-quit --once    wait for iTerm2 to quit, install once, exit
//   swap-on-quit --status  show what is running, staged and installed
//
// Staged build: ~/Documents/iTerm2-builds/staged/iTerm.app (+ BUILD_ID), written by zach/update.sh.
// The replaced app is kept in ~/Documents/iTerm2-builds/previous/ for rollback.

import Darwin
import Foundation

let home = FileManager.default.homeDirectoryForCurrentUser.path
let builds = "\(home)/Documents/iTerm2-builds"
let stagedApp = "\(builds)/staged/iTerm.app"
let stagedID = "\(builds)/staged/BUILD_ID"
let installedID = "\(builds)/installed-BUILD_ID"
let previousDir = "\(builds)/previous"
let target = "/Applications/iTerm.app"
let executableSuffix = "/Applications/iTerm.app/Contents/MacOS/iTerm2"
let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
let ping = "\(home)/.claude/skills/work-on/bin/ping-zach"

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write("\(stamp) \(message)\n".data(using: .utf8)!)
}

func read(_ path: String) -> String? {
    (try? String(contentsOfFile: path, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
}

// A staged build is pending when it exists and differs from what was last installed.
func pendingBuildID() -> String? {
    guard FileManager.default.fileExists(atPath: "\(stagedApp)/Contents/Info.plist"),
          let id = read(stagedID), !id.isEmpty else {
        return nil
    }
    return id == read(installedID) ? nil : id
}

// PID of the iTerm2 app running from /Applications, if any.
func runningITermPID() -> pid_t? {
    let count = proc_listallpids(nil, 0)
    guard count > 0 else { return nil }
    var pids = [pid_t](repeating: 0, count: Int(count) * 2)
    let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
    var path = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
    for pid in pids.prefix(Int(max(filled, 0))) where pid > 0 {
        if proc_pidpath(pid, &path, UInt32(path.count)) > 0,
           String(cString: path).hasSuffix(executableSuffix) {
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

func notify(_ message: String) {
    log(message)
    guard FileManager.default.isExecutableFile(atPath: ping) else { return }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: ping)
    task.arguments = ["--mac", "iTerm2 fork: \(message)"]
    try? task.run()
    task.waitUntilExit()
}

func install(_ id: String) throws {
    let fm = FileManager.default
    try fm.createDirectory(atPath: previousDir, withIntermediateDirectories: true)
    let previousApp = "\(previousDir)/iTerm.app"
    if fm.fileExists(atPath: previousApp) {
        // Keep it if it can't be removed (e.g. the stock app, which macOS protects).
        do {
            try fm.removeItem(atPath: previousApp)
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            try fm.moveItem(atPath: previousApp, toPath: "\(previousDir)/iTerm-\(stamp).app")
        }
    }
    if fm.fileExists(atPath: target) {
        try fm.moveItem(atPath: target, toPath: previousApp)
    }
    do {
        try fm.moveItem(atPath: stagedApp, toPath: target)
    } catch {
        if !fm.fileExists(atPath: target), fm.fileExists(atPath: previousApp) {
            try? fm.moveItem(atPath: previousApp, toPath: target)
        }
        throw error
    }
    try id.write(toFile: installedID, atomically: true, encoding: .utf8)
    let register = Process()
    register.executableURL = URL(fileURLWithPath: lsregister)
    register.arguments = ["-f", target]
    try? register.run()
    register.waitUntilExit()
    log("installed \(id) at \(target)")
}

// Returns true when a build was installed.
func installIfPossible() -> Bool {
    guard let id = pendingBuildID() else { return false }
    if let pid = runningITermPID() {
        log("build \(id) staged; waiting for iTerm2 (pid \(pid)) to quit")
        waitForExit(pid)
    }
    guard runningITermPID() == nil, let current = pendingBuildID() else { return false }
    do {
        try install(current)
        return true
    } catch {
        notify("could not install build \(current): \(error.localizedDescription). Still on the previous build.")
        return false
    }
}

if CommandLine.arguments.contains("--status") {
    print("iTerm2 running: \(runningITermPID().map { "pid \($0)" } ?? "no")")
    print("staged build: \(read(stagedID) ?? "none")")
    print("installed build: \(read(installedID) ?? "none (stock app)")")
    print("pending install: \(pendingBuildID() ?? "none")")
    exit(0)
}

let once = CommandLine.arguments.contains("--once")
if once {
    if pendingBuildID() == nil {
        log("no staged build to install")
        exit(0)
    }
    exit(installIfPossible() ? 0 : 1)
}

log("watching for staged builds")
var lastFailure: Date?
while true {
    if let failed = lastFailure, Date().timeIntervalSince(failed) < 600 {
        // After a failed install, wait ten minutes before retrying.
    } else if pendingBuildID() != nil {
        lastFailure = installIfPossible() || pendingBuildID() == nil ? nil : Date()
    }
    Thread.sleep(forTimeInterval: 15)
}
