// run-update: what the LaunchAgent com.zach.iterm2-fork-update runs (04:00, and at load:
// login, install.sh, and quiet hours' `wake`, which catches up a night the 04:00 run was paused).
//
// Why this exists: ~/Documents is privacy-protected (TCC). A launchd job that starts /bin/zsh
// directly gets no Documents grant and cannot ask for one, so update.sh never started
// (11-11 and 11-12 04:00: "can't open input file: .../update.sh", exit 127). This binary is
// signed with Zach's Developer ID under its own identifier, macOS grants it Documents access
// once, and the update.sh it starts inherits that grant (same responsible process).
//
//   run-update [args]   skip while quiet hours are on, else run update.sh [args] and exit with its status
//   run-update --probe  check Documents access and exit (0 = update.sh is readable)

import Darwin
import Foundation

let home = FileManager.default.homeDirectoryForCurrentUser.path
let script = "\(home)/Documents/iTerm2-builds/bin/update.sh"
let quietFlag = "\(home)/.claude/quiet-hours/active"
let zsh = "/bin/zsh"

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write("\(stamp) run-update: \(message)\n".data(using: .utf8)!)
}

// Quiet hours: no builds on the Mac. A flag whose text starts with "test" is the sound-reset
// test, not a night.
func quietHoursOn() -> Bool {
    guard FileManager.default.fileExists(atPath: quietFlag) else { return false }
    let text = (try? String(contentsOfFile: quietFlag, encoding: .utf8)) ?? ""
    return !text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("test")
}

// A real read, not access(2): the privacy check happens on open, and access(2) can say yes
// while the open is refused.
func documentsReadable() -> (ok: Bool, detail: String) {
    let fd = open(script, O_RDONLY)
    guard fd >= 0 else { return (false, String(cString: strerror(errno))) }
    defer { close(fd) }
    var byte: UInt8 = 0
    let n = read(fd, &byte, 1)
    return n >= 0 ? (true, "readable") : (false, String(cString: strerror(errno)))
}

let args = Array(CommandLine.arguments.dropFirst())

if args.first == "--probe" {
    let probe = documentsReadable()
    print("Documents access: \(probe.ok ? "yes" : "no") (\(probe.detail)): \(script)")
    exit(probe.ok ? 0 : 1)
}

if quietHoursOn() {
    log("quiet hours are on; no build tonight (wake loads this job again and it catches up)")
    exit(0)
}

let probe = documentsReadable()
guard probe.ok else {
    log("cannot read \(script): \(probe.detail). Grant \"run-update\" access to the Documents folder (System Settings > Privacy & Security > Files and Folders, or Full Disk Access).")
    exit(77)
}

// Forward launchd's stop (SIGTERM, e.g. quiet hours booting the job out) to update.sh.
var child: pid_t = 0
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
var sources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT] {
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
    source.setEventHandler {
        if child > 0 { kill(child, sig) }
    }
    source.resume()
    sources.append(source)
}

let argv: [UnsafeMutablePointer<CChar>?] = ([zsh, script] + args).map { strdup($0) } + [nil]
defer { argv.forEach { free($0) } }
let spawned = posix_spawn(&child, zsh, nil, nil, argv, environ)
guard spawned == 0 else {
    log("could not start \(zsh) \(script): \(String(cString: strerror(spawned)))")
    exit(71)
}

var status: Int32 = 0
while waitpid(child, &status, 0) < 0 {
    if errno != EINTR {
        log("waitpid failed: \(String(cString: strerror(errno)))")
        exit(71)
    }
}
// WIFEXITED / WEXITSTATUS / WTERMSIG, which Swift does not import.
let termSignal = status & 0x7f
exit(termSignal == 0 ? (status >> 8) & 0xff : 128 + termSignal)
