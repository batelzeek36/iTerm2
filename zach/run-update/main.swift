// run-update: what the LaunchAgent com.zach.iterm2-fork-update runs (04:00, and at load:
// login, install.sh).
//
// Why this exists: ~/Documents is privacy-protected (TCC). A launchd job that starts /bin/zsh
// directly gets no Documents grant and cannot ask for one, so update.sh never started
// (11-11 and 11-12 04:00: "can't open input file: .../update.sh", exit 127). This binary is
// signed with Zach's Developer ID under its own identifier, macOS grants it Documents access
// once, and the update.sh it starts inherits that grant (same responsible process).
//
// Quiet hours (Zach, 2026-11-15): the run goes ahead during quiet hours too ("i dont think an iterm2
// nightly build is going to ram spotify to the point of affecting playback"). It runs at background
// QoS (efficiency cores), Nice 10, low-priority I/O; quiet hours keep its LaunchAgent and leave its
// processes alone (~/Documents/quiet-hours, config.NIGHT_EXEMPT_WORK). It is the only build allowed then.
//
//   run-update [args]     run update.sh [args] and exit with its status
//   run-update --probe    check Documents access and exit (0 = update.sh is readable)
//   run-update --dry-run  say what a run would do (quiet hours, Documents access, the command); start nothing

import Darwin
import Foundation

let home = FileManager.default.homeDirectoryForCurrentUser.path
let script = "\(home)/Documents/iTerm2-builds/bin/update.sh"
// QUIET_HOURS_STATE_DIR: the quiet-hours tests' folder (never set by launchd).
let quietDir = ProcessInfo.processInfo.environment["QUIET_HOURS_STATE_DIR"] ?? "\(home)/.claude/quiet-hours"
let quietFlag = "\(quietDir)/active"
let zsh = "/bin/zsh"

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write("\(stamp) run-update: \(message)\n".data(using: .utf8)!)
}

// Quiet hours are on (only logged: the build runs anyway). A flag whose text starts with "test" is
// the sound-reset test, not a night.
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

if args.first == "--dry-run" {
    let probe = documentsReadable()
    print("quiet hours: \(quietHoursOn() ? "on (the build runs anyway, Zach 2026-11-15)" : "off")")
    print("Documents access: \(probe.ok ? "yes" : "no") (\(probe.detail)): \(script)")
    print("would run: \(zsh) \(script)")
    exit(probe.ok ? 0 : 1)
}

if quietHoursOn() {
    log("quiet hours are on; building anyway (Zach 2026-11-15), at background priority")
}

let probe = documentsReadable()
guard probe.ok else {
    log("cannot read \(script): \(probe.detail). Grant \"run-update\" access to the Documents folder (System Settings > Privacy & Security > Files and Folders, or Full Disk Access).")
    exit(77)
}

// Forward launchd's stop (SIGTERM, e.g. `launchctl bootout`) to update.sh.
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
