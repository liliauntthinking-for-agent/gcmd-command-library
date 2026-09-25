import Foundation
import SQLite3

public enum GcmdCore {
    public static func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

public struct GcmdVariable: Codable, Hashable, Identifiable {
    public var name: String
    public var defaultValue: String
    public var required: Bool

    public var id: String { name }

    public init(name: String = "", defaultValue: String = "", required: Bool = true) {
        self.name = name
        self.defaultValue = defaultValue
        self.required = required
    }

    enum CodingKeys: String, CodingKey {
        case name
        case defaultValue = "default_value"
        case required
    }
}

public struct GcmdCommand: Codable, Identifiable, Hashable {
    public let id: String
    public var title: String
    public var command: String
    public var description: String
    public var cwd: String?
    public var tags: [String]
    public var variables: [GcmdVariable]
    public var createdAt: String
    public var updatedAt: String
    public var deletedAt: String?
    public var conflictOf: String?

    public init(
        id: String = UUID().uuidString.lowercased(),
        title: String,
        command: String,
        description: String = "",
        cwd: String? = nil,
        tags: [String] = [],
        variables: [GcmdVariable] = [],
        createdAt: String = GcmdCore.now(),
        updatedAt: String = GcmdCore.now(),
        deletedAt: String? = nil,
        conflictOf: String? = nil
    ) {
        self.id = id
        self.title = title
        self.command = command
        self.description = description
        self.cwd = cwd
        self.tags = tags
        self.variables = variables
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.conflictOf = conflictOf
    }

    enum CodingKeys: String, CodingKey {
        case id, title, command, cwd, tags
        case description, variables
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case conflictOf = "conflict_of"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        command = try values.decode(String.self, forKey: .command)
        description = try values.decodeIfPresent(String.self, forKey: .description) ?? ""
        cwd = try values.decodeIfPresent(String.self, forKey: .cwd)
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        variables = try values.decodeIfPresent([GcmdVariable].self, forKey: .variables) ?? []
        createdAt = try values.decode(String.self, forKey: .createdAt)
        updatedAt = try values.decode(String.self, forKey: .updatedAt)
        deletedAt = try values.decodeIfPresent(String.self, forKey: .deletedAt)
        conflictOf = try values.decodeIfPresent(String.self, forKey: .conflictOf)
    }
}

public struct GcmdDraft {
    public var id: String?
    public var title: String
    public var command: String
    public var description: String
    public var cwd: String
    public var tags: String
    public var variables: [GcmdVariable]

    public init(
        id: String? = nil,
        title: String = "",
        command: String = "",
        description: String = "",
        cwd: String = "",
        tags: String = "",
        variables: [GcmdVariable] = []
    ) {
        self.id = id
        self.title = title
        self.command = command
        self.description = description
        self.cwd = cwd
        self.tags = tags
        self.variables = variables
    }

    public init(command: GcmdCommand) {
        self.init(
            id: command.id,
            title: command.title,
            command: command.command,
            description: command.description,
            cwd: command.cwd ?? "",
            tags: command.tags.joined(separator: ", "),
            variables: command.variables
        )
    }
}

public struct GcmdSyncResult {
    public let commandCount: Int
    public let conflictCount: Int

    public var summary: String {
        var value = "synced \(commandCount) commands"
        if conflictCount > 0 {
            value += "; created \(conflictCount) conflict copies"
        }
        return value
    }
}

public struct GcmdWarpImportResult {
    public let commandCount: Int
    public let folderTagCount: Int
}

public enum GcmdError: LocalizedError {
    case message(String)
    case commandNotFound(String)
    case syncDirectoryNotConfigured

    public var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        case .commandNotFound(let id):
            return "command not found: \(id)"
        case .syncDirectoryNotConfigured:
            return "sync directory is not configured"
        }
    }
}

public final class GcmdStore {
    public let dataDirectory: URL
    private let databaseURL: URL
    private let configURL: URL
    private var database: OpaquePointer?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(dataDirectory: URL? = nil) throws {
        if let override = ProcessInfo.processInfo.environment["GCMD_HOME"], dataDirectory == nil {
            self.dataDirectory = URL(fileURLWithPath: override).standardizedFileURL
        } else {
            self.dataDirectory = dataDirectory
                ?? FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/gcmd")
        }
        databaseURL = self.dataDirectory.appendingPathComponent("commands.sqlite3")
        configURL = self.dataDirectory.appendingPathComponent("config.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()

        try FileManager.default.createDirectory(
            at: self.dataDirectory,
            withIntermediateDirectories: true
        )
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE,
            nil
        )
        guard result == SQLITE_OK, let handle else {
            throw GcmdError.message("cannot open SQLite database")
        }
        database = handle
        do {
            try execute(
                """
                CREATE TABLE IF NOT EXISTS commands (
                    id TEXT PRIMARY KEY,
                    title TEXT NOT NULL,
                    command TEXT NOT NULL,
                    description TEXT NOT NULL DEFAULT '',
                    cwd TEXT,
                    tags TEXT NOT NULL DEFAULT '[]',
                    variables TEXT NOT NULL DEFAULT '[]',
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    deleted_at TEXT,
                    conflict_of TEXT
                )
                """
            )
            try ensureColumn("ALTER TABLE commands ADD COLUMN description TEXT NOT NULL DEFAULT ''")
            try ensureColumn("ALTER TABLE commands ADD COLUMN variables TEXT NOT NULL DEFAULT '[]'")
            try ensureColumn("ALTER TABLE commands ADD COLUMN conflict_of TEXT")
        } catch {
            sqlite3_close(handle)
            database = nil
            throw error
        }
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    public func list(includeDeleted: Bool = false) throws -> [GcmdCommand] {
        let columns = "id, title, command, description, cwd, tags, variables, created_at, updated_at, deleted_at, conflict_of"
        let sql = includeDeleted
            ? "SELECT \(columns) FROM commands ORDER BY lower(title), updated_at"
            : "SELECT \(columns) FROM commands WHERE deleted_at IS NULL ORDER BY lower(title), updated_at"
        var statement: OpaquePointer?
        try prepare(sql, &statement)
        defer { sqlite3_finalize(statement) }

        var commands: [GcmdCommand] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            commands.append(try readCommand(statement))
        }
        return commands
    }

    public func search(_ query: String, includeDeleted: Bool = false) throws -> [GcmdCommand] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return try list(includeDeleted: includeDeleted).filter { command in
            guard !needle.isEmpty else { return true }
            return [
                command.title,
                command.command,
                command.description,
                command.tags.joined(separator: " "),
                command.variables.map(\.name).joined(separator: " ")
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(needle)
        }
    }

    @discardableResult
    public func save(_ draft: GcmdDraft) throws -> GcmdCommand {
        let commandText = draft.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commandText.isEmpty else {
            throw GcmdError.message("command is required")
        }
        try execute("DELETE FROM commands WHERE command = \(sqlLiteral(commandText)) AND deleted_at IS NULL")
        let now = GcmdCore.now()
        let command = GcmdCommand(
            title: draft.title.isEmpty ? Self.title(for: commandText) : draft.title,
            command: commandText,
            description: draft.description,
            cwd: draft.cwd.isEmpty ? nil : draft.cwd,
            tags: Self.tags(from: draft.tags),
            variables: draft.variables.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            createdAt: now,
            updatedAt: now
        )
        try upsert(command)
        return command
    }

    @discardableResult
    public func update(_ draft: GcmdDraft) throws -> GcmdCommand {
        guard let id = draft.id, var command = try list(includeDeleted: true).first(where: { $0.id == id }) else {
            throw GcmdError.commandNotFound(draft.id ?? "")
        }
        let commandText = draft.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commandText.isEmpty else {
            throw GcmdError.message("command is required")
        }
        command.title = draft.title.isEmpty ? Self.title(for: commandText) : draft.title
        command.command = commandText
        command.description = draft.description
        command.cwd = draft.cwd.isEmpty ? nil : draft.cwd
        command.tags = Self.tags(from: draft.tags)
        command.variables = draft.variables.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        command.updatedAt = GcmdCore.now()
        command.deletedAt = nil
        try upsert(command)
        return command
    }

    public func delete(id: String) throws {
        guard var command = try list(includeDeleted: true).first(where: { $0.id == id }) else {
            throw GcmdError.commandNotFound(id)
        }
        command.deletedAt = GcmdCore.now()
        command.updatedAt = GcmdCore.now()
        try upsert(command)
    }

    public func replaceWithWarpDatabase(at sourceURL: URL) throws -> GcmdWarpImportResult {
        let imported = try readWarpWorkflows(from: sourceURL)
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try execute("DELETE FROM commands")
            var folderTagCount = 0
            for item in imported {
                let commandText = item.workflow.command.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !commandText.isEmpty else { continue }
                var tags = item.workflow.tags
                if let folder = item.folder, !folder.isEmpty {
                    tags.append(folder)
                    folderTagCount += 1
                }
                let variables = item.workflow.arguments.compactMap { argument -> GcmdVariable? in
                    let name = argument.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return nil }
                    return GcmdVariable(
                        name: name,
                        defaultValue: argument.defaultValue ?? "",
                        required: argument.defaultValue == nil
                    )
                }
                let command = GcmdCommand(
                    title: item.workflow.name,
                    command: commandText,
                    description: item.workflow.description ?? "",
                    cwd: nil,
                    tags: Self.uniqueTags(tags),
                    variables: variables,
                    createdAt: GcmdCore.now(),
                    updatedAt: GcmdCore.now()
                )
                try upsert(command)
            }
            try execute("COMMIT")
            return GcmdWarpImportResult(
                commandCount: imported.filter {
                    !$0.workflow.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }.count,
                folderTagCount: folderTagCount
            )
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public func syncDirectory() throws -> URL? {
        let config = try readConfig()
        return config["sync_dir"].flatMap { URL(fileURLWithPath: $0) }
    }

    public func configureSyncDirectory(_ directory: URL, initializeGit: Bool) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("commands"),
            withIntermediateDirectories: true
        )
        if initializeGit, !FileManager.default.fileExists(atPath: directory.appendingPathComponent(".git").path) {
            _ = try runGit(["init"], in: directory)
        }
        try writeConfig(["sync_dir": directory.standardizedFileURL.path])
    }

    public func sync(directory: URL? = nil, useGit: Bool = false) throws -> GcmdSyncResult {
        let syncDirectory = try directory ?? syncDirectory() ?? {
            throw GcmdError.syncDirectoryNotConfigured
        }()
        try FileManager.default.createDirectory(
            at: syncDirectory.appendingPathComponent("commands"),
            withIntermediateDirectories: true
        )
        if useGit {
            _ = try runGit(["pull", "--rebase"], in: syncDirectory)
        }

        let local = Dictionary(uniqueKeysWithValues: try list(includeDeleted: true).map { ($0.id, $0) })
        let remote = try readRecords(from: syncDirectory)
        let base = try readState(from: syncDirectory)
        let mergedResult = merge(local: local, remote: remote, base: base)

        for command in mergedResult.records.values {
            try upsert(command)
        }
        try writeRecords(mergedResult.records, to: syncDirectory)
        try writeState(mergedResult.records, to: syncDirectory)

        if useGit {
            _ = try runGit(["add", "commands", ".gcmd-state.json"], in: syncDirectory)
            let status = try runGit(["status", "--porcelain"], in: syncDirectory)
            if !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                _ = try runGit(["commit", "-m", "Sync gcmd commands"], in: syncDirectory)
                _ = try runGit(["push"], in: syncDirectory)
            }
        }
        return GcmdSyncResult(
            commandCount: mergedResult.records.count,
            conflictCount: mergedResult.conflicts
        )
    }

    public static func title(for command: String) -> String {
        let firstLine = command.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", maxSplits: 1)
            .first
            .map(String.init) ?? command
        return firstLine.count <= 72 ? firstLine : String(firstLine.prefix(69)) + "..."
    }

    public static func tags(from value: String) -> [String] {
        uniqueTags(value.split(separator: ",").map(String.init))
    }

    private static func uniqueTags(_ values: [String]) -> [String] {
        Array(
            Set(
                values
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()
    }

    private func execute(_ sql: String) throws {
        guard let database else { throw GcmdError.message("database is closed") }
        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "SQLite error"
            sqlite3_free(errorMessage)
            throw GcmdError.message(message)
        }
    }

    private func prepare(_ sql: String, _ statement: inout OpaquePointer?) throws {
        guard let database else { throw GcmdError.message("database is closed") }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw GcmdError.message(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func ensureColumn(_ sql: String) throws {
        do {
            try execute(sql)
        } catch GcmdError.message(let message) where message.contains("duplicate column name") {
            // Existing databases already have this migrated column.
        }
    }

    private func upsert(_ command: GcmdCommand) throws {
        let sql = """
        INSERT INTO commands
            (id, title, command, description, cwd, tags, variables, created_at, updated_at, deleted_at, conflict_of)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title=excluded.title,
            command=excluded.command,
            description=excluded.description,
            cwd=excluded.cwd,
            tags=excluded.tags,
            variables=excluded.variables,
            created_at=excluded.created_at,
            updated_at=excluded.updated_at,
            deleted_at=excluded.deleted_at,
            conflict_of=excluded.conflict_of
        """
        var statement: OpaquePointer?
        try prepare(sql, &statement)
        defer { sqlite3_finalize(statement) }
        bind(command.id, to: statement, index: 1)
        bind(command.title, to: statement, index: 2)
        bind(command.command, to: statement, index: 3)
        bind(command.description, to: statement, index: 4)
        bind(command.cwd, to: statement, index: 5)
        bind(Self.json(command.tags), to: statement, index: 6)
        bind(Self.json(command.variables), to: statement, index: 7)
        bind(command.createdAt, to: statement, index: 8)
        bind(command.updatedAt, to: statement, index: 9)
        bind(command.deletedAt, to: statement, index: 10)
        bind(command.conflictOf, to: statement, index: 11)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw GcmdError.message("SQLite write failed")
        }
    }

    private func readCommand(_ statement: OpaquePointer?) throws -> GcmdCommand {
        guard
            let id = column(statement, 0),
            let title = column(statement, 1),
            let command = column(statement, 2),
            let tagsJSON = column(statement, 5),
            let createdAt = column(statement, 7),
            let updatedAt = column(statement, 8)
        else {
            throw GcmdError.message("invalid command record")
        }
        let tags = (try? decoder.decode([String].self, from: Data(tagsJSON.utf8))) ?? []
        return GcmdCommand(
            id: id,
            title: title,
            command: command,
            description: column(statement, 3) ?? "",
            cwd: column(statement, 4),
            tags: (try? decoder.decode([String].self, from: Data(tagsJSON.utf8))) ?? tags,
            variables: (try? decoder.decode(
                [GcmdVariable].self,
                from: Data((column(statement, 6) ?? "[]").utf8)
            )) ?? [],
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: column(statement, 9),
            conflictOf: column(statement, 10)
        )
    }

    private func bind(_ value: String?, to statement: OpaquePointer?, index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        _ = value.withCString {
            sqlite3_bind_text(statement, index, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
    }

    private func column(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private func readConfig() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return [:] }
        let data = try Data(contentsOf: configURL)
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func writeConfig(_ config: [String: String]) throws {
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: .atomic)
    }

    private func readRecords(from directory: URL) throws -> [String: GcmdCommand] {
        let commandsDirectory = directory.appendingPathComponent("commands")
        guard FileManager.default.fileExists(atPath: commandsDirectory.path) else { return [:] }
        var records: [String: GcmdCommand] = [:]
        for file in try FileManager.default.contentsOfDirectory(
            at: commandsDirectory,
            includingPropertiesForKeys: nil
        ) where file.pathExtension == "json" {
            let data = try Data(contentsOf: file)
            let command = try decoder.decode(GcmdCommand.self, from: data)
            records[command.id] = command
        }
        return records
    }

    private func readWarpWorkflows(from sourceURL: URL) throws -> [(workflow: WarpWorkflow, folder: String?)] {
        var sourceDatabase: OpaquePointer?
        let result = sqlite3_open_v2(
            sourceURL.path,
            &sourceDatabase,
            SQLITE_OPEN_READONLY,
            nil
        )
        guard result == SQLITE_OK, let sourceDatabase else {
            throw GcmdError.message("cannot open Warp database: \(sourceURL.path)")
        }
        defer { sqlite3_close(sourceDatabase) }

        let sql = """
        SELECT w.data, f.name
        FROM workflows w
        LEFT JOIN object_metadata wm
            ON wm.object_type = 'WORKFLOW'
            AND wm.shareable_object_id = w.id
        LEFT JOIN object_metadata fm
            ON fm.object_type = 'FOLDER'
            AND fm.server_id = wm.folder_id
        LEFT JOIN folders f
            ON f.id = fm.shareable_object_id
        ORDER BY w.id
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(sourceDatabase, sql, -1, &statement, nil) == SQLITE_OK else {
            throw GcmdError.message("cannot read Warp workflows")
        }
        defer { sqlite3_finalize(statement) }

        var workflows: [(workflow: WarpWorkflow, folder: String?)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let dataText = sqlite3_column_text(statement, 0)
            else {
                continue
            }
            let data = Data(bytes: dataText, count: Int(strlen(dataText)))
            let workflow = try decoder.decode(WarpWorkflow.self, from: data)
            let folder = sqlite3_column_text(statement, 1).map { String(cString: $0) }
            workflows.append((workflow, folder))
        }
        return workflows
    }

    private func writeRecords(_ records: [String: GcmdCommand], to directory: URL) throws {
        let commandsDirectory = directory.appendingPathComponent("commands")
        try FileManager.default.createDirectory(at: commandsDirectory, withIntermediateDirectories: true)
        let currentFiles = try FileManager.default.contentsOfDirectory(
            at: commandsDirectory,
            includingPropertiesForKeys: nil
        )
        let expected = Set(records.keys.map { "\($0).json" })
        for file in currentFiles where file.pathExtension == "json" && !expected.contains(file.lastPathComponent) {
            try FileManager.default.removeItem(at: file)
        }
        for command in records.values {
            try encoder.encode(command).write(
                to: commandsDirectory.appendingPathComponent("\(command.id).json"),
                options: .atomic
            )
        }
    }

    private func readState(from directory: URL) throws -> [String: GcmdCommand] {
        let file = directory.appendingPathComponent(".gcmd-state.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        return (try? decoder.decode([String: GcmdCommand].self, from: Data(contentsOf: file))) ?? [:]
    }

    private func writeState(_ records: [String: GcmdCommand], to directory: URL) throws {
        try encoder.encode(records).write(
            to: directory.appendingPathComponent(".gcmd-state.json"),
            options: .atomic
        )
    }

    private func merge(
        local: [String: GcmdCommand],
        remote: [String: GcmdCommand],
        base: [String: GcmdCommand]
    ) -> (records: [String: GcmdCommand], conflicts: Int) {
        var merged: [String: GcmdCommand] = [:]
        var conflicts = 0
        let ids = Set(local.keys).union(remote.keys).union(base.keys)
        for id in ids {
            let localRecord = local[id]
            let remoteRecord = remote[id]
            let baseRecord = base[id]
            if encoded(localRecord) == encoded(remoteRecord) {
                if let localRecord { merged[id] = localRecord }
                continue
            }
            if localRecord == nil, let remoteRecord {
                merged[id] = remoteRecord
                continue
            }
            if remoteRecord == nil, let localRecord {
                merged[id] = localRecord
                continue
            }
            if let baseRecord {
                let localChanged = encoded(localRecord) != encoded(baseRecord)
                let remoteChanged = encoded(remoteRecord) != encoded(baseRecord)
                if localChanged, remoteChanged, let localRecord, let remoteRecord {
                    merged[id] = localRecord
                    let conflict = GcmdCommand(
                        title: remoteRecord.title + " (conflict copy)",
                        command: remoteRecord.command,
                        description: remoteRecord.description,
                        cwd: remoteRecord.cwd,
                        tags: Array(Set(remoteRecord.tags).union(["conflict"])).sorted(),
                        variables: remoteRecord.variables,
                        createdAt: remoteRecord.createdAt,
                        updatedAt: GcmdCore.now(),
                        deletedAt: remoteRecord.deletedAt,
                        conflictOf: id
                    )
                    merged[conflict.id] = conflict
                    conflicts += 1
                } else if localChanged, let localRecord {
                    merged[id] = localRecord
                } else if remoteChanged, let remoteRecord {
                    merged[id] = remoteRecord
                } else if let localRecord {
                    merged[id] = localRecord
                }
                continue
            }
            if let localRecord, let remoteRecord {
                merged[id] = localRecord.updatedAt >= remoteRecord.updatedAt ? localRecord : remoteRecord
            } else if let localRecord {
                merged[id] = localRecord
            } else if let remoteRecord {
                merged[id] = remoteRecord
            }
        }
        return (merged, conflicts)
    }

    private func encoded(_ value: GcmdCommand?) -> Data? {
        guard let value else { return nil }
        return try? encoder.encode(value)
    }

    private func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw GcmdError.message(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return stdout
    }

    private func sqlLiteral(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private static func json<T: Encodable>(_ value: T) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}

private struct WarpWorkflow: Decodable {
    let name: String
    let command: String
    let tags: [String]
    let description: String?
    let arguments: [WarpArgument]

    enum CodingKeys: String, CodingKey {
        case name, command, tags, description, arguments
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        command = try values.decodeIfPresent(String.self, forKey: .command) ?? ""
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        description = try values.decodeIfPresent(String.self, forKey: .description)
        arguments = try values.decodeIfPresent([WarpArgument].self, forKey: .arguments) ?? []
    }
}

private struct WarpArgument: Decodable {
    let name: String
    let defaultValue: String?

    enum CodingKeys: String, CodingKey {
        case name
        case defaultValue = "default_value"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        defaultValue = try values.decodeIfPresent(String.self, forKey: .defaultValue)
    }
}
