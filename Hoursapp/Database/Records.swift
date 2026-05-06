import Foundation
import GRDB

struct ClientRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable {
    var id: Int64?
    var name: String
    var createdAt: String
    var updatedAt: String

    static let databaseTableName = "clients"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct ProjectRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable {
    var id: Int64?
    var clientId: Int64
    var name: String
    var createdAt: String
    var updatedAt: String

    static let databaseTableName = "projects"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let clientId = Column(CodingKeys.clientId)
        static let name = Column(CodingKeys.name)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case clientId = "client_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct TaskRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable {
    var id: Int64?
    var clientId: Int64
    var name: String
    var createdAt: String
    var updatedAt: String

    static let databaseTableName = "tasks"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let clientId = Column(CodingKeys.clientId)
        static let name = Column(CodingKeys.name)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case clientId = "client_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct EntryRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    var id: String
    var date: String
    var clientId: Int64
    var projectId: Int64
    var taskId: Int64
    var seconds: Int
    var notes: String
    var startedAt: String?
    var stoppedAt: String?
    var createdAt: String
    var updatedAt: String

    static let databaseTableName = "entries"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let date = Column(CodingKeys.date)
        static let clientId = Column(CodingKeys.clientId)
        static let projectId = Column(CodingKeys.projectId)
        static let taskId = Column(CodingKeys.taskId)
        static let seconds = Column(CodingKeys.seconds)
        static let notes = Column(CodingKeys.notes)
        static let startedAt = Column(CodingKeys.startedAt)
        static let stoppedAt = Column(CodingKeys.stoppedAt)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, date, seconds, notes
        case clientId = "client_id"
        case projectId = "project_id"
        case taskId = "task_id"
        case startedAt = "started_at"
        case stoppedAt = "stopped_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct FavoriteRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable {
    var id: Int64?
    var clientId: Int64
    var projectId: Int64
    var taskId: Int64
    var createdAt: String
    var updatedAt: String

    static let databaseTableName = "favorites"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let clientId = Column(CodingKeys.clientId)
        static let projectId = Column(CodingKeys.projectId)
        static let taskId = Column(CodingKeys.taskId)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case clientId = "client_id"
        case projectId = "project_id"
        case taskId = "task_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
