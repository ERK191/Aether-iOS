import Foundation

struct ChatUser: Codable {
    let id: Int64
    let username: String
    let avatar: String?
    let isOwner: Bool

    enum CodingKeys: String, CodingKey {
        case id, username, avatar
        case isOwner = "is_owner"
    }

    init(id: Int64, username: String, avatar: String? = nil, isOwner: Bool = false) {
        self.id = id
        self.username = username
        self.avatar = avatar
        self.isOwner = isOwner
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int64.self, forKey: .id)
        username = try values.decode(String.self, forKey: .username)
        avatar = try values.decodeIfPresent(String.self, forKey: .avatar)
        isOwner = try values.decodeIfPresent(Bool.self, forKey: .isOwner) ?? false
    }
}

struct Channel: Codable {
    let id: Int64
    let name: String
    let description: String
    let memberCount: Int
    let serverID: Int64?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case memberCount = "member_count"
        case serverID = "server_id"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int64.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        description = try values.decode(String.self, forKey: .description)
        memberCount = try values.decodeIfPresent(Int.self, forKey: .memberCount) ?? 0
        serverID = try values.decodeIfPresent(Int64.self, forKey: .serverID)
    }
}

struct ChatMessage: Codable {
    let id: Int64
    let channelID: Int64?
    let conversationID: Int64?
    let userID: Int64
    let username: String
    let content: String
    let createdAt: Date
    let avatar: String?

    enum CodingKeys: String, CodingKey {
        case id, username, content, avatar
        case channelID = "channel_id"
        case conversationID = "conversation_id"
        case userID = "user_id"
        case createdAt = "created_at"
    }
}

struct AetherServer: Codable {
    let id: Int64
    let name: String
    let description: String
    let ownerID: Int64
    let createdAt: Date
    let memberCount: Int
    let isMember: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case ownerID = "owner_id"
        case createdAt = "created_at"
        case memberCount = "member_count"
        case isMember = "is_member"
    }
}

struct FriendEntry: Decodable {
    let user: ChatUser
    let since: Date
}

struct FriendRequest: Decodable {
    let id: Int64
    let status: String
    let direction: String
    let user: ChatUser
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status, direction, user
        case createdAt = "created_at"
    }
}

struct DirectConversation: Decodable {
    let id: Int64
    let user: ChatUser
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, user
        case createdAt = "created_at"
    }

    init(id: Int64, user: ChatUser, createdAt: Date = Date()) {
        self.id = id
        self.user = user
        self.createdAt = createdAt
    }
}

struct UserSearchResult: Decodable {
    let id: Int64
    let username: String
    let avatar: String?
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

struct UserSearchResponse: Decodable {
    let users: [UserSearchResult]
}

struct FriendsResponse: Decodable {
    let friends: [FriendEntry]
}

struct FriendRequestsResponse: Decodable {
    let requests: [FriendRequest]
}

struct ConversationsResponse: Decodable {
    let conversations: [DirectConversation]
}

struct ServersResponse: Decodable {
    let servers: [AetherServer]
}

struct ServerResponse: Decodable {
    let server: AetherServer
}

struct ServerChannelsResponse: Decodable {
    let channels: [Channel]
}

struct FriendRequestResponse: Decodable {
    let request: FriendRequestRecord
}

struct FriendRequestRecord: Decodable {
    let id: Int64
    let status: String
    let requesterID: Int64?
    let recipientID: Int64?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status
        case requesterID = "requester_id"
        case recipientID = "recipient_id"
        case createdAt = "created_at"
    }
}

struct ConversationResponse: Decodable {
    let conversation: ConversationRecord
}

struct ConversationRecord: Decodable {
    let id: Int64
    let userID: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
    }
}

struct ServerCreateResponse: Decodable {
    let server: AetherServer
    let channels: [Channel]
}

struct DeleteAccountResponse: Decodable {
    let deleted: Bool
}

struct OwnerAccountsResponse: Decodable {
    let users: [OwnerAccount]
}

struct OwnerAccount: Decodable {
    let id: Int64
    let username: String
    let isBanned: Bool
    let isTestAccount: Bool

    enum CodingKeys: String, CodingKey {
        case id, username
        case isBanned = "is_banned"
        case isTestAccount = "is_test_account"
    }
}

struct OwnerAccountResponse: Decodable {
    let user: OwnerAccount
}

struct ServerMembersResponse: Decodable {
    let members: [ServerMember]
}

struct KickMemberResponse: Decodable {
    let kicked: Bool
    let userID: Int64

    enum CodingKeys: String, CodingKey {
        case kicked
        case userID = "user_id"
    }
}

struct ServerMember: Decodable {
    let user: ChatUser
    let role: String
    let joinedAt: Date

    enum CodingKeys: String, CodingKey {
        case user, role
        case joinedAt = "joined_at"
    }
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

    func decodeIfPresent(_ type: Int64.Type, forKey key: Key) throws -> Int64? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return try decode(type, forKey: key)
    }
}
