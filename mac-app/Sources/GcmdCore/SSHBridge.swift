import Foundation
import Network

public struct GcmdSSHBridgeError: Error, LocalizedError {
    public let message: String

    public var errorDescription: String? { message }
}

public final class GcmdSSHBridgeServer {
    public let token: String
    public private(set) var localPort: UInt16

    public var launchApp: ([String]) throws -> Void
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.gcmd.ssh-bridge")
    private let stateQueue = DispatchQueue(label: "com.gcmd.ssh-bridge-state")
    private var stopped = false

    public init(localPort: UInt16 = 0, token: String? = nil) throws {
        self.token = token ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")
        self.localPort = localPort
        launchApp = { arguments in
            guard let appPath = ProcessInfo.processInfo.environment["GCMD_APP"], !appPath.isEmpty else {
                throw GcmdSSHBridgeError(message: "GCMD_APP is not set")
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-n", appPath, "--args"] + arguments
            try process.run()
        }
    }

    public var baseURL: String {
        "http://127.0.0.1:\(localPort)/\(token)"
    }

    public func start() throws {
        try stateQueue.sync {
            guard !stopped else {
                throw GcmdSSHBridgeError(message: "SSH bridge has stopped")
            }
            guard listener == nil else { return }

            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host("127.0.0.1"),
                port: NWEndpoint.Port(rawValue: localPort) ?? .any
            )
            let listener = try NWListener(using: parameters)
            self.listener = listener

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }

            let ready = DispatchGroup()
            var startError: Error?
            ready.enter()
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if let port = listener.port?.rawValue, port != 0 {
                        self?.localPort = port
                    }
                    ready.leave()
                case .failed(let error):
                    startError = GcmdSSHBridgeError(message: "SSH bridge listener failed: \(error)")
                    ready.leave()
                case .cancelled:
                    break
                default:
                    break
                }
            }

            listener.start(queue: queue)
            ready.wait()

            if let startError {
                listener.cancel()
                self.listener = nil
                throw startError
            }
        }
    }

    public func stop() {
        stateQueue.sync {
            guard !stopped else { return }
            stopped = true
            listener?.cancel()
            listener = nil
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var current = buffer
            if let data {
                current.append(data)
            }

            let separator = Data("\r\n\r\n".utf8)
            guard let headerEnd = current.range(of: separator) else {
                if error == nil && !complete && current.count < 1_048_576 {
                    self.receive(connection, buffer: current)
                } else {
                    connection.cancel()
                }
                return
            }

            let header = current[current.startIndex..<headerEnd.lowerBound]
            let body = current[headerEnd.upperBound...]
            guard let request = self.parseRequest(header: Data(header), body: Data(body)) else {
                if error == nil && !complete && current.count < 1_048_576 {
                    self.receive(connection, buffer: current)
                } else {
                    self.respond(connection, status: "400 Bad Request")
                }
                return
            }

            self.dispatch(request) { status in
                self.respond(connection, status: status)
            }
        }
    }

    private func parseRequest(header: Data, body: Data) -> SSHBridgeRequest? {
        guard let text = String(data: header, encoding: .isoLatin1) else { return nil }
        var lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first?.split(separator: " "), requestLine.count >= 2 else {
            return nil
        }
        lines.removeFirst()

        var contentLength = 0
        for line in lines {
            let fields = line.split(separator: ":", maxSplits: 1)
            guard fields.count == 2, fields[0].lowercased() == "content-length" else { continue }
            contentLength = Int(fields[1].trimmingCharacters(in: .whitespaces)) ?? 0
        }
        guard contentLength >= 0, contentLength <= 65_536, body.count >= contentLength else {
            return nil
        }

        let target = String(requestLine[1])
        guard target.hasPrefix("/") else { return nil }
        let components = target.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2 else { return nil }
        let requestToken = String(components[0])
        let authorized = secureEqual(requestToken, token)

        return SSHBridgeRequest(
            method: String(requestLine[0]),
            action: String(components[1]),
            body: body.prefix(contentLength),
            authorized: authorized
        )
    }

    private func dispatch(_ request: SSHBridgeRequest, completion: @escaping (String) -> Void) {
        guard request.authorized else {
            completion("404 Not Found")
            return
        }
        switch (request.method, request.action) {
        case ("GET", "search"):
            do {
                try launchApp(["--search"])
                completion("200 OK")
            } catch {
                completion("500 Internal Server Error")
            }
        case ("POST", "save"):
            let values = Self.formValues(request.body)
            guard let command = values["command"], !command.isEmpty else {
                completion("400 Bad Request")
                return
            }
            var arguments = ["--save", "--command", command]
            if let cwd = values["cwd"], !cwd.isEmpty {
                arguments += ["--cwd", cwd]
            }
            do {
                try launchApp(arguments)
                completion("200 OK")
            } catch {
                completion("500 Internal Server Error")
            }
        default:
            completion("404 Not Found")
        }
    }

    private func respond(_ connection: NWConnection, status: String) {
        let response = Data("HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func formValues(_ body: Data) -> [String: String] {
        guard let text = String(data: body, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for pair in text.split(separator: "&") {
            let fields = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let name = fields.first else { continue }
            let value = fields.count > 1 ? String(fields[1]) : ""
            values[String(name)] = percentDecoded(value)
        }
        return values
    }

    private static func percentDecoded(_ value: String) -> String {
        value
            .replacingOccurrences(of: "+", with: " ")
            .removingPercentEncoding ?? value
    }

    private func secureEqual(_ left: String, _ right: String) -> Bool {
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for (leftByte, rightByte) in zip(left.utf8, right.utf8) {
            difference |= leftByte ^ rightByte
        }
        return difference == 0
    }
}

private struct SSHBridgeRequest {
    let method: String
    let action: String
    let body: Data
    let authorized: Bool
}

public enum GcmdSSHBridge {
    public static func remoteCommand(remotePort: UInt16, localPort: UInt16, token: String) -> String {
        let script = remoteScript(
            baseURL: "http://127.0.0.1:\(remotePort)/\(token)"
        )
        let encoded = Data(script.utf8).base64EncodedString()
        return """
        umask 077; \
        GCMD_BRIDGE_FILE="$(mktemp "${TMPDIR:-/tmp}/gcmd-bridge-XXXXXXXXXX")"; \
        export GCMD_BRIDGE_FILE; \
        printf '%s' '\(encoded)' | base64 -d > "$GCMD_BRIDGE_FILE"; \
        chmod 700 "$GCMD_BRIDGE_FILE"; \
        case "$(basename "${SHELL:-/bin/sh}")" in \
          *bash*) exec "$SHELL" -il -c 'source "$GCMD_BRIDGE_FILE"; rm -f "$GCMD_BRIDGE_FILE"; exec "$SHELL" -il' ;; \
          *) exec "$SHELL" -il -c 'source "$GCMD_BRIDGE_FILE"; rm -f "$GCMD_BRIDGE_FILE"; exec "$SHELL" -il' ;; \
        esac
        """
    }

    public static func remoteScript(baseURL: String) -> String {
        """
        GCMD_BRIDGE_URL="\(baseURL)"
        export GCMD_BRIDGE_URL

        function _gcmd_bridge_message() {
          if [ -n "$ZSH_VERSION" ]; then
            zle -M "$1"
          else
            printf '%s\\n' "$1" >&2
          fi
        }

        function _gcmd_bridge_search() {
          if [ -n "$ZSH_VERSION" ]; then
            zle -I
          fi
          if command curl -fsS --max-time 2 "$GCMD_BRIDGE_URL/search" >/dev/null; then
            :
          else
            _gcmd_bridge_message "gcmd: SSH bridge unavailable"
          fi
          if [ -n "$ZSH_VERSION" ]; then
            zle reset-prompt
          fi
        }

        function _gcmd_bridge_save() {
          local input="${BUFFER:-}"
          local directory="$PWD"
          if [ -z "$ZSH_VERSION" ]; then
            input="${READLINE_LINE:-}"
          fi
          if [ -z "$input" ]; then
            _gcmd_bridge_message "gcmd: current input is empty"
            return
          fi
          if [ -n "$ZSH_VERSION" ]; then
            zle -I
          fi
          if command curl -fsS --max-time 2 "$GCMD_BRIDGE_URL/save" \\
            --data-urlencode "command=$input" \\
            --data-urlencode "cwd=$directory" >/dev/null; then
            :
          else
            _gcmd_bridge_message "gcmd: SSH bridge unavailable"
          fi
          if [ -n "$ZSH_VERSION" ]; then
            zle reset-prompt
          fi
        }

        if [[ -n "${ZSH_VERSION:-}" ]]; then
          zle -N gcmd-remote-search _gcmd_bridge_search
          zle -N gcmd-remote-save _gcmd_bridge_save
          for keymap in emacs viins vicmd; do
            bindkey -M "$keymap" $'\\x07' gcmd-remote-search
            bindkey -M "$keymap" $'\\x18' gcmd-remote-save
          done
        else
          bind -x '"\\C-g": _gcmd_bridge_search'
          bind -x '"\\C-x": _gcmd_bridge_save'
        fi
        """
    }
}
