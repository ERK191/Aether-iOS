import Foundation
import Security

final class ChatService {
    static let shared = ChatService()

    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder: JSONDecoder
    private var webSocket: URLSessionWebSocketTask?
    private var socketSession: URLSession?
    private let socketLock = NSLock()
    private var socketGeneration = 0
    private var socketToken: String?
    private var socketHandler: ((ChatMessage) -> Void)?
    private var reconnectAttempt = 0

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 180
        session = URLSession(configuration: configuration)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid server date.")
        }
        self.decoder = decoder
    }

    var isConfigured: Bool {
        !(AppConfiguration.apiBaseURL.host?.hasPrefix("YOUR-") ?? true)
    }

    func register(username: String, password: String, completion: @escaping (Result<AuthResponse, Error>) -> Void) {
        authenticate(path: "/api/auth/register", username: username, password: password, completion: completion)
    }

    func login(username: String, password: String, completion: @escaping (Result<AuthResponse, Error>) -> Void) {
        authenticate(path: "/api/auth/login", username: username, password: password, completion: completion)
    }

    private func authenticate(
        path: String,
        username: String,
        password: String,
        completion: @escaping (Result<AuthResponse, Error>) -> Void
    ) {
        let body = ["username": username, "password": password]
        request(path: path, method: "POST", token: nil, body: body, completion: completion)
    }

    func currentUser(token: String, completion: @escaping (Result<ChatUser, Error>) -> Void) {
        request(path: "/api/me", method: "GET", token: token, body: Optional<[String: String]>.none) {
            (result: Result<UserResponse, Error>) in
            completion(result.map(\.user))
        }
    }

    func channels(token: String, completion: @escaping (Result<[Channel], Error>) -> Void) {
        request(path: "/api/channels", method: "GET", token: token, body: Optional<[String: String]>.none) {
            (result: Result<ChannelsResponse, Error>) in
            completion(result.map(\.channels))
        }
    }

    func messages(
        channelID: Int64,
        token: String,
        completion: @escaping (Result<[ChatMessage], Error>) -> Void
    ) {
        request(
            path: "/api/channels/\(channelID)/messages?limit=50",
            method: "GET",
            token: token,
            body: Optional<[String: String]>.none
        ) { (result: Result<MessagesResponse, Error>) in
            completion(result.map(\.messages))
        }
    }

    func send(
        content: String,
        channelID: Int64,
        token: String,
        completion: @escaping (Result<ChatMessage, Error>) -> Void
    ) {
        request(
            path: "/api/channels/\(channelID)/messages",
            method: "POST",
            token: token,
            body: ["content": content]
        ) { (result: Result<MessageResponse, Error>) in
            completion(result.map(\.message))
        }
    }

    func users(
        query: String,
        token: String,
        completion: @escaping (Result<[UserSearchResult], Error>) -> Void
    ) {
        get(queryPath("/api/users", items: [URLQueryItem(name: "query", value: query)]), token: token) {
            (result: Result<UserSearchResponse, Error>) in completion(result.map(\.users))
        }
    }

    func friends(token: String, completion: @escaping (Result<[FriendEntry], Error>) -> Void) {
        get("/api/friends", token: token) { (result: Result<FriendsResponse, Error>) in
            completion(result.map(\.friends))
        }
    }

    func friendRequests(token: String, completion: @escaping (Result<[FriendRequest], Error>) -> Void) {
        get("/api/friends/requests", token: token) { (result: Result<FriendRequestsResponse, Error>) in
            completion(result.map(\.requests))
        }
    }

    func sendFriendRequest(userID: Int64, token: String, completion: @escaping (Result<Void, Error>) -> Void) {
        request(path: "/api/friends/requests", method: "POST", token: token, body: ["user_id": String(userID)]) {
            (result: Result<FriendRequestResponse, Error>) in
            completion(result.map { _ in () })
        }
    }

    func respondToFriendRequest(
        requestID: Int64,
        accept: Bool,
        token: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let action = accept ? "accept" : "reject"
        request(
            path: "/api/friends/requests/\(requestID)/\(action)",
            method: "POST",
            token: token,
            body: Optional<[String: String]>.none
        ) { (result: Result<FriendRequestResponse, Error>) in
            completion(result.map { _ in () })
        }
    }

    func removeFriend(userID: Int64, token: String, completion: @escaping (Result<Void, Error>) -> Void) {
        request(
            path: "/api/friends/\(userID)",
            method: "DELETE",
            token: token,
            body: Optional<[String: String]>.none
        ) { (result: Result<RemovedResponse, Error>) in
            completion(result.map { _ in () })
        }
    }

    func conversations(token: String, completion: @escaping (Result<[DirectConversation], Error>) -> Void) {
        get("/api/conversations", token: token) {
            (result: Result<ConversationsResponse, Error>) in completion(result.map(\.conversations))
        }
    }

    func createConversation(
        userID: Int64,
        token: String,
        completion: @escaping (Result<ConversationRecord, Error>) -> Void
    ) {
        request(
            path: "/api/conversations",
            method: "POST",
            token: token,
            body: ["user_id": String(userID)]
        ) { (result: Result<ConversationResponse, Error>) in
            completion(result.map(\.conversation))
        }
    }

    func directMessages(
        conversationID: Int64,
        token: String,
        completion: @escaping (Result<[ChatMessage], Error>) -> Void
    ) {
        get("/api/conversations/\(conversationID)/messages?limit=50", token: token) {
            (result: Result<MessagesResponse, Error>) in completion(result.map(\.messages))
        }
    }

    func sendDirectMessage(
        content: String,
        conversationID: Int64,
        token: String,
        completion: @escaping (Result<ChatMessage, Error>) -> Void
    ) {
        request(
            path: "/api/conversations/\(conversationID)/messages",
            method: "POST",
            token: token,
            body: ["content": content]
        ) { (result: Result<MessageResponse, Error>) in
            completion(result.map(\.message))
        }
    }

    func servers(token: String, completion: @escaping (Result<[AetherServer], Error>) -> Void) {
        get("/api/servers", token: token) { (result: Result<ServersResponse, Error>) in
            completion(result.map(\.servers))
        }
    }

    func createServer(
        name: String,
        description: String,
        token: String,
        completion: @escaping (Result<ServerCreateResponse, Error>) -> Void
    ) {
        request(
            path: "/api/servers",
            method: "POST",
            token: token,
            body: ["name": name, "description": description]
        ) { completion($0) }
    }

    func joinServer(serverID: Int64, token: String, completion: @escaping (Result<Void, Error>) -> Void) {
        request(
            path: "/api/servers/\(serverID)/join",
            method: "POST",
            token: token,
            body: Optional<[String: String]>.none
        ) { (result: Result<JoinedServerResponse, Error>) in
            completion(result.map { _ in () })
        }
    }

    func leaveServer(serverID: Int64, token: String, completion: @escaping (Result<Void, Error>) -> Void) {
        request(
            path: "/api/servers/\(serverID)/membership",
            method: "DELETE",
            token: token,
            body: Optional<[String: String]>.none
        ) { (result: Result<JoinedServerResponse, Error>) in
            completion(result.map { _ in () })
        }
    }

    func deleteServer(serverID: Int64, token: String, completion: @escaping (Result<Void, Error>) -> Void) {
        request(
            path: "/api/servers/\(serverID)",
            method: "DELETE",
            token: token,
            body: Optional<[String: String]>.none
        ) { (result: Result<DeleteAccountResponse, Error>) in
            completion(result.map { _ in () })
        }
    }

    func serverChannels(serverID: Int64, token: String, completion: @escaping (Result<[Channel], Error>) -> Void) {
        get("/api/servers/\(serverID)/channels", token: token) {
            (result: Result<ServerChannelsResponse, Error>) in completion(result.map(\.channels))
        }
    }

    func updateAvatar(
        dataURL: String?,
        token: String,
        completion: @escaping (Result<ChatUser, Error>) -> Void
    ) {
        request(path: "/api/me/avatar", method: "PUT", token: token, body: AvatarBody(avatar: dataURL)) {
            (result: Result<UserResponse, Error>) in completion(result.map(\.user))
        }
    }

    func deleteAccount(token: String, completion: @escaping (Result<Void, Error>) -> Void) {
        request(
            path: "/api/me",
            method: "DELETE",
            token: token,
            body: Optional<[String: String]>.none
        ) { (result: Result<DeleteAccountResponse, Error>) in
            completion(result.map { _ in () })
        }
    }

    private func get<Response: Decodable>(
        _ path: String,
        token: String,
        completion: @escaping (Result<Response, Error>) -> Void
    ) {
        request(path: path, method: "GET", token: token, body: Optional<[String: String]>.none, completion: completion)
    }

    private func queryPath(_ path: String, items: [URLQueryItem]) -> String {
        var components = URLComponents()
        components.path = path
        components.queryItems = items
        return components.string ?? path
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        token: String?,
        body: Body?,
        completion: @escaping (Result<Response, Error>) -> Void
    ) {
        guard isConfigured else {
            completion(.failure(ChatAPIError.invalidURL))
            return
        }
        let pathParts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        guard var urlComponents = URLComponents(
            url: AppConfiguration.apiBaseURL,
            resolvingAgainstBaseURL: false
        ) else {
            completion(.failure(ChatAPIError.invalidURL))
            return
        }
        urlComponents.path = String(pathParts[0])
        if pathParts.count == 2 {
            urlComponents.queryItems = URLComponents(string: "?\(pathParts[1])")?.queryItems
        }
        guard let url = urlComponents.url else {
            completion(.failure(ChatAPIError.invalidURL))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            do {
                request.httpBody = try encoder.encode(body)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            } catch {
                completion(.failure(error))
                return
            }
        }

        session.dataTask(with: request) { [decoder] data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, let data else {
                completion(.failure(ChatAPIError.invalidResponse))
                return
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                let message = (try? decoder.decode(APIErrorResponse.self, from: data).error)
                    ?? "The server returned error \(httpResponse.statusCode)."
                completion(.failure(ChatAPIError.server(message)))
                return
            }
            do {
                completion(.success(try decoder.decode(Response.self, from: data)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func connectWebSocket(
        token: String,
        onMessage: @escaping (ChatMessage) -> Void,
        onReady: @escaping () -> Void
    ) {
        disconnectWebSocket()
        socketLock.lock()
        socketGeneration += 1
        socketToken = token
        socketHandler = onMessage
        reconnectAttempt = 0
        let generation = socketGeneration
        socketLock.unlock()
        openWebSocket(generation: generation, onMessage: onMessage, onReady: onReady)
    }

    private func openWebSocket(
        generation: Int,
        onMessage: @escaping (ChatMessage) -> Void,
        onReady: @escaping () -> Void
    ) {
        socketLock.lock()
        guard socketGeneration == generation, let token = socketToken, socketHandler != nil else {
            socketLock.unlock()
            return
        }
        socketLock.unlock()
        guard isConfigured,
              var components = URLComponents(url: AppConfiguration.apiBaseURL, resolvingAgainstBaseURL: false) else {
            return
        }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/ws"
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let newSession = URLSession(configuration: .default)
        let task = newSession.webSocketTask(with: request)
        socketLock.lock()
        guard socketGeneration == generation, socketToken != nil else {
            socketLock.unlock()
            newSession.invalidateAndCancel()
            return
        }
        socketSession = newSession
        self.webSocket = task
        socketLock.unlock()
        task.resume()
        receiveNextMessage(from: task, generation: generation, onMessage: onMessage, onReady: onReady)
    }

    private func receiveNextMessage(
        from task: URLSessionWebSocketTask,
        generation: Int,
        onMessage: @escaping (ChatMessage) -> Void,
        onReady: @escaping () -> Void
    ) {
        task.receive { [weak self, weak task] result in
            guard let self, let task else { return }
            switch result {
            case .success(let message):
                let data: Data
                switch message {
                case .data(let value): data = value
                case .string(let value): data = Data(value.utf8)
                @unknown default:
                    self.receiveNextMessage(
                        from: task,
                        generation: generation,
                        onMessage: onMessage,
                        onReady: onReady
                    )
                    return
                }
                if let event = try? self.decoder.decode(SocketEvent.self, from: data) {
                    if event.type == "ready" {
                        self.socketLock.lock()
                        if self.socketGeneration == generation {
                            self.reconnectAttempt = 0
                        }
                        self.socketLock.unlock()
                        onReady()
                    } else if event.type == "message", let message = event.message {
                        onMessage(message)
                    }
                }
                self.receiveNextMessage(
                    from: task,
                    generation: generation,
                    onMessage: onMessage,
                    onReady: onReady
                )
            case .failure:
                self.scheduleReconnect(
                    after: task,
                    generation: generation,
                    onMessage: onMessage,
                    onReady: onReady
                )
            }
        }
    }

    private func scheduleReconnect(
        after task: URLSessionWebSocketTask,
        generation: Int,
        onMessage: @escaping (ChatMessage) -> Void,
        onReady: @escaping () -> Void
    ) {
        socketLock.lock()
        guard socketGeneration == generation, webSocket === task, let socketToken else {
            socketLock.unlock()
            return
        }
        let oldSession = socketSession
        webSocket = nil
        socketSession = nil
        reconnectAttempt += 1
        let exponent = min(reconnectAttempt - 1, 5)
        let delay = min(pow(2.0, Double(exponent)), 30.0)
        socketLock.unlock()

        task.cancel(with: .goingAway, reason: nil)
        oldSession?.invalidateAndCancel()
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.socketLock.lock()
            let shouldReconnect = self.socketGeneration == generation && self.socketToken == socketToken
            self.socketLock.unlock()
            if shouldReconnect {
                self.openWebSocket(
                    generation: generation,
                    onMessage: onMessage,
                    onReady: onReady
                )
            }
        }
    }

    func disconnectWebSocket() {
        socketLock.lock()
        socketGeneration += 1
        socketToken = nil
        socketHandler = nil
        reconnectAttempt = 0
        let oldSocket = webSocket
        let oldSession = socketSession
        webSocket = nil
        socketSession = nil
        socketLock.unlock()
        oldSocket?.cancel(with: .goingAway, reason: nil)
        oldSession?.invalidateAndCancel()
    }
}

private struct AvatarBody: Encodable {
    let avatar: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let avatar {
            try container.encode(avatar, forKey: .avatar)
        } else {
            try container.encodeNil(forKey: .avatar)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case avatar
    }
}

private struct RemovedResponse: Decodable {
    let removed: Bool
}

private struct JoinedServerResponse: Decodable {
    let serverID: Int64
    let joined: Bool?
    let left: Bool?

    enum CodingKeys: String, CodingKey {
        case serverID = "server_id"
        case joined, left
    }
}

enum SessionStore {
    private static let service = "app.aether.chat"
    private static let account = "session-token"

    static func save(token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
