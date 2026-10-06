import Foundation

struct ChatUser: Codable {
    let id: Int64
    let username: String
    let avatar: String?
    let isOwner: Bool
    let isOnline: Bool
    let lastSeenAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, username, avatar
        case isOwner = "is_owner"
        case isOnline = "online"
        case lastSeenAt = "last_seen_at"
    }

    init(
        id: Int64,
        username: String,
        avatar: String? = nil,
        isOwner: Bool = false,
        isOnline: Bool = false,
        lastSeenAt: Date? = nil
    ) {
        self.id = id
        self.username = username
        self.avatar = avatar
        self.isOwner = isOwner
        self.isOnline = isOnline
        self.lastSeenAt = lastSeenAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int64.self, forKey: .id)
        username = try values.decode(String.self, forKey: .username)
        avatar = try values.decodeIfPresent(String.self, forKey: .avatar)
        isOwner = try values.decodeIfPresent(Bool.self, forKey: .isOwner) ?? false
        isOnline = try values.decodeIfPresent(Bool.self, forKey: .isOnline) ?? false
        lastSeenAt = try values.decodeIfPresent(Date.self, forKey: .lastSeenAt)
    }
}

struct Channel: Codable {
    let id: Int64
    let name: String
    let description: String
    let memberCount: Int
    let serverID: Int64?
    let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case memberCount = "member_count"
        case serverID = "server_id"
        case unreadCount = "unread_count"
    }

    init(id: Int64, name: String, description: String, memberCount: Int = 0, serverID: Int64? = nil, unreadCount: Int = 0) {
        self.id = id
        self.name = name
        self.description = description
        self.memberCount = memberCount
        self.serverID = serverID
        self.unreadCount = unreadCount
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int64.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        description = try values.decode(String.self, forKey: .description)
        memberCount = try values.decodeIfPresent(Int.self, forKey: .memberCount) ?? 0
        serverID = try values.decodeIfPresent(Int64.self, forKey: .serverID)
        unreadCount = try values.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
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
    let imageData: String?

    enum CodingKeys: String, CodingKey {
        case id, username, content, avatar
        case channelID = "channel_id"
        case conversationID = "conversation_id"
        case userID = "user_id"
        case createdAt = "created_at"
        case imageData = "image_data"
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
    let lastMessage: DirectMessagePreview?
    let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case id, user
        case createdAt = "created_at"
        case lastMessage = "last_message"
        case unreadCount = "unread_count"
    }

    init(
        id: Int64,
        user: ChatUser,
        createdAt: Date = Date(),
        lastMessage: DirectMessagePreview? = nil,
        unreadCount: Int = 0
    ) {
        self.id = id
        self.user = user
        self.createdAt = createdAt
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int64.self, forKey: .id)
        user = try values.decode(ChatUser.self, forKey: .user)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        lastMessage = try values.decodeIfPresent(DirectMessagePreview.self, forKey: .lastMessage)
        unreadCount = try values.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
    }
}

struct DirectMessagePreview: Decodable {
    let id: Int64
    let userID: Int64
    let content: String
    let createdAt: Date
    let imageAvailable: Bool

    enum CodingKeys: String, CodingKey {
        case id, content
        case userID = "user_id"
        case createdAt = "created_at"
        case imageAvailable = "image_available"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int64.self, forKey: .id)
        userID = try values.decode(Int64.self, forKey: .userID)
        content = try values.decode(String.self, forKey: .content)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        imageAvailable = try values.decodeIfPresent(Bool.self, forKey: .imageAvailable) ?? false
    }
}

struct MessageSearchResult: Decodable {
    let scope: String
    let roomID: Int64
    let messageID: Int64
    let title: String
    let username: String
    let content: String
    let imageAvailable: Bool
    let createdAt: Date
    let serverID: Int64?
    let channelName: String?

    enum CodingKeys: String, CodingKey {
        case scope, title, username, content
        case roomID = "room_id"
        case messageID = "message_id"
        case imageAvailable = "image_available"
        case createdAt = "created_at"
        case serverID = "server_id"
        case channelName = "channel_name"
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
