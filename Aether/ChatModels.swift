import Foundation

struct ChatUser: Codable {
    let id: Int64
    let username: String
}

struct Channel: Codable {
    let id: Int64
    let name: String
    let description: String
    let memberCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case memberCount = "member_count"
    }
}

struct ChatMessage: Codable {
    let id: Int64
    let channelID: Int64
    let userID: Int64
    let username: String
    let content: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, username, content
        case channelID = "channel_id"
        case userID = "user_id"
        case createdAt = "created_at"
    }
}

struct AuthResponse: Decodable {
    let token: String
    let user: ChatUser
}

struct UserResponse: Decodable {
    let user: ChatUser
}

struct ChannelsResponse: Decodable {
    let channels: [Channel]
}

struct MessagesResponse: Decodable {
    let messages: [ChatMessage]
}

struct MessageResponse: Decodable {
    let message: ChatMessage
}

struct APIErrorResponse: Decodable {
    let error: String
}

struct SocketEvent: Decodable {
    let type: String
    let message: ChatMessage?
}

enum ChatAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server(String)
    case connection(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "The server address is not configured yet."
        case .invalidResponse: return "The server returned an unexpected response."
        case .server(let message): return message
        case .connection(let message): return message
        }
    }
}

extension KeyedDecodingContainer {
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        let valueDecoder = try superDecoder(forKey: key)
        let value = try valueDecoder.singleValueContainer()
        if let number = try? value.decode(Int64.self) {
            return number
        }
        if let string = try? value.decode(String.self), let number = Int64(string) {
            return number
        }
        throw DecodingError.typeMismatch(
            Int64.self,
            DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Expected an integer ID.")
        )
    }
}
