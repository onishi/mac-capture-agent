import Foundation

enum NetworkGateError: Error {
    case denied(NetworkPolicy.Denial)
    case http(Int)
    case noResponse
}

/// The only place that talks to the network. Enforces `NetworkPolicy`
/// (opt-in, API key present, not in Battery mode, allow-listed HTTPS hosts),
/// uses an ephemeral session (no cookies, no cache) and records what was sent
/// — purpose, host and size, never the content — for the Settings list.
actor NetworkGate {
    private var policy: NetworkPolicy
    private var records: [SentRecord] = []
    private let session: URLSession
    private let onSend: @Sendable (SentRecord) -> Void

    init(policy: NetworkPolicy, onSend: @escaping @Sendable (SentRecord) -> Void) {
        self.policy = policy
        self.onSend = onSend
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
    }

    func update(_ policy: NetworkPolicy) {
        self.policy = policy
    }

    func isAllowed(_ url: URL) -> Bool {
        policy.denial(for: url) == nil
    }

    func send(_ request: URLRequest, purpose: String, includesImage: Bool) async throws -> Data {
        guard let url = request.url else { throw NetworkGateError.noResponse }
        if let denial = policy.denial(for: url) {
            throw NetworkGateError.denied(denial)
        }
        let record = SentRecord(date: Date(), purpose: purpose, host: url.host ?? "?",
                                bytes: request.httpBody?.count ?? 0, includesImage: includesImage)
        records.insert(record, at: 0)
        if records.count > 50 { records.removeLast(records.count - 50) }
        onSend(record)
        Log.app.info("Network request: \(purpose, privacy: .public), \(record.bytes) bytes")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkGateError.noResponse }
        guard (200..<300).contains(http.statusCode) else {
            Log.app.error("Network request failed with HTTP \(http.statusCode)")
            throw NetworkGateError.http(http.statusCode)
        }
        return data
    }

    func recentRecords() -> [SentRecord] {
        records
    }
}
