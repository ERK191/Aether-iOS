import UIKit

final class MainTabBarController: UITabBarController {
    private let user: ChatUser
    private let token: String
    private var presenceTimer: Timer?

    init(user: ChatUser, token: String) {
        self.user = user
        self.token = token
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AetherTheme.background
        configureAppearance()

        let chats = ChatListViewController(user: user, token: token)
        let servers = CommunityViewController(page: .servers, user: user, token: token)
        let friends = CommunityViewController(page: .friends, user: user, token: token)
        let settings = CommunityViewController(page: .settings, user: user, token: token)

        viewControllers = [
            tab(chats, title: "Chats", symbol: "bubble.left.and.bubble.right.fill", tag: 0),
            tab(servers, title: "Communities", symbol: "person.3.fill", tag: 1),
            tab(friends, title: "Friends", symbol: "person.crop.circle.fill", tag: 2),
            tab(settings, title: "Settings", symbol: "gearshape.fill", tag: 3)
        ]
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startPresenceUpdates()
    }

    deinit {
        presenceTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func applicationDidBecomeActive() {
        startPresenceUpdates()
    }

    @objc private func applicationWillResignActive() {
        presenceTimer?.invalidate()
        presenceTimer = nil
    }

    private func startPresenceUpdates() {
        presenceTimer?.invalidate()
        ChatService.shared.heartbeatPresence(token: token)
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 40, repeats: true) { [weak self] _ in
            guard let self else { return }
            ChatService.shared.heartbeatPresence(token: self.token)
        }
    }

    private func tab(_ root: UIViewController, title: String, symbol: String, tag: Int) -> UINavigationController {
        let navigation = UINavigationController(rootViewController: root)
        navigation.tabBarItem = UITabBarItem(
            title: AetherLanguage.string(title),
            image: UIImage(systemName: symbol),
            tag: tag
        )
        navigation.navigationBar.prefersLargeTitles = false
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = AetherTheme.background
        appearance.titleTextAttributes = [
            .foregroundColor: AetherTheme.text,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        navigation.navigationBar.standardAppearance = appearance
        navigation.navigationBar.scrollEdgeAppearance = appearance
        navigation.navigationBar.tintColor = AetherTheme.accent
        return navigation
    }

    private func configureAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = AetherTheme.panel
        appearance.shadowColor = AetherTheme.border.withAlphaComponent(0.55)

        let normal = UITabBarItemAppearance()
        normal.normal.iconColor = AetherTheme.muted
        normal.normal.titleTextAttributes = [.foregroundColor: AetherTheme.muted]
        normal.selected.iconColor = AetherTheme.accent
        normal.selected.titleTextAttributes = [.foregroundColor: AetherTheme.accent]
        appearance.stackedLayoutAppearance = normal
        appearance.inlineLayoutAppearance = normal
        appearance.compactInlineLayoutAppearance = normal
        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        }
        tabBar.tintColor = AetherTheme.accent
        tabBar.unselectedItemTintColor = AetherTheme.muted
    }
}

private final class ChatListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    private let user: ChatUser
    private let token: String
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchBar = UISearchBar()
    private let activity = UIActivityIndicatorView(style: .medium)
    private var channels: [Channel] = []
    private var conversations: [DirectConversation] = []
    private var searchResults: [MessageSearchResult] = []
    private var query = ""
    private var pendingLoads = 0
    private var isLoadingData = false
    private var refreshTimer: Timer?
    private var searchWorkItem: DispatchWorkItem?
    private var searchGeneration = 0
    private var isSearchLoading = false

    init(user: ChatUser, token: String) {
        self.user = user
        self.token = token
        super.init(nibName: nil, bundle: nil)
        title = AetherLanguage.string("Chats")
        tabBarItem = UITabBarItem(title: AetherLanguage.string("Chats"), image: UIImage(systemName: "bubble.left.and.bubble.right.fill"), tag: 0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AetherTheme.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.pencil"),
            style: .plain,
            target: self,
            action: #selector(startConversation)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = AetherLanguage.string("New message")
        buildTable()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ChatService.shared.heartbeatPresence(token: token)
        if isViewLoaded, !tableView.isDragging {
            loadData()
        }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.loadData()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    deinit {
        refreshTimer?.invalidate()
        searchWorkItem?.cancel()
    }

    private func buildTable() {
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.delegate = self
        searchBar.placeholder = AetherLanguage.string("Search chats and messages")
        searchBar.searchBarStyle = .minimal
        searchBar.barTintColor = AetherTheme.background
        searchBar.tintColor = AetherTheme.accent
        searchBar.backgroundColor = AetherTheme.background
        searchBar.searchTextField.backgroundColor = AetherTheme.elevated
        searchBar.searchTextField.textColor = AetherTheme.text
        searchBar.searchTextField.attributedPlaceholder = NSAttributedString(
            string: searchBar.placeholder ?? "",
            attributes: [.foregroundColor: AetherTheme.muted]
        )
        view.addSubview(searchBar)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = AetherTheme.background
        tableView.separatorStyle = .none
        tableView.rowHeight = 78
        tableView.keyboardDismissMode = .onDrag
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ChatListCell.self, forCellReuseIdentifier: ChatListCell.reuseIdentifier)
        view.addSubview(tableView)

        activity.translatesAutoresizingMaskIntoConstraints = false
        activity.color = AetherTheme.accent
        activity.hidesWhenStopped = true
        view.addSubview(activity)

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 2),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            searchBar.heightAnchor.constraint(equalToConstant: 50),
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            activity.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            activity.centerYAnchor.constraint(equalTo: tableView.centerYAnchor)
        ])
    }

    private func loadData() {
        guard !isLoadingData else { return }
        isLoadingData = true
        pendingLoads = 2
        activity.startAnimating()
        ChatService.shared.channels(token: token) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                if case .success(let channels) = result {
                    self.channels = channels
                } else if case .failure(let error) = result {
                    self.showError(error)
                }
                self.finishLoad()
            }
        }
        ChatService.shared.conversations(token: token) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                if case .success(let conversations) = result {
                    self.conversations = conversations
                } else if case .failure(let error) = result {
                    self.showError(error)
                }
                self.finishLoad()
            }
        }
    }

    private func finishLoad() {
        pendingLoads -= 1
        guard pendingLoads == 0 else { return }
        isLoadingData = false
        activity.stopAnimating()
        updateUnreadTabBadge()
        tableView.reloadData()
    }

    private func updateUnreadTabBadge() {
        let unread = channels.reduce(0) { $0 + $1.unreadCount }
            + conversations.reduce(0) { $0 + $1.unreadCount }
        tabBarController?.tabBar.items?.first?.badgeValue = unread == 0 ? nil : (unread > 99 ? "99+" : String(unread))
    }

    private var visibleConversations: [DirectConversation] {
        guard !query.isEmpty else { return conversations }
        return conversations.filter { $0.user.username.localizedCaseInsensitiveContains(query) }
    }

    func numberOfSections(in tableView: UITableView) -> Int { 3 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        numberOfRows(in: section)
    }

    private func numberOfRows(in section: Int) -> Int {
        switch section {
        case 0:
            return channels.contains(where: { $0.name == "general" }) ? 1 : 0
        case 1:
            return visibleConversations.count
        case 2:
            return query.count >= 2 ? searchResults.count : 0
        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard numberOfRows(in: section) > 0 || section == 1 || (section == 2 && query.count >= 2) else { return nil }
        let label = UILabel()
        switch section {
        case 0:
            label.text = AetherLanguage.string("AETHER COMMUNITY")
        case 1:
            label.text = AetherLanguage.string("DIRECT MESSAGES")
        default:
            label.text = AetherLanguage.string("MESSAGE RESULTS")
        }
        label.textColor = AetherTheme.secondary
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.letterSpacing(1.1)
        let container = UIView()
        container.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 15),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -7)
        ])
        return container
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        numberOfRows(in: section) > 0 || section == 1 || (section == 2 && query.count >= 2) ? 38 : 0.01
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        if section == 1 && visibleConversations.isEmpty { return 112 }
        if section == 2 && query.count >= 2 && !isSearchLoading && searchResults.isEmpty { return 60 }
        return 10
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard (section == 1 && visibleConversations.isEmpty) ||
                (section == 2 && query.count >= 2 && !isSearchLoading && searchResults.isEmpty) else {
            return UIView()
        }
        let label = UILabel()
        if section == 1 {
            label.text = query.isEmpty
                ? AetherLanguage.string("No chats yet. Find a friend and say hello.")
                : AetherLanguage.string("No matching conversations.")
        } else {
            label.text = AetherLanguage.string("No matching messages.")
        }
        label.textColor = AetherTheme.secondary
        label.font = .systemFont(ofSize: 14)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: ChatListCell.reuseIdentifier,
            for: indexPath
        ) as? ChatListCell else {
            return UITableViewCell(style: .default, reuseIdentifier: nil)
        }
        if indexPath.section == 0, let channel = channels.first(where: { $0.name == "general" }) {
            cell.configure(
                title: AetherLanguage.string("The Lounge"),
                detail: "\(AetherLanguage.string("Community chat")) · #\(channel.name)",
                time: nil,
                avatar: user.avatar,
                symbol: "person.3.fill",
                tint: AetherTheme.accent,
                unreadCount: channel.unreadCount
            )
        } else if indexPath.section == 1, visibleConversations.indices.contains(indexPath.row) {
            let conversation = visibleConversations[indexPath.row]
            let preview = conversation.lastMessage.map {
                $0.content.isEmpty && $0.imageAvailable ? AetherLanguage.string("Photo") : $0.content
            } ?? AetherLanguage.string("Start a conversation")
            cell.configure(
                title: conversation.user.username,
                detail: conversation.user.isOnline
                    ? "\(AetherLanguage.string("Online")) · \(preview)"
                    : preview,
                time: conversation.lastMessage?.createdAt,
                avatar: conversation.user.avatar,
                symbol: "person.fill",
                tint: AetherTheme.accent,
                unreadCount: conversation.unreadCount,
                isOnline: conversation.user.isOnline
            )
        } else if indexPath.section == 2, searchResults.indices.contains(indexPath.row) {
            let result = searchResults[indexPath.row]
            let preview = result.content.isEmpty && result.imageAvailable
                ? AetherLanguage.string("Photo")
                : result.content
            cell.configure(
                title: result.title,
                detail: "\(result.username) · \(preview)",
                time: result.createdAt,
                avatar: nil,
                symbol: result.scope == "direct" ? "person.fill" : "number",
                tint: AetherTheme.accent
            )
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0, let channel = channels.first(where: { $0.name == "general" }) {
            openChat(channel: channel)
        } else if indexPath.section == 1, visibleConversations.indices.contains(indexPath.row) {
            openChat(conversation: visibleConversations[indexPath.row])
        } else if indexPath.section == 2, searchResults.indices.contains(indexPath.row) {
            openSearchResult(searchResults[indexPath.row])
        }
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        searchGeneration += 1
        let generation = searchGeneration
        searchWorkItem?.cancel()
        searchResults = []
        isSearchLoading = query.count >= 2
        tableView.reloadData()
        guard query.count >= 2 else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            ChatService.shared.searchMessages(query: self.query, token: self.token) { result in
                DispatchQueue.main.async {
                    guard self.searchGeneration == generation else { return }
                    switch result {
                    case .success(let results):
                        self.searchResults = results
                        self.isSearchLoading = false
                        self.tableView.reloadData()
                    case .failure(let error):
                        self.isSearchLoading = false
                        self.tableView.reloadData()
                        self.showError(error)
                    }
                }
            }
        }
        searchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    @objc private func startConversation() {
        tabBarController?.selectedIndex = 2
    }

    private func openChat(conversation: DirectConversation, initialMessageID: Int64? = nil) {
        let chat = ChatViewController(
            user: user,
            token: token,
            directConversation: conversation,
            initialMessageID: initialMessageID
        )
        chat.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(chat, animated: true)
    }

    private func openChat(channel: Channel, initialMessageID: Int64? = nil) {
        let chat = ChatViewController(
            user: user,
            token: token,
            serverChannel: channel,
            initialMessageID: initialMessageID
        )
        chat.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(chat, animated: true)
    }

    private func openSearchResult(_ result: MessageSearchResult) {
        if result.scope == "direct",
           let conversation = conversations.first(where: { $0.id == result.roomID }) {
            openChat(conversation: conversation, initialMessageID: result.messageID)
            return
        }
        guard result.scope == "channel" else { return }
        let channel = channels.first(where: { $0.id == result.roomID }) ?? Channel(
            id: result.roomID,
            name: result.channelName ?? result.title,
            description: "",
            serverID: result.serverID
        )
        openChat(channel: channel, initialMessageID: result.messageID)
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(
            title: AetherLanguage.string("Could not load chats"),
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: AetherLanguage.string("OK"), style: .default))
        present(alert, animated: true)
    }
}

private final class ChatListCell: UITableViewCell {
    static let reuseIdentifier = "AetherChatListCell"

    private let avatarView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let timeLabel = UILabel()
    private let unreadLabel = UILabel()
    private let onlineIndicator = UIView()
    private let separator = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = AetherTheme.background
        selectionStyle = .none
        buildLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(
        title: String,
        detail: String,
        time: Date?,
        avatar: String?,
        symbol: String,
        tint: UIColor,
        unreadCount: Int = 0,
        isOnline: Bool = false
    ) {
        titleLabel.text = title
        detailLabel.text = detail
        timeLabel.text = time.map(Self.shortTime)
        timeLabel.isHidden = time == nil
        avatarView.image = Self.image(from: avatar) ?? UIImage(systemName: symbol)
        avatarView.tintColor = .white
        avatarView.backgroundColor = tint
        unreadLabel.text = unreadCount > 99 ? "99+" : String(unreadCount)
        unreadLabel.isHidden = unreadCount == 0
        onlineIndicator.isHidden = !isOnline
        accessibilityLabel = "\(title), \(detail)"
    }

    private func buildLayout() {
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 28
        contentView.addSubview(avatarView)

        onlineIndicator.translatesAutoresizingMaskIntoConstraints = false
        onlineIndicator.backgroundColor = AetherTheme.accent
        onlineIndicator.layer.cornerRadius = 7
        onlineIndicator.layer.borderWidth = 2
        onlineIndicator.layer.borderColor = AetherTheme.background.cgColor
        contentView.addSubview(onlineIndicator)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = AetherTheme.text
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(titleLabel)

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.textColor = AetherTheme.secondary
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(detailLabel)

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.textColor = AetherTheme.accent
        timeLabel.font = .systemFont(ofSize: 11, weight: .medium)
        timeLabel.textAlignment = .right
        contentView.addSubview(timeLabel)

        unreadLabel.translatesAutoresizingMaskIntoConstraints = false
        unreadLabel.backgroundColor = AetherTheme.accent
        unreadLabel.textColor = .white
        unreadLabel.font = .systemFont(ofSize: 11, weight: .bold)
        unreadLabel.textAlignment = .center
        unreadLabel.layer.cornerRadius = 10
        unreadLabel.clipsToBounds = true
        contentView.addSubview(unreadLabel)

        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = AetherTheme.border.withAlphaComponent(0.55)
        contentView.addSubview(separator)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 56),
            avatarView.heightAnchor.constraint(equalToConstant: 56),
            onlineIndicator.widthAnchor.constraint(equalToConstant: 14),
            onlineIndicator.heightAnchor.constraint(equalToConstant: 14),
            onlineIndicator.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor),
            onlineIndicator.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            timeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            timeLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 56),
            unreadLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            unreadLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -17),
            unreadLabel.heightAnchor.constraint(equalToConstant: 20),
            unreadLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 13),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 17),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: unreadLabel.leadingAnchor, constant: -8),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            separator.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5)
        ])
    }

    private static func image(from dataURL: String?) -> UIImage? {
        guard let dataURL,
              let encoded = dataURL.split(separator: ",", maxSplits: 1).last,
              let data = Data(base64Encoded: String(encoded)) else { return nil }
        return UIImage(data: data)
    }

    private static func shortTime(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
        }
        if calendar.isDateInYesterday(date) { return AetherLanguage.string("Yesterday") }
        let formatter = DateFormatter()
        formatter.dateFormat = calendar.isDate(date, equalTo: Date(), toGranularity: .year) ? "EEE" : "d MMM"
        return formatter.string(from: date)
    }
}

private extension UILabel {
    func letterSpacing(_ value: CGFloat) {
        guard let text else { return }
        attributedText = NSAttributedString(
            string: text,
            attributes: [.kern: value]
        )
    }
}
