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

    func testRemoteRepositoryConfigurationPreservesSyncDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gcmd-remote-\(UUID().uuidString)")
        let database = root.appendingPathComponent("database")
        let remote = root.appendingPathComponent("remote")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try GcmdStore(dataDirectory: database)
        try store.configureSyncDirectory(remote, initializeGit: true)
        let configuredURL = "git@example.com:account/repository.git"
        try store.setRemoteRepository(configuredURL)

        XCTAssertEqual(try store.syncDirectory()?.standardizedFileURL.path, remote.standardizedFileURL.path)
        XCTAssertEqual(store.remoteRepositoryURL(), configuredURL)
    }

    func testSSHBridgeDispatchesSearch() throws {
        let bridge = try GcmdSSHBridgeServer(localPort: 0)
        let launched = DispatchSemaphore(value: 0)
        var receivedArguments: [String] = []
        bridge.launchApp = { arguments in
            receivedArguments = arguments
            launched.signal()
        }
        try bridge.start()
        defer { bridge.stop() }

        let request = URLRequest(url: URL(string: "\(bridge.baseURL)/search")!)
        let (_, response) = try URLSession.shared.synchronousData(for: request)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(launched.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(receivedArguments, ["--search"])
    }

    func testSSHBridgeRejectsWrongToken() throws {
        let bridge = try GcmdSSHBridgeServer(localPort: 0)
        bridge.launchApp = { _ in
            XCTFail("bridge must not launch the app for an invalid token")
        }
        try bridge.start()
        defer { bridge.stop() }

        let url = URL(string: "http://127.0.0.1:\(bridge.localPort)/wrong-token/search")!
        let (_, response) = try URLSession.shared.synchronousData(for: URLRequest(url: url))

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404)
    }

    func testRemoteCommandEmbedsPortsAndToken() {
        let script = GcmdSSHBridge.remoteScript(
            baseURL: "http://127.0.0.1:23456/bridge-token"
        )
        let command = GcmdSSHBridge.remoteCommand(
            remotePort: 23456,
            localPort: 34567,
            token: "anything-encoded-in-script"
        )

        XCTAssertTrue(command.contains("mktemp"))
        XCTAssertTrue(command.contains("infocmp \"${TERM:-dumb}\""))
        XCTAssertTrue(command.contains("TERM=xterm-256color; export TERM"))
        XCTAssertTrue(script.contains("http://127.0.0.1:23456/bridge-token"))
        XCTAssertTrue(script.contains("gcmd-remote-search"))
        XCTAssertFalse(script.contains("stty "))
    }
}

private extension URLSession {
    func synchronousData(for request: URLRequest) throws -> (Data, URLResponse) {
        var result: Result<(Data, URLResponse), Error>?
        let semaphore = DispatchSemaphore(value: 0)
        dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
            } else {
                result = .success((data ?? Data(), response!))
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()

        return try result!.get()
    }
}
