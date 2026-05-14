import Testing
import Foundation
@testable import Hoursapp

/// On-demand generator for `docs/sample-export.xlsx`. Gated on a trigger file
/// at `<repo>/.sample-export-trigger` (which `tools/generate_sample_export.sh`
/// creates around its invocation) — xcodebuild test doesn't forward shell env
/// vars to the test host, so a filesystem signal is the simplest reliable
/// cross-process gate.
@Suite("Sample export generator")
struct SampleExportGenerator {
    @Test(
        "Writes a deterministic monthly sample workbook",
        .enabled(if: SampleExportGenerator.triggerPath().map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
    )
    func generate() throws {
        guard let triggerURL = Self.triggerPath() else {
            Issue.record("Could not resolve repo root from #filePath")
            return
        }
        let repoRoot = triggerURL.deletingLastPathComponent()
        let outURL = repoRoot.appending(path: "docs/sample-export.xlsx")

        try FileManager.default.createDirectory(
            at: outURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let entries = SampleDataset.april2026()
        try ExcelExporter.export(
            entries: entries,
            period: .month(year: 2026, month: 4),
            to: outURL
        )

        // Verify the file landed; the workbook tests cover the byte-level format.
        #expect(FileManager.default.fileExists(atPath: outURL.path))
    }

    /// Resolves `<repo-root>/.sample-export-trigger` from this source file's
    /// path. The HoursappTests directory sits one level below the repo root.
    static func triggerPath(file: StaticString = #filePath) -> URL? {
        let thisFile = URL(fileURLWithPath: "\(file)")
        let repoRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent()
        return repoRoot.appending(path: ".sample-export-trigger")
    }
}

// MARK: - Sample dataset

/// Hand-tuned, deterministic dataset for the committed example workbook.
/// Output bytes change only when this generator changes, so the repo diff is
/// meaningful when someone updates the sample.
private enum SampleDataset {
    /// April 2026 — 22 weekdays plus one Saturday push, roughly 150 hours total
    /// spread across three clients with varied project/task mixes and notes.
    static func april2026() -> [Entry] {
        var rng = SplitMix64(seed: 0xA9E1_F420_2604_2026)
        var entries: [Entry] = []
        var idCounter = 0
        func nextId() -> String {
            idCounter += 1
            return String(format: "sample-%04d", idCounter)
        }

        for day in workingDays(year: 2026, month: 4) {
            let dayString = String(format: "2026-04-%02d", day.day)
            let plans = plan(for: day, rng: &rng)
            for slice in plans {
                let stoppedAtUTC = String(
                    format: "2026-04-%02dT%02d:%02d:00Z",
                    day.day, slice.endHour, slice.endMinute
                )
                let startedAtUTC = String(
                    format: "2026-04-%02dT%02d:%02d:00Z",
                    day.day, slice.startHour, slice.startMinute
                )
                entries.append(Entry(
                    id: nextId(),
                    date: dayString,
                    client: slice.client,
                    project: slice.project,
                    task: slice.task,
                    seconds: slice.seconds,
                    notes: slice.notes,
                    startedAt: startedAtUTC,
                    stoppedAt: stoppedAtUTC
                ))
            }
        }
        return entries
    }

    // MARK: - Day plan

    private struct Slice {
        let client: String
        let project: String
        let task: String
        let seconds: Int
        let notes: String
        let startHour: Int
        let startMinute: Int
        let endHour: Int
        let endMinute: Int
    }

    private struct DayInfo {
        let day: Int
        let weekday: Int   // 1=Mon .. 7=Sun
    }

    /// Mon–Fri across April 2026 plus a single Saturday cameo (Apr 18) so the
    /// weekday-of-week and calendar heatmap have something off-grid to render.
    private static func workingDays(year: Int, month: Int) -> [DayInfo] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let first = cal.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = cal.range(of: .day, in: .month, for: first)
        else { return [] }

        var out: [DayInfo] = []
        for day in range {
            let date = cal.date(from: DateComponents(year: year, month: month, day: day))!
            // weekday: 1=Sun..7=Sat
            let raw = cal.component(.weekday, from: date)
            // shift so Mon=1..Sun=7
            let weekday = ((raw + 5) % 7) + 1
            let isWeekday = weekday <= 5
            let isSaturdayCameo = (day == 18 && weekday == 6)
            if isWeekday || isSaturdayCameo {
                out.append(DayInfo(day: day, weekday: weekday))
            }
        }
        return out
    }

    /// Per-day plan: pick a "shape" for the day (deep-work, meetings-heavy,
    /// mixed, light) and emit 1–4 entries from a curated palette.
    private static func plan(for day: DayInfo, rng: inout SplitMix64) -> [Slice] {
        // Saturday cameo is intentionally short.
        if day.weekday == 6 {
            return [
                makeSlice(
                    rng: &rng,
                    catalog: catalog[0],
                    project: "Brand Refresh",
                    task: "Polish",
                    startHour: 10, startMinute: 15,
                    durationMinutes: 75,
                    notes: "Weekend pass before Monday review."
                )
            ]
        }

        // Mondays are slightly meetings-heavy; Fridays slightly lighter.
        let shape: DayShape
        switch day.weekday {
        case 1: shape = .meetingsHeavy
        case 5: shape = .light
        default: shape = pick(rng: &rng, from: [.mixed, .mixed, .deepWork, .meetingsHeavy])
        }

        switch shape {
        case .deepWork:
            return deepWorkDay(rng: &rng)
        case .meetingsHeavy:
            return meetingsHeavyDay(rng: &rng)
        case .mixed:
            return mixedDay(rng: &rng)
        case .light:
            return lightDay(rng: &rng)
        }
    }

    private enum DayShape { case deepWork, meetingsHeavy, mixed, light }

    private static func deepWorkDay(rng: inout SplitMix64) -> [Slice] {
        let primary = pick(rng: &rng, from: catalog)
        let secondary = pick(rng: &rng, from: catalog.filter { $0.client != primary.client })
        return [
            makeSlice(
                rng: &rng, catalog: primary,
                project: pick(rng: &rng, from: primary.projects),
                task: pick(rng: &rng, from: primary.tasks),
                startHour: 9, startMinute: 5,
                durationMinutes: 175,
                notes: pick(rng: &rng, from: focusNotes)
            ),
            makeSlice(
                rng: &rng, catalog: primary,
                project: pick(rng: &rng, from: primary.projects),
                task: pick(rng: &rng, from: primary.tasks),
                startHour: 13, startMinute: 0,
                durationMinutes: 160,
                notes: pick(rng: &rng, from: focusNotes)
            ),
            makeSlice(
                rng: &rng, catalog: secondary,
                project: pick(rng: &rng, from: secondary.projects),
                task: pick(rng: &rng, from: secondary.tasks),
                startHour: 16, startMinute: 0,
                durationMinutes: 55,
                notes: pick(rng: &rng, from: shortNotes)
            ),
        ]
    }

    private static func meetingsHeavyDay(rng: inout SplitMix64) -> [Slice] {
        let primary = pick(rng: &rng, from: catalog)
        let secondary = pick(rng: &rng, from: catalog.filter { $0.client != primary.client })
        let tertiary = pick(rng: &rng, from: catalog.filter { $0.client != primary.client && $0.client != secondary.client })
        return [
            makeSlice(
                rng: &rng, catalog: primary,
                project: pick(rng: &rng, from: primary.projects),
                task: "Calls",
                startHour: 9, startMinute: 30,
                durationMinutes: 50,
                notes: "Sprint standup + stakeholder Q&A."
            ),
            makeSlice(
                rng: &rng, catalog: secondary,
                project: pick(rng: &rng, from: secondary.projects),
                task: "Planning",
                startHour: 11, startMinute: 0,
                durationMinutes: 80,
                notes: "Quarterly roadmap walkthrough."
            ),
            makeSlice(
                rng: &rng, catalog: tertiary,
                project: pick(rng: &rng, from: tertiary.projects),
                task: pick(rng: &rng, from: tertiary.tasks),
                startHour: 13, startMinute: 30,
                durationMinutes: 100,
                notes: pick(rng: &rng, from: focusNotes)
            ),
            makeSlice(
                rng: &rng, catalog: primary,
                project: pick(rng: &rng, from: primary.projects),
                task: "Coordination",
                startHour: 15, startMinute: 30,
                durationMinutes: 70,
                notes: "Async follow-ups, ticket triage."
            ),
        ]
    }

    private static func mixedDay(rng: inout SplitMix64) -> [Slice] {
        let primary = pick(rng: &rng, from: catalog)
        let secondary = pick(rng: &rng, from: catalog.filter { $0.client != primary.client })
        return [
            makeSlice(
                rng: &rng, catalog: primary,
                project: pick(rng: &rng, from: primary.projects),
                task: pick(rng: &rng, from: primary.tasks),
                startHour: 9, startMinute: 15,
                durationMinutes: 120,
                notes: pick(rng: &rng, from: focusNotes)
            ),
            makeSlice(
                rng: &rng, catalog: primary,
                project: pick(rng: &rng, from: primary.projects),
                task: "Reviews",
                startHour: 11, startMinute: 30,
                durationMinutes: 45,
                notes: pick(rng: &rng, from: shortNotes)
            ),
            makeSlice(
                rng: &rng, catalog: secondary,
                project: pick(rng: &rng, from: secondary.projects),
                task: pick(rng: &rng, from: secondary.tasks),
                startHour: 13, startMinute: 15,
                durationMinutes: 145,
                notes: pick(rng: &rng, from: focusNotes)
            ),
            makeSlice(
                rng: &rng, catalog: primary,
                project: pick(rng: &rng, from: primary.projects),
                task: "Coordination",
                startHour: 16, startMinute: 0,
                durationMinutes: 35,
                notes: "Wrap-up notes for tomorrow."
            ),
        ]
    }

    private static func lightDay(rng: inout SplitMix64) -> [Slice] {
        let primary = pick(rng: &rng, from: catalog)
        return [
            makeSlice(
                rng: &rng, catalog: primary,
                project: pick(rng: &rng, from: primary.projects),
                task: pick(rng: &rng, from: primary.tasks),
                startHour: 10, startMinute: 0,
                durationMinutes: 95,
                notes: pick(rng: &rng, from: shortNotes)
            ),
            makeSlice(
                rng: &rng, catalog: primary,
                project: pick(rng: &rng, from: primary.projects),
                task: "Reviews",
                startHour: 13, startMinute: 0,
                durationMinutes: 75,
                notes: "Sign-off pass before week-end."
            ),
        ]
    }

    private static func makeSlice(
        rng: inout SplitMix64,
        catalog: ClientCatalog,
        project: String,
        task: String,
        startHour: Int,
        startMinute: Int,
        durationMinutes: Int,
        notes: String
    ) -> Slice {
        // Small ±5 minute jitter so durations don't look uniformly synthetic.
        let jitter = Int(rng.next() % 11) - 5
        let total = max(15, durationMinutes + jitter)
        let endTotal = startHour * 60 + startMinute + total
        let endHour = endTotal / 60
        let endMinute = endTotal % 60
        return Slice(
            client: catalog.client,
            project: project,
            task: task,
            seconds: total * 60,
            notes: notes,
            startHour: startHour, startMinute: startMinute,
            endHour: endHour, endMinute: endMinute
        )
    }

    // MARK: - Catalog & notes

    private struct ClientCatalog {
        let client: String
        let projects: [String]
        let tasks: [String]
    }

    private static let catalog: [ClientCatalog] = [
        ClientCatalog(
            client: "Clerkenwell Studio",
            projects: ["Brand Refresh", "Wayfinding"],
            tasks: ["Mockups", "Calls", "Reviews", "Polish"]
        ),
        ClientCatalog(
            client: "Bermondsey & Co",
            projects: ["Annual Review", "Investor Deck"],
            tasks: ["Planning", "Writing", "Reviews", "Coordination"]
        ),
        ClientCatalog(
            client: "Hampstead Media",
            projects: ["iOS Rebuild", "Holiday Campaign"],
            tasks: ["Mockups", "Coordination", "Reviews", "Calls"]
        ),
    ]

    private static let focusNotes: [String] = [
        "Refactor the timer view; pulled the duration into its own subview.",
        "Story-boarded the onboarding flow end-to-end.",
        "Knocked out the spec edits flagged in Monday's review.",
        "Pair-debug session on the export pipeline.",
        "Wrote the integration tests for the rename flow.",
        "Cleaned up the heatmap palette; switched to luminance-based text color.",
        "Iterated on the dashboard hero block — tighter stat grouping.",
        "Polished the empty state copy and illustrations.",
    ]

    private static let shortNotes: [String] = [
        "Inbox + comments.",
        "Quick fix for the weekend regression.",
        "Status sync.",
        "Notes to self for tomorrow.",
        "",
    ]

    // MARK: - Helpers

    private static func pick<T>(rng: inout SplitMix64, from xs: [T]) -> T {
        precondition(!xs.isEmpty)
        return xs[Int(rng.next() % UInt64(xs.count))]
    }
}

/// Tiny deterministic PRNG. Keeps the generated dataset reproducible across
/// machines without relying on Swift stdlib's seeded RNG behavior.
private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
