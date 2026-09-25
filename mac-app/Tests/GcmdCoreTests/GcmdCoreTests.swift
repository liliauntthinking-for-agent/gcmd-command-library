import Foundation
import XCTest
@testable import GcmdCore

final class GcmdCoreTests: XCTestCase {
    func testSaveUpdateDelete() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gcmd-core-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try GcmdStore(dataDirectory: directory)
        let saved = try store.save(
            GcmdDraft(
                title: "Git status",
                command: "git status -sb",
                description: "Show the current branch and working tree",
                shell: "zsh",
                cwd: "/tmp",
                tags: "git, daily",
                variables: [
                    GcmdVariable(name: "branch", defaultValue: "main", required: true)
                ]
            )
        )
        XCTAssertEqual(try store.search("daily").first?.id, saved.id)
        XCTAssertEqual(try store.search("branch").first?.variables.first?.name, "branch")

        let updated = try store.update(
            GcmdDraft(
                id: saved.id,
                title: "Git status updated",
                command: "git status --short",
                description: "Updated description",
                shell: "zsh",
                cwd: "/tmp",
                tags: "git",
                variables: [
                    GcmdVariable(name: "branch", defaultValue: "develop", required: false)
                ]
            )
        )
        XCTAssertEqual(updated.title, "Git status updated")
        XCTAssertEqual(try store.search("status").first?.command, "git status --short")
        XCTAssertEqual(updated.description, "Updated description")
        XCTAssertEqual(updated.variables.first?.defaultValue, "develop")

        try store.delete(id: saved.id)
        XCTAssertTrue(try store.search("status").isEmpty)
        XCTAssertEqual(try store.list(includeDeleted: true).count, 1)
    }

    func testDirectorySyncCreatesJsonRecords() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gcmd-sync-\(UUID().uuidString)")
        let database = root.appendingPathComponent("database")
        let remote = root.appendingPathComponent("remote")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try GcmdStore(dataDirectory: database)
        _ = try store.save(GcmdDraft(title: "Echo", command: "echo hello"))
        let result = try store.sync(directory: remote)

        XCTAssertEqual(result.commandCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: remote.appendingPathComponent(".gcmd-state.json").path
        ))
        let commandFiles = try FileManager.default.contentsOfDirectory(
            at: remote.appendingPathComponent("commands"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(commandFiles.filter { $0.pathExtension == "json" }.count, 1)
    }

    func testSyncCreatesAndPersistsConflictCopy() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gcmd-conflict-\(UUID().uuidString)")
        let database = root.appendingPathComponent("database")
        let remote = root.appendingPathComponent("remote")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try GcmdStore(dataDirectory: database)
        let saved = try store.save(GcmdDraft(title: "Echo", command: "echo base"))
        _ = try store.sync(directory: remote)

        _ = try store.update(
            GcmdDraft(id: saved.id, title: "Echo local", command: "echo local")
        )

        let remoteFile = remote.appendingPathComponent("commands/\(saved.id).json")
        var remoteCommand = try JSONDecoder().decode(
            GcmdCommand.self,
            from: Data(contentsOf: remoteFile)
        )
        remoteCommand.title = "Echo remote"
        remoteCommand.command = "echo remote"
        remoteCommand.updatedAt = GcmdCore.now()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(remoteCommand).write(to: remoteFile, options: .atomic)

        let result = try store.sync(directory: remote)
        XCTAssertEqual(result.conflictCount, 1)
        let commands = try store.list()
        XCTAssertTrue(commands.contains { $0.conflictOf == saved.id })
        XCTAssertTrue(commands.contains { $0.command == "echo local" })
        XCTAssertTrue(commands.contains { $0.command == "echo remote" })
    }
}
