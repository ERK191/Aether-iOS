import UIKit

enum CommunityPage: Equatable {
    case conversations
    case friends
    case requests
    case discoverServers
    case servers
    case addServer
    case serverChannels
    case settings
    case ownerTools
    case ownerServerMembers
}

final class CommunityViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let page: CommunityPage
    private var user: ChatUser
    private let token: String
    private let server: AetherServer?
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var rowActions: [() -> Void] = []

    init(page: CommunityPage, user: ChatUser, token: String, server: AetherServer? = nil) {
        self.page = page
        self.user = user
        self.token = token
        self.server = server
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AetherTheme.background
        title = pageTitle
        navigationController?.setNavigationBarHidden(false, animated: false)
        navigationController?.navigationBar.tintColor = AetherTheme.cyan
        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithOpaqueBackground()
        navigationAppearance.backgroundColor = AetherTheme.background
        navigationAppearance.titleTextAttributes = [
            .foregroundColor: AetherTheme.text,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        navigationController?.navigationBar.standardAppearance = navigationAppearance
        if #available(iOS 15.0, *) {
            navigationController?.navigationBar.scrollEdgeAppearance = navigationAppearance
        }
        buildLayout()
        loadPage()
        if page == .friends {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: AetherLanguage.string("Add"),
                style: .plain,
                target: self,
                action: #selector(addFriend)
            )
        }
    }

    private var pageTitle: String {
        switch page {
        case .conversations: return AetherLanguage.string("Direct Messages")
        case .friends: return AetherLanguage.string("Friends")
        case .requests: return AetherLanguage.string("Friend Requests")
        case .discoverServers: return AetherLanguage.string("Discover Servers")
        case .servers: return AetherLanguage.string("Your Servers")
        case .addServer: return AetherLanguage.string("Create a Server")
        case .serverChannels: return server?.name ?? AetherLanguage.string("Channels")
        case .settings: return AetherLanguage.string("Account Settings")
        case .ownerTools: return AetherLanguage.string("Owner Tools")
        case .ownerServerMembers: return server?.name ?? AetherLanguage.string("Server Members")
        }
    }

    private func buildLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 10
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 18),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -18),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 18),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24)
        ])
    }

    private func loadPage() {
        switch page {
        case .conversations:
            loadConversations()
        case .friends:
            loadFriends()
        case .requests:
            loadRequests()
        case .discoverServers:
            loadDiscoverableServers()
        case .servers:
            loadServers()
        case .addServer:
            addRow(
                title: AetherLanguage.string("Create a server"),
                subtitle: AetherLanguage.string("Start a new community with a general chat channel."),
                symbol: "plus.circle.fill",
                action: promptCreateServer
            )
        case .serverChannels:
            loadServerChannels()
        case .settings:
            loadSettings()
        case .ownerTools:
            loadOwnerTools()
        case .ownerServerMembers:
            loadOwnerServerMembers()
        }
    }

    private func resetRows() {
        rowActions.removeAll()
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
    }

    private func addHeading(_ text: String) {
        let label = UILabel()
        label.text = text.uppercased()
        label.textColor = AetherTheme.secondary
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.accessibilityTraits = .header
        contentStack.addArrangedSubview(label)
        label.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
    }

    private func addRow(
        title: String,
        subtitle: String? = nil,
        symbol: String = "circle.fill",
        action: @escaping () -> Void
    ) {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = AetherTheme.panel
        AetherTheme.surface(button, radius: 17)
        button.contentHorizontalAlignment = .leading
        button.tag = rowActions.count
        rowActions.append(action)
        button.addTarget(self, action: #selector(performRowAction(_:)), for: .touchUpInside)

        let iconTile = UIView()
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.backgroundColor = AetherTheme.elevated
        AetherTheme.rounded(iconTile, radius: 12)
        button.addSubview(iconTile)

        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = AetherTheme.cyan
        icon.contentMode = .scaleAspectFit
        iconTile.addSubview(icon)

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = AetherTheme.muted
        chevron.contentMode = .scaleAspectFit
        button.addSubview(chevron)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.textColor = AetherTheme.text
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.numberOfLines = 1
        button.addSubview(titleLabel)

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = subtitle
        subtitleLabel.textColor = AetherTheme.secondary
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.numberOfLines = 2
        subtitleLabel.isHidden = subtitle == nil
        button.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            iconTile.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 13),
            iconTile.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 42),
            iconTile.heightAnchor.constraint(equalToConstant: 42),
            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            chevron.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -14),
            chevron.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 10),
            chevron.heightAnchor.constraint(equalToConstant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: button.topAnchor, constant: subtitle == nil ? 16 : 12),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -11),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: subtitle == nil ? 56 : 72)
        ])
        contentStack.addArrangedSubview(button)
    }

    @objc private func performRowAction(_ sender: UIButton) {
        guard rowActions.indices.contains(sender.tag) else { return }
        rowActions[sender.tag]()
    }

    private func loadConversations() {
        ChatService.shared.conversations(token: token) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.resetRows()
                switch result {
                case .success(let conversations):
                    self.addRow(
                        title: AetherLanguage.string("Find friends"),
                        subtitle: AetherLanguage.string("Add people to start a private conversation."),
                        symbol: "person.badge.plus",
                        action: self.addFriend
                    )
                    if conversations.isEmpty {
                        self.addEmptyState(AetherLanguage.string("No conversations yet. Add a friend to get started."))
                    }
                    for conversation in conversations {
                        self.addRow(
                            title: conversation.user.username,
                            subtitle: AetherLanguage.string("Tap to open your conversation"),
                            symbol: "person.crop.circle.fill",
                            action: { [weak self] in self?.openConversation(conversation) }
                        )
                    }
                case .failure(let error):
                    self.addError(error)
                }
            }
        }
    }

    private func loadFriends() {
        ChatService.shared.friends(token: token) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.resetRows()
                switch result {
                case .success(let friends):
                    self.addRow(
                        title: AetherLanguage.string("Add a friend"),
                        subtitle: AetherLanguage.string("Search by username."),
                        symbol: "person.badge.plus",
                        action: self.addFriend
                    )
                    self.addRow(
                        title: AetherLanguage.string("Friend requests"),
                        symbol: "envelope.badge",
                        action: { [weak self] in self?.push(.requests) }
                    )
                    if friends.isEmpty {
                        self.addEmptyState(AetherLanguage.string("Your friends will appear here."))
                    }
                    for entry in friends {
                        self.addRow(
                            title: entry.user.username,
                            subtitle: AetherLanguage.string("Tap to message · hold for options"),
                            symbol: "person.crop.circle.fill",
                            action: { [weak self] in self?.showFriendActions(entry.user) }
                        )
                    }
                case .failure(let error):
                    self.addError(error)
                }
            }
        }
    }

    private func loadRequests() {
        ChatService.shared.friendRequests(token: token) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.resetRows()
                switch result {
                case .success(let requests):
                    let incoming = requests.filter { $0.direction == "incoming" && $0.status == "pending" }
                    let outgoing = requests.filter { $0.direction == "outgoing" }
                    self.addHeading(AetherLanguage.string("Incoming"))
                    if incoming.isEmpty {
                        self.addEmptyState(AetherLanguage.string("No incoming requests."))
                    }
                    incoming.forEach { request in
                        self.addRow(
                            title: request.user.username,
                            subtitle: AetherLanguage.string("Accept or decline this request."),
                            symbol: "person.crop.circle.badge.questionmark",
                            action: { [weak self] in self?.showRequestActions(request) }
                        )
                    }
                    if !outgoing.isEmpty {
                        self.addHeading(AetherLanguage.string("Sent"))
                        outgoing.forEach { request in
                            self.addRow(
                                title: request.user.username,
                                subtitle: "\(AetherLanguage.string("Request")): \(AetherLanguage.string(request.status))",
                                symbol: "paperplane"
                            ) {}
                        }
                    }
                case .failure(let error):
                    self.addError(error)
                }
            }
        }
    }

    private func loadDiscoverableServers() {
        ChatService.shared.servers(token: token) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.resetRows()
                switch result {
                case .success(let servers):
                    self.addRow(
                        title: AetherLanguage.string("Create a server"),
                        subtitle: AetherLanguage.string("Build a new place for your community."),
                        symbol: "plus.circle.fill",
                        action: { [weak self] in self?.push(.addServer) }
                    )
                    let discoverable = servers.filter { !$0.isMember }
                    if discoverable.isEmpty {
                        self.addEmptyState(AetherLanguage.string("No other public servers are available yet."))
                    }
                    discoverable.forEach { server in
                        self.addRow(
                            title: server.name,
                            subtitle: "\(server.memberCount) \(AetherLanguage.string("members")) · \(server.description)",
                            symbol: "globe.americas.fill",
                            action: { [weak self] in self?.showServerActions(server) }
                        )
                    }
                case .failure(let error):
                    self.addError(error)
                }
            }
        }
    }

    private func loadServers() {
        ChatService.shared.servers(token: token) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.resetRows()
                switch result {
                case .success(let servers):
                    let joined = servers.filter(\.isMember)
                    self.addRow(
                        title: AetherLanguage.string("Discover servers"),
                        subtitle: AetherLanguage.string("Find a community to join."),
                        symbol: "safari.fill",
                        action: { [weak self] in self?.push(.discoverServers) }
                    )
                    if joined.isEmpty {
                        self.addEmptyState(AetherLanguage.string("Join or create a server to see it here."))
                    }
                    joined.forEach { server in
                        self.addRow(
                            title: server.name,
                            subtitle: "\(server.memberCount) \(AetherLanguage.string("members"))",
                            symbol: "server.rack",
                            action: { [weak self] in self?.openServer(server) }
                        )
                    }
                case .failure(let error):
                    self.addError(error)
                }
            }
        }
    }

    private func loadServerChannels() {
        guard let server else {
            addEmptyState(AetherLanguage.string("Server not found."))
            return
        }
        ChatService.shared.serverChannels(serverID: server.id, token: token) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.resetRows()
                switch result {
                case .success(let channels):
                    self.addRow(
                        title: server.ownerID == self.user.id
                            ? AetherLanguage.string("Delete Server")
                            : AetherLanguage.string("Leave Server"),
                        subtitle: server.ownerID == self.user.id
                            ? AetherLanguage.string("Permanently remove this server and its channels.")
                            : AetherLanguage.string("Leave this community."),
                        symbol: "rectangle.portrait.and.arrow.right",
                        action: { [weak self] in self?.confirmLeaveOrDelete(server) }
                    )
                    if channels.isEmpty {
                        self.addEmptyState(AetherLanguage.string("This server has no channels yet."))
                    }
                    channels.forEach { channel in
                        self.addRow(
                            title: "# \(channel.name)",
                            subtitle: channel.description,
                            symbol: "number",
                            action: { [weak self] in self?.openChannel(channel) }
                        )
                    }
                case .failure(let error):
                    self.addError(error)
                }
            }
        }
    }

    private func loadSettings() {
        let avatarText = user.avatar == nil
            ? AetherLanguage.string("Tap to choose a profile photo.")
            : AetherLanguage.string("Tap to change your profile photo.")
        addRow(title: user.username, subtitle: avatarText, symbol: "person.crop.circle", action: pickAvatar)
        if user.avatar != nil {
            addRow(
                title: AetherLanguage.string("Remove profile photo"),
                symbol: "person.crop.circle.badge.xmark",
                action: removeAvatar
            )
        }
        addRow(
            title: AetherLanguage.string("Language"),
            subtitle: "\(AetherLanguage.string("Current")): \(AetherLanguage.string(AetherLanguage.currentName))",
            symbol: "globe",
            action: chooseLanguage
        )
        addRow(
            title: AetherLanguage.string("Message text size"),
            subtitle: "\(AetherLanguage.string("Current")): \(AetherLanguage.textSizeName)",
            symbol: "textformat.size",
            action: chooseTextSize
        )
        addRow(
            title: AetherLanguage.string("Your servers"),
            symbol: "server.rack",
            action: { [weak self] in self?.push(.servers) }
        )
        if user.isOwner {
            addRow(
                title: AetherLanguage.string("Owner Tools"),
                subtitle: AetherLanguage.string("Manage accounts, test users, and server members."),
                symbol: "checkmark.shield.fill",
                action: { [weak self] in self?.push(.ownerTools) }
            )
        }
        addRow(
            title: AetherLanguage.string("Sign out"),
            symbol: "rectangle.portrait.and.arrow.right",
            action: signOut
        )
        if !user.isOwner {
            addRow(
                title: AetherLanguage.string("Delete account"),
                subtitle: AetherLanguage.string("Permanently delete your account and messages."),
                symbol: "trash",
                action: confirmDeleteAccount
            )
        }
    }

    private func loadOwnerTools() {
        guard user.isOwner else {
            addError(ChatAPIError.server(AetherLanguage.string("Owner access is required.")))
            return
        }
        addHeading(AetherLanguage.string("Accounts"))
        addRow(
            title: AetherLanguage.string("Create a test account"),
            subtitle: AetherLanguage.string("Add a non-owner account for testing the app."),
            symbol: "person.badge.plus",
            action: promptCreateTestAccount
        )
        addRow(
            title: AetherLanguage.string("Find and ban a user"),
            subtitle: AetherLanguage.string("Search accounts and ban or restore access."),
            symbol: "person.crop.circle.badge.xmark",
            action: promptOwnerUserSearch
        )
        addHeading(AetherLanguage.string("Server moderation"))
        ChatService.shared.servers(token: token) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let servers):
                    if servers.isEmpty {
                        self.addEmptyState(AetherLanguage.string("No servers are available to moderate."))
                    }
                    servers.forEach { server in
                        self.addRow(
                            title: server.name,
                            subtitle: "\(server.memberCount) \(AetherLanguage.string("members"))",
                            symbol: "person.3.fill",
                            action: { [weak self] in self?.push(.ownerServerMembers, server: server) }
                        )
                    }
                case .failure(let error):
                    self.addError(error)
                }
            }
        }
    }

    private func loadOwnerServerMembers() {
        guard user.isOwner, let server else {
            addError(ChatAPIError.server(AetherLanguage.string("Owner access is required.")))
            return
        }
        ChatService.shared.serverMembers(serverID: server.id, token: token) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.resetRows()
                switch result {
                case .success(let members):
                    if members.isEmpty {
                        self.addEmptyState(AetherLanguage.string("This server has no members."))
                    }
                    members.forEach { member in
                        let isServerOwner = member.role == "owner"
                        self.addRow(
                            title: member.user.username,
                            subtitle: isServerOwner
                                ? AetherLanguage.string("Server owner")
                                : AetherLanguage.string("Tap to kick this member from the server."),
                            symbol: isServerOwner ? "crown.fill" : "person.crop.circle",
                            action: {
                                guard !isServerOwner else { return }
                                self.confirmKick(member.user, from: server)
                            }
                        )
                    }
                case .failure(let error):
                    self.addError(error)
                }
            }
        }
    }

    private func promptCreateTestAccount() {
        let prompt = UIAlertController(
            title: AetherLanguage.string("Create a test account"),
            message: AetherLanguage.string("Use a unique username and password with at least 8 characters."),
            preferredStyle: .alert
        )
        prompt.addTextField {
            $0.placeholder = AetherLanguage.string("Username")
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
        }
        prompt.addTextField {
            $0.placeholder = AetherLanguage.string("Password")
            $0.isSecureTextEntry = true
        }
        prompt.addAction(UIAlertAction(title: AetherLanguage.string("Cancel"), style: .cancel))
        prompt.addAction(UIAlertAction(title: AetherLanguage.string("Create"), style: .default) { [weak self, weak prompt] _ in
            guard let self else { return }
            let fields = prompt?.textFields ?? []
            let username = fields.first?.text ?? ""
            let password = fields.count > 1 ? fields[1].text ?? "" : ""
            ChatService.shared.createTestAccount(username: username, password: password, token: self.token) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let account):
                        self.showNotice("\(AetherLanguage.string("Test account created")): \(account.username)")
                    case .failure(let error):
                        self.showNotice(error.localizedDescription)
                    }
                }
            }
        })
        present(prompt, animated: true)
    }

    private func promptOwnerUserSearch() {
        let prompt = UIAlertController(
            title: AetherLanguage.string("Find a user"),
            message: AetherLanguage.string("Enter at least two characters of their username."),
            preferredStyle: .alert
        )
        prompt.addTextField {
            $0.placeholder = AetherLanguage.string("Username")
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
        }
        prompt.addAction(UIAlertAction(title: AetherLanguage.string("Cancel"), style: .cancel))
        prompt.addAction(UIAlertAction(title: AetherLanguage.string("Search"), style: .default) { [weak self, weak prompt] _ in
            guard let self else { return }
            let query = prompt?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard query.count >= 2 else {
                self.showNotice(AetherLanguage.string("Enter at least two characters."))
                return
            }
            ChatService.shared.ownerUsers(query: query, token: self.token) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let users):
                        self.showOwnerUsers(users)
                    case .failure(let error):
                        self.showNotice(error.localizedDescription)
                    }
                }
            }
        })
        present(prompt, animated: true)
    }

    private func showOwnerUsers(_ users: [OwnerAccount]) {
        guard !users.isEmpty else {
            showNotice(AetherLanguage.string("No users found."))
            return
        }
        let choices = UIAlertController(
            title: AetherLanguage.string("Choose an account"),
            message: AetherLanguage.string("Banning blocks sign-in and removes active chat sessions."),
            preferredStyle: .actionSheet
        )
        users.forEach { account in
            let status = account.isBanned
                ? AetherLanguage.string("Banned")
                : (account.isTestAccount ? AetherLanguage.string("Test account") : AetherLanguage.string("Active"))
            choices.addAction(UIAlertAction(title: "\(account.username) · \(status)", style: .default) { [weak self] _ in
                self?.confirmAccountModeration(account)
            })
        }
        choices.addAction(UIAlertAction(title: AetherLanguage.string("Cancel"), style: .cancel))
        present(choices, animated: true)
    }

    private func confirmAccountModeration(_ account: OwnerAccount) {
        let isBanning = !account.isBanned
        let confirmation = UIAlertController(
            title: isBanning
                ? AetherLanguage.string("Ban this account?")
                : AetherLanguage.string("Restore this account?"),
            message: isBanning
                ? AetherLanguage.string("This immediately blocks sign-in and ends active chat sessions.")
                : AetherLanguage.string("This allows the user to sign in again."),
            preferredStyle: .alert
        )
        if isBanning {
            confirmation.addTextField {
                $0.placeholder = AetherLanguage.string("Reason (optional)")
            }
        }
        confirmation.addAction(UIAlertAction(title: AetherLanguage.string("Cancel"), style: .cancel))
        confirmation.addAction(UIAlertAction(
            title: isBanning ? AetherLanguage.string("Ban") : AetherLanguage.string("Unban"),
            style: .destructive
        ) { [weak self, weak confirmation] _ in
            guard let self else { return }
            let reason = confirmation?.textFields?.first?.text ?? ""
            ChatService.shared.setUserBanned(
                userID: account.id,
                banned: isBanning,
                reason: reason,
                token: self.token
            ) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self.showNotice(AetherLanguage.string(isBanning ? "Account banned." : "Account unbanned."))
                    case .failure(let error):
                        self.showNotice(error.localizedDescription)
                    }
                }
            }
        })
        present(confirmation, animated: true)
    }

    private func confirmKick(_ member: ChatUser, from server: AetherServer) {
        let confirmation = UIAlertController(
            title: AetherLanguage.string("Kick member?"),
            message: "\(AetherLanguage.string("Remove")) \(member.username) \(AetherLanguage.string("from")) \(server.name)?",
            preferredStyle: .alert
        )
        confirmation.addAction(UIAlertAction(title: AetherLanguage.string("Cancel"), style: .cancel))
        confirmation.addAction(UIAlertAction(title: AetherLanguage.string("Kick"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            ChatService.shared.kickServerMember(serverID: server.id, userID: member.id, token: self.token) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self.loadOwnerServerMembers()
                    case .failure(let error):
                        self.showNotice(error.localizedDescription)
                    }
                }
            }
        })
        present(confirmation, animated: true)
    }

    private func addEmptyState(_ text: String) {
        let label = UILabel()
        label.text = text
        label.textColor = AetherTheme.secondary
        label.font = .systemFont(ofSize: 14)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.backgroundColor = AetherTheme.panel
        AetherTheme.surface(label, radius: 18)
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(label)
        label.heightAnchor.constraint(greaterThanOrEqualToConstant: 92).isActive = true
    }

    private func addError(_ error: Error) {
        addEmptyState(error.localizedDescription)
    }

    private func push(_ page: CommunityPage, server: AetherServer? = nil) {
        navigationController?.pushViewController(
            CommunityViewController(page: page, user: user, token: token, server: server),
            animated: true
        )
    }

    private func openConversation(_ conversation: DirectConversation) {
        navigationController?.pushViewController(
            ChatViewController(user: user, token: token, directConversation: conversation),
            animated: true
        )
    }

    private func openServer(_ server: AetherServer) {
        push(.serverChannels, server: server)
    }

    private func openChannel(_ channel: Channel) {
        navigationController?.pushViewController(
            ChatViewController(user: user, token: token, serverChannel: channel),
            animated: true
        )
    }

    @objc private func addFriend() {
        let prompt = UIAlertController(
            title: AetherLanguage.string("Add a friend"),
            message: AetherLanguage.string("Enter at least two characters of their username."),
            preferredStyle: .alert
        )
        prompt.addTextField {
            $0.placeholder = AetherLanguage.string("Username")
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
        }
        prompt.addAction(UIAlertAction(title: AetherLanguage.string("Cancel"), style: .cancel))
        prompt.addAction(UIAlertAction(title: AetherLanguage.string("Search"), style: .default) { [weak self, weak prompt] _ in
            guard let self, let query = prompt?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  query.count >= 2 else {
                self?.showNotice(AetherLanguage.string("Enter at least two characters."))
                return
            }
            ChatService.shared.users(query: query, token: self.token) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch result {
                    case .success(let users):
                        self.showSearchResults(users)
                    case .failure(let error):
                        self.showNotice(error.localizedDescription)
                    }
                }
            }
        })
        present(prompt, animated: true)
    }

    private func showSearchResults(_ users: [UserSearchResult]) {
        guard !users.isEmpty else {
            showNotice(AetherLanguage.string("No users found."))
            return
        }
        let choices = UIAlertController(title: AetherLanguage.string("People"), message: nil, preferredStyle: .actionSheet)
        users.forEach { candidate in
            choices.addAction(UIAlertAction(title: candidate.username, style: .default) { [weak self] _ in
                guard let self else { return }
                ChatService.shared.sendFriendRequest(userID: candidate.id, token: self.token) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            self.showNotice(AetherLanguage.string("Friend request sent."))
                        case .failure(let error):
                            self.showNotice(error.localizedDescription)
                        }
                    }
                }
            })
        }
        choices.addAction(UIAlertAction(title: AetherLanguage.string("Cancel"), style: .cancel))
        present(choices, animated: true)
    }

    private func showFriendActions(_ friend: ChatUser) {
        let choices = UIAlertController(title: friend.username, message: nil, preferredStyle: .actionSheet)
        choices.addAction(UIAlertAction(title: AetherLanguage.string("Message"), style: .default) { [weak self] _ in
            self?.startConversation(with: friend)
        })
        choices.addAction(UIAlertAction(title: AetherLanguage.string("Remove Friend"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            ChatService.shared.removeFriend(userID: friend.id, token: self.token) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success: self.loadFriends()
                    case .failure(let error): self.showNotice(error.localizedDescription)
                    }
                }
            }
        })
        choices.addAction(UIAlertAction(title: AetherLanguage.string("Cancel"), style: .cancel))
        present(choices, animated: true)
    }

    private func startConversation(with friend: ChatUser) {
        ChatService.shared.createConversation(userID: friend.id, token: token) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let record):
                    self.openConversation(DirectConversation(id: record.id, user: friend))
                case .failure(let error):
                    self.showNotice(error.localizedDescription)
                }
            }
        }
    }

    private func showRequestActions(_ request: FriendRequest) {
        let choices = UIAlertController(title: request.user.username, message: nil, preferredStyle: .actionSheet)
        choices.addAction(UIAlertAction(title: AetherLanguage.string("Accept"), style: .default) { [weak self] _ in
            self?.respond(to: request, accept: true)
        })
        choices.addAction(UIAlertAction(title: AetherLanguage.string("Decline"), style: .destructive) { [weak self] _ in
            self?.respond(to: request, accept: false)
        })
        choices.addAction(UIAlertAction(title: AetherLanguage.string("Cancel"), style: .cancel))
        present(choices, animated: true)
    }

    private func respond(to request: FriendRequest, accept: Bool) {
        ChatService.shared.respondToFriendRequest(requestID: request.id, accept: accept, token: token) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success: self.loadRequests()
                case .failure(let error): self.showNotice(error.localizedDescription)
                }
            }
        }
    }

    private func showServerActions(_ server: AetherServer) {
        let choices = UIAlertController(title: server.name, message: server.description, preferredStyle: .actionSheet)
        choices.addAction(UIAlertAction(title: AetherLanguage.string("Join Server"), style: .default) { [weak self] _ in
            guard let self else { return }
            ChatService.shared.joinServer(serverID: server.id, token: self.token) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success: self.openServer(server)
                    case .failure(let error): self.showNotice(error.localizedDescription)
                    }
                }
            }
        })
        choices.addAction(UIAlertAction(title: AetherLanguage.string("Cancel"), style: .cancel))
        present(choices, animated: true)
    }

    private func confirmLeaveOrDelete(_ server: AetherServer) {
        let isOwner = server.ownerID == user.id
        let title = isOwner ? AetherLanguage.string("Delete Server?") : AetherLanguage.string("Leave Server?")
        let message = isOwner
            ? AetherLanguage.string("This permanently deletes the server, channels, and messages.")
            : AetherLanguage.string("You will lose access to this server's channels.")
        let confirmation = UIAlertController(title: title, message: message, preferredStyle: .alert)
        confirmation.addAction(UIAlertAction(title: AetherLanguage.string("Cancel"), style: .cancel))
        confirmation.addAction(UIAlertAction(
            title: isOwner ? AetherLanguage.string("Delete Server") : AetherLanguage.string("Leave Server"),
            style: .destructive
        ) { [weak self] _ in
            guard let self else { return }
            let complete: (Result<Void, Error>) -> Void = { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success: self.navigationController?.popToRootViewController(animated: true)
                    case .failure(let error): self.showNotice(error.localizedDescription)
                    }
                }
            }
            if isOwner {
                ChatService.shared.deleteServer(serverID: server.id, token: self.token, completion: complete)
            } else {
                ChatService.shared.leaveServer(serverID: server.id, token: self.token, completion: complete)
            }
        })
        present(confirmation, animated: true)
    }

    private func promptCreateServer() {
        let prompt = UIAlertController(
            title: AetherLanguage.string("Create a Server"),
            message: AetherLanguage.string("Your new server starts with a #general channel."),
            preferredStyle: .alert
        )
        prompt.addTextField {
            $0.placeholder = AetherLanguage.string("Server name")
            $0.autocapitalizationType = .words
        }
        prompt.addTextField {
            $0.placeholder = AetherLanguage.string("Description (optional)")
        }
        prompt.addAction(UIAlertAction(title: AetherLanguage.string("Cancel"), style: .cancel))
        prompt.addAction(UIAlertAction(title: AetherLanguage.string("Create"), style: .default) { [weak self, weak prompt] _ in
            guard let self else { return }
            let fields = prompt?.textFields ?? []
            let name = fields.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let description = fields.count > 1 ? fields[1].text ?? "" : ""
            guard !name.isEmpty else {
                self.showNotice(AetherLanguage.string("Enter a server name."))
                return
            }
            ChatService.shared.createServer(name: name, description: description, token: self.token) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let response): self.openServer(response.server)
                    case .failure(let error): self.showNotice(error.localizedDescription)
                    }
                }
            }
        })
        present(prompt, animated: true)
    }

    private func pickAvatar() {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = self
        picker.allowsEditing = true
        present(picker, animated: true)
    }

    private func removeAvatar() {
        ChatService.shared.updateAvatar(dataURL: nil, token: token) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let updatedUser):
                    self?.user = updatedUser
                    self?.showNotice(AetherLanguage.string("Profile photo removed."))
                    self?.reloadVisiblePage()
                case .failure(let error):
                    self?.showNotice(error.localizedDescription)
                }
            }
        }
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)
        guard let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage),
              let jpeg = compressedJPEG(image, maximumBytes: 700_000) else {
            showNotice(AetherLanguage.string("That photo could not be prepared. Try a smaller image."))
            return
        }
        let dataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        ChatService.shared.updateAvatar(dataURL: dataURL, token: token) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let updatedUser):
                    self?.user = updatedUser
                    self?.showNotice(AetherLanguage.string("Profile photo updated."))
                    self?.reloadVisiblePage()
                case .failure(let error):
                    self?.showNotice(error.localizedDescription)
                }
            }
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    private func compressedJPEG(_ image: UIImage, maximumBytes: Int) -> Data? {
        var candidate = image
        for _ in 0..<5 {
            for quality in [0.82, 0.68, 0.54, 0.4] {
                if let data = candidate.jpegData(compressionQuality: quality), data.count <= maximumBytes {
                    return data
                }
            }
            let size = CGSize(width: candidate.size.width * 0.7, height: candidate.size.height * 0.7)
            let renderer = UIGraphicsImageRenderer(size: size)
            candidate = renderer.image { _ in candidate.draw(in: CGRect(origin: .zero, size: size)) }
        }
        return candidate.jpegData(compressionQuality: 0.35).flatMap { $0.count <= maximumBytes ? $0 : nil }
    }

    private func chooseLanguage() {
        let choices = UIAlertController(title: AetherLanguage.string("Language"), message: nil, preferredStyle: .actionSheet)
        choices.addAction(UIAlertAction(title: "English", style: .default) { [weak self] _ in
            AetherLanguage.set("en")
            self?.reloadVisiblePage()
        })
        choices.addAction(UIAlertAction(title: "Română", style: .default) { [weak self] _ in
            AetherLanguage.set("ro")
            self?.reloadVisiblePage()
        })
        choices.addAction(UIAlertAction(title: AetherLanguage.string("Cancel"), style: .cancel))
        present(choices, animated: true)
    }

    private func chooseTextSize() {
        let choices = UIAlertController(title: AetherLanguage.string("Message text size"), message: nil, preferredStyle: .actionSheet)
        ["Small", "Standard", "Large"].forEach { size in
            choices.addAction(UIAlertAction(title: AetherLanguage.string(size), style: .default) { [weak self] _ in
                let value: Double = size == "Small" ? 13 : (size == "Large" ? 18 : 15)
                UserDefaults.standard.set(value, forKey: "aether.messageFontSize")
                self?.reloadVisiblePage()
            })
        }
        choices.addAction(UIAlertAction(title: AetherLanguage.string("Cancel"), style: .cancel))
        present(choices, animated: true)
    }

    private func reloadVisiblePage() {
        resetRows()
        loadPage()
        title = pageTitle
    }

    private func signOut() {
        SessionStore.delete()
        ChatService.shared.disconnectWebSocket()
        navigationController?.setViewControllers([AuthViewController()], animated: true)
    }

    private func confirmDeleteAccount() {
        let confirm = UIAlertController(
            title: AetherLanguage.string("Delete your account?"),
            message: AetherLanguage.string("This permanently deletes your account, friendships, and messages. This cannot be undone."),
            preferredStyle: .alert
        )
        confirm.addAction(UIAlertAction(title: AetherLanguage.string("Cancel"), style: .cancel))
        confirm.addAction(UIAlertAction(title: AetherLanguage.string("Delete Account"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            ChatService.shared.deleteAccount(token: self.token) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success: self.signOut()
                    case .failure(let error): self.showNotice(error.localizedDescription)
                    }
                }
            }
        })
        present(confirm, animated: true)
    }

    private func showNotice(_ message: String) {
        let alert = UIAlertController(title: "Aether", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: AetherLanguage.string("OK"), style: .default))
        present(alert, animated: true)
    }
}

enum AetherLanguage {
    private static let languageKey = "aether.language"
    private static let sizeKey = "aether.messageFontSize"

    static var currentName: String {
        UserDefaults.standard.string(forKey: languageKey) == "ro" ? "Română" : "English"
    }

    static var textSizeName: String {
        let size = UserDefaults.standard.double(forKey: sizeKey)
        if size == 0 || size == 15 { return string("Standard") }
        return string(size < 15 ? "Small" : "Large")
    }

    static func set(_ language: String) {
        UserDefaults.standard.set(language, forKey: languageKey)
        NotificationCenter.default.post(name: .aetherLanguageDidChange, object: nil)
    }

    static func string(_ english: String) -> String {
        guard UserDefaults.standard.string(forKey: languageKey) == "ro" else { return english }
        return romanian[english] ?? english
    }

    private static let romanian: [String: String] = [
        "Add": "Adaugă",
        "Direct Messages": "Mesaje directe",
        "Friends": "Prieteni",
        "Friend Requests": "Cereri de prietenie",
        "Discover Servers": "Descoperă servere",
        "Your Servers": "Serverele tale",
        "Create a Server": "Creează un server",
        "Channels": "Canale",
        "Account Settings": "Setări cont",
        "Chats": "Conversații",
        "Communities": "Comunități",
        "Settings": "Setări",
        "AETHER COMMUNITY": "COMUNITATEA AETHER",
        "DIRECT MESSAGES": "MESAJE DIRECTE",
        "Aether private chat": "Conversație privată Aether",
        "Aether community": "Comunitatea Aether",
        "Community channel": "Canalul comunității",
        "Community chat": "Chatul comunității",
        "Search chats": "Caută conversații",
        "New message": "Mesaj nou",
        "No chats yet. Find a friend and say hello.": "Nu ai conversații. Găsește un prieten și salută-l.",
        "Start a conversation": "Începe o conversație",
        "Yesterday": "Ieri",
        "Back to chats": "Înapoi la conversații",
        "PRIVATE CONVERSATION": "CONVERSAȚIE PRIVATĂ",
        "SERVER CHANNEL": "CANAL DE SERVER",
        "COMMUNITY CHAT": "CHATUL COMUNITĂȚII",
        "Say hello to": "Salută-l pe",
        "Welcome to": "Bine ai venit în",
        "Your private conversation starts with your first message.": "Conversația privată începe cu primul mesaj.",
        "This channel is quiet for now. Send a message to get things started.": "Canalul este liniștit momentan. Trimite un mesaj pentru a începe.",
        "Choose a channel and start a conversation.": "Alege un canal și începe o conversație.",
        "Owner Tools": "Instrumente proprietar",
        "Server Members": "Membrii serverului",
        "Accounts": "Conturi",
        "Create a test account": "Creează un cont de test",
        "Add a non-owner account for testing the app.": "Adaugă un cont fără privilegii pentru a testa aplicația.",
        "Use a unique username and password with at least 8 characters.": "Folosește un nume unic și o parolă de cel puțin 8 caractere.",
        "Test account created": "Cont de test creat",
        "Find and ban a user": "Găsește și blochează un utilizator",
        "Search accounts and ban or restore access.": "Caută conturi și blochează sau restabilește accesul.",
        "Find a user": "Găsește un utilizator",
        "Choose an account": "Alege un cont",
        "Banning blocks sign-in and removes active chat sessions.": "Blocarea împiedică autentificarea și închide sesiunile active.",
        "Banned": "Blocat",
        "Test account": "Cont de test",
        "Active": "Activ",
        "Ban this account?": "Blochezi acest cont?",
        "Restore this account?": "Restabilești acest cont?",
        "This immediately blocks sign-in and ends active chat sessions.": "Blochează imediat autentificarea și închide sesiunile active.",
        "This allows the user to sign in again.": "Utilizatorul se poate autentifica din nou.",
        "Reason (optional)": "Motiv (opțional)",
        "Ban": "Blochează",
        "Unban": "Deblochează",
        "Account banned.": "Cont blocat.",
        "Account unbanned.": "Cont deblocat.",
        "Server moderation": "Moderarea serverelor",
        "No servers are available to moderate.": "Nu există servere de moderat.",
        "This server has no members.": "Acest server nu are membri.",
        "Server owner": "Proprietarul serverului",
        "Tap to kick this member from the server.": "Apasă pentru a elimina acest membru din server.",
        "Kick member?": "Elimini membrul?",
        "Remove": "Elimină",
        "from": "din",
        "Kick": "Elimină",
        "Owner access is required.": "Este necesar accesul proprietarului.",
        "Message": "Mesaj",
        "Aether home": "Acasă Aether",
        "Account settings": "Setări cont",
        "THE LOUNGE": "CLUBUL",
        "LIVE COMMUNITY": "COMUNITATE ACTIVĂ",
        "No messages yet.\nStart the conversation ✨": "Nu există mesaje.\nÎncepe conversația ✨",
        "Start a new community with a general chat channel.": "Începe o comunitate nouă cu un canal general.",
        "Find friends": "Găsește prieteni",
        "Add people to start a private conversation.": "Adaugă persoane pentru o conversație privată.",
        "Tap to open your conversation": "Apasă pentru a deschide conversația",
        "No conversations yet. Add a friend to get started.": "Nu ai conversații. Adaugă un prieten pentru a începe.",
        "Add a friend": "Adaugă un prieten",
        "Search by username.": "Caută după numele de utilizator.",
        "Friend requests": "Cereri de prietenie",
        "Your friends will appear here.": "Prietenii tăi vor apărea aici.",
        "Tap to message · hold for options": "Apasă pentru mesaj · ține apăsat pentru opțiuni",
        "Incoming": "Primite",
        "No incoming requests.": "Nu ai cereri primite.",
        "Accept or decline this request.": "Acceptă sau refuză cererea.",
        "Sent": "Trimise",
        "Request": "Cerere",
        "pending": "în așteptare",
        "accepted": "acceptată",
        "rejected": "respinsă",
        "Create a server": "Creează un server",
        "Build a new place for your community.": "Creează un loc nou pentru comunitatea ta.",
        "No other public servers are available yet.": "Nu există alte servere publice momentan.",
        "Discover servers": "Descoperă servere",
        "Find a community to join.": "Găsește o comunitate la care să te alături.",
        "members": "membri",
        "Join or create a server to see it here.": "Alătură-te sau creează un server pentru a-l vedea aici.",
        "Server not found.": "Serverul nu a fost găsit.",
        "This server has no channels yet.": "Acest server nu are încă niciun canal.",
        "Tap to choose a profile photo.": "Apasă pentru a alege o fotografie de profil.",
        "Tap to change your profile photo.": "Apasă pentru a schimba fotografia de profil.",
        "Remove profile photo": "Elimină fotografia de profil",
        "Language": "Limbă",
        "Current": "Curent",
        "English": "Engleză",
        "Message text size": "Dimensiunea textului",
        "Current: \(AetherLanguage.textSizeName)": "Curent: \(AetherLanguage.textSizeName)",
        "Sign out": "Deconectare",
        "Permanently delete your account and messages.": "Șterge definitiv contul și mesajele.",
        "Delete account": "Șterge contul",
        "Enter at least two characters of their username.": "Introdu cel puțin două caractere din numele de utilizator.",
        "Username": "Nume de utilizator",
        "Cancel": "Anulează",
        "Search": "Caută",
        "Enter at least two characters.": "Introdu cel puțin două caractere.",
        "People": "Persoane",
        "No users found.": "Nu s-au găsit utilizatori.",
        "Friend request sent.": "Cererea de prietenie a fost trimisă.",
        "Remove Friend": "Elimină prietenul",
        "Accept": "Acceptă",
        "Decline": "Refuză",
        "Join Server": "Alătură-te serverului",
        "Leave Server": "Părăsește serverul",
        "Delete Server": "Șterge serverul",
        "Delete Server?": "Ștergi serverul?",
        "Leave Server?": "Părăsești serverul?",
        "Permanently remove this server and its channels.": "Elimină definitiv serverul și canalele sale.",
        "Leave this community.": "Părăsește această comunitate.",
        "This permanently deletes the server, channels, and messages.": "Serverul, canalele și mesajele vor fi șterse definitiv.",
        "You will lose access to this server's channels.": "Vei pierde accesul la canalele acestui server.",
        "Your new server starts with a #general channel.": "Noul server începe cu un canal #general.",
        "Server name": "Numele serverului",
        "Description (optional)": "Descriere (opțională)",
        "Create": "Creează",
        "Enter a server name.": "Introdu numele serverului.",
        "That photo could not be prepared. Try a smaller image.": "Fotografia nu a putut fi pregătită. Încearcă o imagine mai mică.",
        "Profile photo updated.": "Fotografia de profil a fost actualizată.",
        "Profile photo removed.": "Fotografia de profil a fost eliminată.",
        "Small": "Mic",
        "Standard": "Standard",
        "Large": "Mare",
        "Delete your account?": "Ștergi contul?",
        "This permanently deletes your account, friendships, and messages. This cannot be undone.": "Contul, prieteniile și mesajele vor fi șterse definitiv. Acțiunea nu poate fi anulată.",
        "Delete Account": "Șterge contul",
        "OK": "OK"
    ]
}

extension Notification.Name {
    static let aetherLanguageDidChange = Notification.Name("AetherLanguageDidChange")
}
