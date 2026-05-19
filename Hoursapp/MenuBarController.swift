import AppKit
import Darwin
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var ticker: Timer?
    private var controlClickMonitor: Any?

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

        if ProcessInfo.processInfo.environment["HOURSAPP_AUTO_OPEN_POPOVER"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                NSApp.activate(ignoringOtherApps: true)
                self?.togglePopover(nil)
            }
        }
    }

    deinit {
        ticker?.invalidate()
        if let controlClickMonitor {
            NSEvent.removeMonitor(controlClickMonitor)
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        installControlClickMonitor()
    }

    /// Intercepts Ctrl+left-click on the status-bar button before AppKit
    /// dispatches it. We can't detect this from the button's regular action
    /// — `NSStatusBarButton` doesn't fire the action when Control is held —
    /// so we look at the event itself and route it to the context menu.
    ///
    /// The menu is shown synchronously from the monitor closure (which AppKit
    /// already delivers on the main thread). Hopping through a Task here
    /// introduced a deferred continuation that prevented `NSApp.terminate`
    /// from completing when the user picked "Quit" — staying synchronous
    /// matches the right-click path exactly.
    private func installControlClickMonitor() {
        controlClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            guard event.window === self.statusItem.button?.window else { return event }
            // Match only plain Ctrl (no Cmd/Opt/Shift) so we don't interfere
            // with Cmd-drag rearrangement of menu-bar items.
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods == .control else { return event }
            MainActor.assumeIsolated { self.showQuickAddMenu() }
            return nil
        }
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
        let timeText = TimeFormat.hoursMinutes(total)

        button.wantsLayer = true
        button.layer?.backgroundColor = nil
        button.layer?.cornerRadius = 0

        if isRunning {
            button.image = Self.makeRunningPill(at: .now, time: timeText)
            button.imagePosition = .imageOnly
            button.title = ""
        } else {
            button.image = Self.makeClockIcon(at: .now)
            button.imagePosition = .imageLeading
            button.title = " " + timeText
        }
    }

    private static func makeClockIcon(at date: Date) -> NSImage {
        let width: CGFloat = 15
        let height: CGFloat = 22
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            drawClock(at: center, radius: 6.5, lineWidth: 1.0, handStyle: .stopped, date: date, color: .black)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func makeRunningPill(at date: Date, time: String) -> NSImage {
        let font = NSFont.menuBarFont(ofSize: 0)
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let timeNS = time as NSString
        let textSize = timeNS.size(withAttributes: textAttrs)

        let pillHeight: CGFloat = 20
        let canvasHeight: CGFloat = 22
        let iconRadius: CGFloat = 6.5
        let leftInset: CGFloat = 4
        let iconCenterX = leftInset + iconRadius
        let iconRight = iconCenterX + iconRadius
        let iconToTextGap: CGFloat = 6
        let textRightPadding: CGFloat = 8
        let textX = iconRight + iconToTextGap
        let pillWidth = ceil(textX + textSize.width + textRightPadding)

        let image = NSImage(size: NSSize(width: pillWidth, height: canvasHeight), flipped: false) { rect in
            let pillRect = NSRect(
                x: 0,
                y: (rect.height - pillHeight) / 2,
                width: rect.width,
                height: pillHeight
            )
            let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: pillHeight / 2, yRadius: pillHeight / 2)
            NSColor.white.setFill()
            pillPath.fill()

            let center = NSPoint(x: iconCenterX, y: rect.midY)
            drawClock(at: center, radius: iconRadius, lineWidth: 1.0, handStyle: .running, date: date, color: .black)

            let textOrigin = NSPoint(
                x: textX,
                y: (rect.height - textSize.height) / 2
            )
            timeNS.draw(at: textOrigin, withAttributes: textAttrs)
            return true
        }
        image.isTemplate = false
        return image
    }

    private enum HandStyle { case stopped, running }

    private static func drawClock(
        at center: NSPoint,
        radius: CGFloat,
        lineWidth: CGFloat,
        handStyle: HandStyle,
        date: Date,
        color: NSColor
    ) {
        color.setStroke()
        let circle = NSBezierPath(ovalIn: NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        circle.lineWidth = lineWidth
        circle.stroke()

        let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let realSeconds = Double(comps.second ?? 0)
        let realMinutes = Double(comps.minute ?? 0)
        let realHours = Double((comps.hour ?? 0) % 12)

        let clockMinutes: Double
        let clockHours: Double
        switch handStyle {
        case .running:
            clockMinutes = realSeconds
            clockHours = (realMinutes + realSeconds / 60).truncatingRemainder(dividingBy: 12)
        case .stopped:
            clockMinutes = realMinutes + realSeconds / 60
            clockHours = realHours + realMinutes / 60
        }

        let hourLength = radius * 0.55
        let minuteLength = radius * 0.82
        let hourWidth = max(1.0, lineWidth * 1.6)
        let minuteWidth = lineWidth

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

        drawHand(clockAngle: clockHours * (.pi * 2 / 12), length: hourLength, lineWidth: hourWidth)
        drawHand(clockAngle: clockMinutes * (.pi * 2 / 60), length: minuteLength, lineWidth: minuteWidth)
    }

    @objc private func handleClick(_ sender: Any?) {
        // Ctrl+click is handled earlier by the local event monitor and never
        // reaches the button's action — see installControlClickMonitor().
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

        menu.addItem(.separator())
        if let action = storage.lastUndoableAction {
            let undo = NSMenuItem(title: "Undo \(action.userFacingName)",
                                  action: #selector(performUndo),
                                  keyEquivalent: "z")
            undo.target = self
            menu.addItem(undo)
        }

        let export = NSMenuItem(title: "Export to Excel…", action: #selector(exportToExcel), keyEquivalent: "e")
        export.target = self
        menu.addItem(export)

        let quit = NSMenuItem(title: "Quit Hoursapp", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 5), in: button)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
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

    @objc private func exportToExcel() {
        ExportDialog.present()
    }

    @objc private func performUndo() {
        Storage.shared.undoLastAction()
    }
}
