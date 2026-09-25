import Foundation
import GcmdCore

let arguments = Array(CommandLine.arguments.dropFirst())

func printUsage() {
    print(
        """
        gcmd - local-first command library

        Usage:
          gcmd save [--title TITLE] [--tags TAGS] [--cwd DIR] COMMAND
          gcmd list [QUERY]
          gcmd pick
          gcmd update ID [--title TITLE] [--command COMMAND] [--tags TAGS]
          gcmd delete ID
          gcmd import-warp [WARP_DATABASE]
          gcmd sync init DIRECTORY [--git]
          gcmd sync [--directory DIRECTORY] [--git]
          gcmd path
          gcmd launch search
          gcmd launch save [--command COMMAND] [--cwd DIR]
        """
    )
}

func option(_ name: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: name), args.index(after: index) < args.endIndex else { return nil }
    return args[args.index(after: index)]
}

func remainingCommand(_ args: [String], excluding options: Set<String>) -> String {
    args.filter { !options.contains($0) }.joined(separator: " ")
}

func printError(_ message: String) {
    fputs("\(message)\n", stderr)
}

func appURL() -> URL {
    if let value = ProcessInfo.processInfo.environment["GCMD_APP"] {
        return URL(fileURLWithPath: value)
    }
    return URL(fileURLWithPath: "/Users/hrzy/Desktop/gcmd-command-library/build/gcmd.app")
}

func defaultWarpDatabaseURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(
            "Library/Group Containers/2BBY89MBSN.dev.warp/Library/Application Support/dev.warp.Warp-Stable/warp.sqlite"
        )
}

func launchApp(_ args: [String]) -> Never {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    guard let action = args.first else {
        printUsage()
        exit(2)
    }
    var appArguments: [String]
    switch action {
    case "search":
        appArguments = ["--search"]
    case "save":
        appArguments = ["--save"] + Array(args.dropFirst())
    default:
        printError("gcmd: unknown launch action: \(action)")
        exit(2)
    }
    process.arguments = ["-n", appURL().path, "--args"] + appArguments
    do {
        try process.run()
        process.waitUntilExit()
        exit(process.terminationStatus)
    } catch {
        fputs("gcmd: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

guard let subcommand = arguments.first else {
    printUsage()
    exit(2)
}

do {
    let store = try GcmdStore()
    switch subcommand {
    case "path":
        print(store.dataDirectory.path)

    case "save":
        let args = Array(arguments.dropFirst())
        let command: String
        if args.contains("--stdin") {
            command = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } else {
            command = option("--command", in: args) ?? remainingCommand(
                args,
                excluding: [
                    "--command", option("--command", in: args) ?? "",
                    "--title", option("--title", in: args) ?? "",
                    "--tags", option("--tags", in: args) ?? "",
                    "--cwd", option("--cwd", in: args) ?? "",
                    "--stdin"
                ]
            )
        }
        let draft = GcmdDraft(
            title: option("--title", in: args) ?? "",
            command: command,
            cwd: option("--cwd", in: args) ?? FileManager.default.currentDirectoryPath,
            tags: option("--tags", in: args) ?? ""
        )
        let saved = try store.save(draft)
        print("saved \(saved.id)  \(saved.title)")

    case "list", "ls":
        let args = Array(arguments.dropFirst())
        let query = args.first(where: { !$0.hasPrefix("--") }) ?? ""
        let records = try store.search(query, includeDeleted: args.contains("--all"))
        if args.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(data: try encoder.encode(records), encoding: .utf8) ?? "[]")
        } else {
            for command in records {
                print("\(command.id)  \(command.title)")
                print("  \(command.command)")
            }
            if records.isEmpty { print("No commands found.") }
        }

    case "pick":
        let args = Array(arguments.dropFirst())
        let records = try store.search(option("--query", in: args) ?? "")
        guard !records.isEmpty else {
            printError("No commands found.")
            exit(1)
        }
        for (index, command) in records.enumerated() {
            printError("\(index + 1). \(command.title)")
            printError("   \(command.command)")
        }
        fputs("Select number: ", stderr)
        let selected = Int(readLine() ?? "") ?? 1
        guard records.indices.contains(selected - 1) else { exit(1) }
        print(records[selected - 1].command)

    case "update":
        guard arguments.count >= 2 else { throw GcmdError.message("update requires an ID") }
        let args = Array(arguments.dropFirst(2))
        let current = try store.list(includeDeleted: true).first { $0.id == arguments[1] }
        guard let current else { throw GcmdError.commandNotFound(arguments[1]) }
        let updated = try store.update(
            GcmdDraft(
                id: current.id,
                title: option("--title", in: args) ?? current.title,
                command: option("--command", in: args) ?? current.command,
                description: current.description,
                cwd: option("--cwd", in: args) ?? current.cwd ?? "",
                tags: option("--tags", in: args) ?? current.tags.joined(separator: ", "),
                variables: current.variables
            )
        )
        print("updated \(updated.id)  \(updated.title)")

    case "delete":
        guard arguments.count >= 2 else { throw GcmdError.message("delete requires an ID") }
        try store.delete(id: arguments[1])
        print("deleted \(arguments[1])")

    case "import-warp":
        let source = arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
            ?? defaultWarpDatabaseURL()
        let result = try store.replaceWithWarpDatabase(at: source)
        print("imported \(result.commandCount) Warp commands")
        print("added \(result.folderTagCount) folder tags")

    case "sync":
        let args = Array(arguments.dropFirst())
        if args.first == "init" {
            guard args.count >= 2 else { throw GcmdError.message("sync init requires a directory") }
            try store.configureSyncDirectory(
                URL(fileURLWithPath: args[1]).standardizedFileURL,
                initializeGit: args.contains("--git")
            )
            print("sync directory configured")
        } else {
            let directory = option("--directory", in: args).map { URL(fileURLWithPath: $0) }
            let result = try store.sync(directory: directory, useGit: args.contains("--git"))
            print(result.summary)
        }

    case "launch":
        launchApp(Array(arguments.dropFirst()))

    default:
        printUsage()
        exit(2)
    }
} catch {
    fputs("gcmd: \(error.localizedDescription)\n", stderr)
    exit(1)
}
