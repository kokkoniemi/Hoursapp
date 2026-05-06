import Foundation
@testable import Hoursapp

enum TestSupport {
    static func makeTempDir(file: StaticString = #file, line: UInt = #line) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "hoursapp-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    static func makeStorage() throws -> (Storage, URL) {
        let dir = makeTempDir()
        let storage = Storage(directory: dir)
        try storage.bootstrap()
        return (storage, dir)
    }

    static func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    static func iso(_ date: Date) -> String {
        DateFormat.timestamp(from: date)
    }

    static func day(_ date: Date) -> String {
        DateFormat.day(from: date)
    }

    static func entry(
        id: String = UUID().uuidString,
        date: String,
        client: String = "Acme",
        project: String = "Site",
        task: String = "Design",
        seconds: Int = 0,
        notes: String = "",
        startedAt: Date? = nil,
        stoppedAt: Date? = nil
    ) -> Entry {
        Entry(
            id: id,
            date: date,
            client: client,
            project: project,
            task: task,
            seconds: seconds,
            notes: notes,
            startedAt: startedAt.map(iso),
            stoppedAt: stoppedAt.map(iso)
        )
    }
}
