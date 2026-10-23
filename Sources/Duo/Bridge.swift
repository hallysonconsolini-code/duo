import Foundation
import Network

struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    func header(_ name: String) -> String? { headers[name.lowercased()] }
}

struct HTTPResponse {
    var status: Int
    var contentType: String?
    var body: Data

    static func json(_ object: Any, status: Int = 200) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return HTTPResponse(status: status, contentType: "application/json", body: data)
    }

    static func empty(_ status: Int) -> HTTPResponse {
        HTTPResponse(status: status, contentType: nil, body: Data())
    }
}

/// Servidor HTTP mínimo em 127.0.0.1 (porta aleatória). Recebe os hooks e as chamadas MCP
/// dos Claude Code dos painéis. Cada requisição precisa do token gerado a cada abertura do app.
final class Bridge {
    let token = UUID().uuidString + UUID().uuidString
    private(set) var port: UInt16 = 0

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "duo.bridge")
    private let handler: @MainActor (HTTPRequest) async -> HTTPResponse

    init(handler: @escaping @MainActor (HTTPRequest) async -> HTTPResponse) {
        self.handler = handler
    }

    var info: BridgeInfo { BridgeInfo(port: port, token: token) }

    func start(onReady: @escaping @MainActor () -> Void) throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self, case .ready = state, let port = listener.port?.rawValue else { return }
            self.port = port
            Task { @MainActor in onReady() }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                self.respond(to: request, on: connection)
            } else if isComplete || error != nil || buffer.count > 32 << 20 {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        let token = self.token
        let handler = self.handler
        Task { @MainActor in
            let response: HTTPResponse
            if request.header("authorization") != "Bearer \(token)" {
                response = .empty(401)
            } else {
                response = await handler(request)
            }
            let data = Self.serialize(response)
            connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    /// Devolve a requisição quando cabeçalho e corpo chegaram por inteiro.
    private static func parse(_ data: Data) -> HTTPRequest? {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let head = String(data: data[..<end.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = data[end.upperBound...]
        guard body.count >= length else { return nil }
        return HTTPRequest(
            method: String(requestLine[0]),
            path: String(requestLine[1]),
            headers: headers,
            body: Data(body.prefix(length))
        )
    }

    private static func serialize(_ response: HTTPResponse) -> Data {
        let reason = [200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized",
                      404: "Not Found", 405: "Method Not Allowed"][response.status] ?? "OK"
        var head = "HTTP/1.1 \(response.status) \(reason)\r\n"
        if let type = response.contentType { head += "Content-Type: \(type)\r\n" }
        head += "Content-Length: \(response.body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + response.body
    }
}
