import AppKit
import Darwin
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var ticker: Timer?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popover = NSPopover()
        popover.contentSize = NSSize(width: 480, height: 640)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ContentView())

        super.init()

        popover.delegate = self
        configureStatusItem()
        startTicker()
        refreshTitle()
    }

    deinit {
        ticker?.invalidate()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshTitle()
            }
        }
    }

    private func refreshTitle() {
        guard let button = statusItem.button else { return }
        let storage = Storage.shared
        let total = storage.todayTotalSeconds()
        let isRunning = storage.runningEntry() != nil
        button.image = Self.makeClockIcon(at: .now, running: isRunning)
        button.title = " " + TimeFormat.hoursMinutes(total)
    }

    private static func makeClockIcon(at date: Date, running: Bool) -> NSImage {
        let size: CGFloat = 22
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            if running {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            }

            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 6.5
            let foreground: NSColor = running ? .white : .black

            foreground.setStroke()
            let circle = NSBezierPath(ovalIn: NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            circle.lineWidth = 1.0
            circle.stroke()

            let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
            let realSeconds = Double(comps.second ?? 0)
            let realMinutes = Double(comps.minute ?? 0)
            let realHours = Double((comps.hour ?? 0) % 12)

            let clockMinutes: Double
            let clockHours: Double
            if running {
                clockMinutes = realSeconds
                clockHours = (realMinutes + realSeconds / 60).truncatingRemainder(dividingBy: 12)
            } else {
                clockMinutes = realMinutes + realSeconds / 60
                clockHours = realHours + realMinutes / 60
            }

            func drawHand(clockAngle: Double, length: CGFloat, lineWidth: CGFloat) {
                let radians = .pi / 2 - clockAngle
                let end = NSPoint(
                    x: center.x + Darwin.cos(radians) * length,
                    y: center.y + Darwin.sin(radians) * length
                )
                let path = NSBezierPath()
                path.move(to: center)
                path.line(to: end)
                path.lineWidth = lineWidth
                path.lineCapStyle = .round
                path.stroke()
            }

            drawHand(clockAngle: clockHours * (.pi * 2 / 12), length: 3.5, lineWidth: 1.6)
            drawHand(clockAngle: clockMinutes * (.pi * 2 / 60), length: 5.2, lineWidth: 1.0)

            return true
        }
        image.isTemplate = !running
        return image
    }

    @objc private func handleClick(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showQuickAddMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showQuickAddMenu() {
        let menu = NSMenu()

        let storage = Storage.shared
        let today = DateFormat.day(from: .now)

        let recent = storage.entries
            .filter { $0.date == today }
            .reduce(into: [Favorite]()) { acc, entry in
                let f = Favorite(client: entry.client, project: entry.project, task: entry.task)
                if !acc.contains(f) { acc.append(f) }
            }

        if !recent.isEmpty {
            menu.addItem(NSMenuItem.sectionHeader(title: "Today"))
            for fav in recent {
                menu.addItem(makeQuickAddItem(for: fav))
            }
        }

        let favorites = storage.favorites
        if !favorites.isEmpty {
            if !recent.isEmpty { menu.addItem(.separator()) }
            menu.addItem(NSMenuItem.sectionHeader(title: "Favorites"))
            for fav in favorites {
                menu.addItem(makeQuickAddItem(for: fav))
            }
        }

        if storage.runningEntry() != nil {
            menu.addItem(.separator())
            let stop = NSMenuItem(title: "Stop timer", action: #selector(stopRunningTimer), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
        }

        if menu.items.isEmpty {
            menu.addItem(NSMenuItem(title: "No favorites yet — add one in the entry sheet", action: nil, keyEquivalent: ""))
        }

        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 5), in: button)
        }
    }

    private func makeQuickAddItem(for fav: Favorite) -> NSMenuItem {
        let item = NSMenuItem(
            title: "\(fav.client) — \(fav.project) — \(fav.task)",
            action: #selector(quickAddSelected(_:)),
            keyEquivalent: ""
        )
        item.representedObject = fav
        item.target = self
        return item
    }

    @objc private func quickAddSelected(_ sender: NSMenuItem) {
        guard let fav = sender.representedObject as? Favorite else { return }
        let today = DateFormat.day(from: .now)
        Storage.shared.startTimer(client: fav.client, project: fav.project, task: fav.task, on: today)
    }

    @objc private func stopRunningTimer() {
        Storage.shared.stopTimer()
    }
}
