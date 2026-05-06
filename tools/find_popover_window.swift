// Prints the CGWindow ID of Hoursapp's open popover so screencapture can grab it.
// Usage: swift tools/find_popover_window.swift <pid>
// Picks the largest on-screen window owned by <pid>, since the popover is much
// bigger than the menu-bar status item window.

import Cocoa

guard CommandLine.arguments.count == 2, let pid = Int(CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: find_popover_window.swift <pid>\n".utf8))
    exit(2)
}

let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

struct Candidate { let id: Int; let w: CGFloat; let h: CGFloat; let layer: Int; let alpha: Double }

let candidates: [Candidate] = info.compactMap { dict in
    guard
        let owner = dict["kCGWindowOwnerPID"] as? Int, owner == pid,
        let id = dict["kCGWindowNumber"] as? Int,
        let bounds = dict["kCGWindowBounds"] as? [String: CGFloat]
    else { return nil }
    let layer = dict["kCGWindowLayer"] as? Int ?? 0
    let alpha = dict["kCGWindowAlpha"] as? Double ?? 0
    return Candidate(id: id, w: bounds["Width"] ?? 0, h: bounds["Height"] ?? 0, layer: layer, alpha: alpha)
}

if ProcessInfo.processInfo.environment["DEBUG"] == "1" {
    for c in candidates {
        FileHandle.standardError.write(Data("id=\(c.id) w=\(c.w) h=\(c.h) layer=\(c.layer) alpha=\(c.alpha)\n".utf8))
    }
}

let visible = candidates.filter { $0.alpha > 0 && $0.w * $0.h > 100_000 }
guard let pick = visible.max(by: { $0.w * $0.h < $1.w * $1.h }) else {
    FileHandle.standardError.write(Data("no popover-sized window found for pid \(pid)\n".utf8))
    exit(1)
}

print(pick.id)
