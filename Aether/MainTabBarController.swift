import UIKit

final class MainTabBarController: UITabBarController {
    private let user: ChatUser
    private let token: String

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
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

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
    private var query = ""
    private var pendingLoads = 0

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
        if isViewLoaded, !tableView.isDragging {
            loadData()
        }
    }

    private func buildTable() {
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.delegate = self
        searchBar.placeholder = AetherLanguage.string("Search chats")
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
        activity.stopAnimating()
        tableView.reloadData()
    }

    private var visibleConversations: [DirectConversation] {
        guard !query.isEmpty else { return conversations }
        return conversations.filter { $0.user.username.localizedCaseInsensitiveContains(query) }
    }

    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        numberOfRows(in: section)
    }

    private func numberOfRows(in section: Int) -> Int {
        section == 0
            ? (channels.first(where: { $0.name == "general" }) == nil ? 0 : 1)
            : visibleConversations.count
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard numberOfRows(in: section) > 0 || section == 1 else { return nil }
        let label = UILabel()
        label.text = section == 0
            ? AetherLanguage.string("AETHER COMMUNITY")
            : AetherLanguage.string("DIRECT MESSAGES")
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
        numberOfRows(in: section) > 0 || section == 1 ? 38 : 0.01
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        section == 1 && visibleConversations.isEmpty ? 112 : 10
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard section == 1, visibleConversations.isEmpty else { return UIView() }
        let label = UILabel()
        label.text = AetherLanguage.string("No chats yet. Find a friend and say hello.")
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
                tint: AetherTheme.accent
            )
        } else if visibleConversations.indices.contains(indexPath.row) {
            let conversation = visibleConversations[indexPath.row]
            let preview = conversation.lastMessage?.content ?? AetherLanguage.string("Start a conversation")
            cell.configure(
                title: conversation.user.username,
                detail: preview,
                time: conversation.lastMessage?.createdAt,
                avatar: conversation.user.avatar,
                symbol: "person.fill",
                tint: AetherTheme.accent
            )
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0, let channel = channels.first(where: { $0.name == "general" }) {
            openChat(channel: channel)
        } else if visibleConversations.indices.contains(indexPath.row) {
            openChat(conversation: visibleConversations[indexPath.row])
        }
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        tableView.reloadData()
    }

    @objc private func startConversation() {
        tabBarController?.selectedIndex = 2
    }

    private func openChat(conversation: DirectConversation) {
        let chat = ChatViewController(user: user, token: token, directConversation: conversation)
        chat.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(chat, animated: true)
    }

    private func openChat(channel: Channel) {
        let chat = ChatViewController(user: user, token: token, serverChannel: channel)
        chat.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(chat, animated: true)
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

    func configure(title: String, detail: String, time: Date?, avatar: String?, symbol: String, tint: UIColor) {
        titleLabel.text = title
        detailLabel.text = detail
        timeLabel.text = time.map(Self.shortTime)
        timeLabel.isHidden = time == nil
        avatarView.image = Self.image(from: avatar) ?? UIImage(systemName: symbol)
        avatarView.tintColor = .white
        avatarView.backgroundColor = tint
        accessibilityLabel = "\(title), \(detail)"
    }

    private func buildLayout() {
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 28
        contentView.addSubview(avatarView)

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

        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = AetherTheme.border.withAlphaComponent(0.55)
        contentView.addSubview(separator)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 56),
            avatarView.heightAnchor.constraint(equalToConstant: 56),
            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            timeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            timeLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 56),
            titleLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 13),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 17),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
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
