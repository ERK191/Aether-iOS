import UIKit

final class ChatViewController: UIViewController, UITextViewDelegate {
    private var user: ChatUser
    private let token: String
    private let directConversation: DirectConversation?
    private let serverChannel: Channel?
    private var channels: [Channel] = []
    private var selectedChannel: Channel?
    private var messages: [ChatMessage] = []

    private let leftRail = UIView()
    private let railStack = UIStackView()
    private var railServers: [AetherServer] = []
    private var railServerButtons: [UIButton] = []
    private let header = UIView()
    private let channelStrip = UIStackView()
    private let serverStatus = UIView()
    private let serverNameLabel = UILabel()
    private let memberLineLabel = UILabel()
    private var accountButton: UIButton?
    private let channelTitle = UILabel()
    private let channelSubtitle = UILabel()
    private let messageScroll = UIScrollView()
    private let messageStack = UIStackView()
    private let composer = UIView()
    private let messageInput = UITextView()
    private let sendButton = UIButton(type: .system)
    private let activity = UIActivityIndicatorView(style: .medium)
    private let emptyLabel = UILabel()
    private var composerBottomConstraint: NSLayoutConstraint?
    private var channelStripHeightConstraint: NSLayoutConstraint?
    private var directRefreshTimer: Timer?

    init(
        user: ChatUser,
        token: String,
        directConversation: DirectConversation? = nil,
        serverChannel: Channel? = nil
    ) {
        self.user = user
        self.token = token
        self.directConversation = directConversation
        self.serverChannel = serverChannel
        super.init(nibName: nil, bundle: nil)
    }

    @objc private func showServers() {
        let page = CommunityViewController(page: .servers, user: user, token: token)
        navigationController?.pushViewController(page, animated: true)
    }

    @objc private func openRailServer(_ sender: UIButton) {
        guard railServers.indices.contains(sender.tag) else { return }
        let page = CommunityViewController(
            page: .serverChannels,
            user: user,
            token: token,
            server: railServers[sender.tag]
        )
        navigationController?.pushViewController(page, animated: true)
    }

    private func loadRailServers() {
        ChatService.shared.servers(token: token) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                let servers: [AetherServer]
                switch result {
                case .success(let value):
                    servers = value
                case .failure(let error):
                    self.showNotice(error.localizedDescription)
                    return
                }
                self.railServers = Array(servers.filter(\.isMember).prefix(3))
                self.railServerButtons.forEach {
                    self.railStack.removeArrangedSubview($0)
                    $0.removeFromSuperview()
                }
                self.railServerButtons = self.railServers.enumerated().map { index, server in
                    let button = UIButton(type: .system)
                    button.translatesAutoresizingMaskIntoConstraints = false
                    button.setTitle(String(server.name.prefix(1)).uppercased(), for: .normal)
                    button.setTitleColor(.white, for: .normal)
                    button.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
                    button.backgroundColor = AetherTheme.elevated
                    button.layer.cornerRadius = 17
                    button.tag = index
                    button.accessibilityLabel = server.name
                    button.addTarget(self, action: #selector(self.openRailServer(_:)), for: .touchUpInside)
                    NSLayoutConstraint.activate([
                        button.widthAnchor.constraint(equalToConstant: 46),
                        button.heightAnchor.constraint(equalToConstant: 46)
                    ])
                    self.railStack.insertArrangedSubview(button, at: min(3 + index, self.railStack.arrangedSubviews.count))
                    return button
                }
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AetherTheme.background
        navigationController?.setNavigationBarHidden(true, animated: false)
        buildRail()
        buildInterface()
        installKeyboardObservers()
        if let directConversation {
            channelTitle.text = directConversation.user.username
            channelSubtitle.text = AetherLanguage.string("Direct message")
            channelStripHeightConstraint?.constant = 0
            reloadSelectedChannel()
            directRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                self?.refreshDirectMessages()
            }
        } else if let serverChannel {
            select(serverChannel)
        } else {
            loadChannels()
        }
        if directConversation == nil {
            ChatService.shared.connectWebSocket(
                token: token,
                onMessage: { [weak self] message in
                    DispatchQueue.main.async {
                        self?.receive(message)
                    }
                },
                onReady: { [weak self] in
                    DispatchQueue.main.async {
                        self?.reloadSelectedChannel()
                    }
                }
            )
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .aetherLanguageDidChange,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        if directConversation == nil {
            loadRailServers()
            ChatService.shared.currentUser(token: token) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch result {
                    case .success(let currentUser):
                        self.user = currentUser
                        self.updateAccountButton()
                    case .failure(let error):
                        self.showNotice(error.localizedDescription)
                    }
                }
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || navigationController?.isBeingDismissed == true {
            directRefreshTimer?.invalidate()
            directRefreshTimer = nil
            if directConversation == nil {
                ChatService.shared.disconnectWebSocket()
            }
            NotificationCenter.default.removeObserver(self)
        }
    }

    deinit {
        directRefreshTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        if directConversation == nil {
            ChatService.shared.disconnectWebSocket()
        }
    }

    @objc private func showHome() {
        if let navigationController, navigationController.viewControllers.count > 1 {
            navigationController.popToRootViewController(animated: true)
        }
        guard let channel = channels.first(where: { $0.name == "general" }) ?? channels.first else { return }
        select(channel)
    }

    @objc private func showDirectMessages() {
        let page = CommunityViewController(page: .conversations, user: user, token: token)
        navigationController?.pushViewController(page, animated: true)
    }

    @objc private func showFriends() {
        let page = CommunityViewController(page: .friends, user: user, token: token)
        navigationController?.pushViewController(page, animated: true)
    }

    @objc private func addServer() {
        let page = CommunityViewController(page: .addServer, user: user, token: token)
        navigationController?.pushViewController(page, animated: true)
    }

    @objc private func discoverServers() {
        let page = CommunityViewController(page: .discoverServers, user: user, token: token)
        navigationController?.pushViewController(page, animated: true)
    }

    private func buildRail() {
        leftRail.translatesAutoresizingMaskIntoConstraints = false
        leftRail.backgroundColor = AetherTheme.panel
        view.addSubview(leftRail)

        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = AetherTheme.elevated
        leftRail.addSubview(divider)

        railStack.translatesAutoresizingMaskIntoConstraints = false
        railStack.axis = .vertical
        railStack.alignment = .center
        railStack.spacing = 12
        leftRail.addSubview(railStack)

        let home = UIButton(type: .system)
        home.translatesAutoresizingMaskIntoConstraints = false
        home.setImage(UIImage(named: "AetherMark"), for: .normal)
        home.tintColor = .white
        home.backgroundColor = AetherTheme.accent
        home.layer.cornerRadius = 17
        home.clipsToBounds = true
        home.accessibilityLabel = AetherLanguage.string("Aether home")
        home.addTarget(self, action: #selector(showHome), for: .touchUpInside)
        railStack.addArrangedSubview(home)
        NSLayoutConstraint.activate([
            home.widthAnchor.constraint(equalToConstant: 46),
            home.heightAnchor.constraint(equalToConstant: 46)
        ])

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = AetherTheme.elevated
        railStack.addArrangedSubview(separator)
        NSLayoutConstraint.activate([
            separator.widthAnchor.constraint(equalToConstant: 34),
            separator.heightAnchor.constraint(equalToConstant: 2)
        ])

        let server = UIButton(type: .system)
        server.translatesAutoresizingMaskIntoConstraints = false
        server.setTitle("L", for: .normal)
        server.setTitleColor(.white, for: .normal)
        server.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        server.backgroundColor = AetherTheme.elevated
        server.layer.cornerRadius = 17
        server.accessibilityLabel = "The Lounge server"
        server.addTarget(self, action: #selector(showHome), for: .touchUpInside)
        railStack.addArrangedSubview(server)
        NSLayoutConstraint.activate([
            server.widthAnchor.constraint(equalToConstant: 46),
            server.heightAnchor.constraint(equalToConstant: 46)
        ])
        server.addTarget(self, action: #selector(showServers), for: .touchUpInside)

        railStack.addArrangedSubview(makeRailButton(
            symbol: "person.2.fill",
            label: "Friends",
            action: #selector(showFriends)
        ))
        railStack.addArrangedSubview(makeRailButton(
            symbol: "bubble.left.and.bubble.right.fill",
            label: "Direct messages",
            action: #selector(showDirectMessages)
        ))
        railStack.addArrangedSubview(makeRailButton(
            symbol: "plus",
            label: "Add a server",
            action: #selector(addServer)
        ))
        railStack.addArrangedSubview(makeRailButton(
            symbol: "safari.fill",
            label: "Discover servers",
            action: #selector(discoverServers)
        ))

        let spacer = UIView()
        railStack.addArrangedSubview(spacer)
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)

        let account = UIButton(type: .system)
        account.translatesAutoresizingMaskIntoConstraints = false
        account.setTitle(String(user.username.prefix(1)).uppercased(), for: .normal)
        account.setTitleColor(.white, for: .normal)
        account.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        account.backgroundColor = AetherTheme.accent
        account.layer.cornerRadius = 22
        account.accessibilityLabel = AetherLanguage.string("Account settings")
        accountButton = account
        updateAccountButton()
        account.addTarget(self, action: #selector(showAccountMenu), for: .touchUpInside)
        railStack.addArrangedSubview(account)
        NSLayoutConstraint.activate([
            account.widthAnchor.constraint(equalToConstant: 46),
            account.heightAnchor.constraint(equalToConstant: 46),
            leftRail.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            leftRail.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            leftRail.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            leftRail.widthAnchor.constraint(equalToConstant: 68),
            divider.trailingAnchor.constraint(equalTo: leftRail.trailingAnchor),
            divider.topAnchor.constraint(equalTo: leftRail.topAnchor),
            divider.bottomAnchor.constraint(equalTo: leftRail.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            railStack.leadingAnchor.constraint(equalTo: leftRail.leadingAnchor, constant: 10),
            railStack.trailingAnchor.constraint(equalTo: leftRail.trailingAnchor, constant: -11),
            railStack.topAnchor.constraint(equalTo: leftRail.topAnchor, constant: 12),
            railStack.bottomAnchor.constraint(equalTo: leftRail.bottomAnchor, constant: -12)
        ])
    }

    private func updateAccountButton() {
        guard let accountButton else { return }
        if let avatar = user.avatar,
           let encoded = avatar.split(separator: ",", maxSplits: 1).last,
           let data = Data(base64Encoded: String(encoded)),
           let image = UIImage(data: data) {
            accountButton.setTitle(nil, for: .normal)
            accountButton.setImage(image, for: .normal)
            accountButton.imageView?.contentMode = .scaleAspectFill
            accountButton.clipsToBounds = true
        } else {
            accountButton.setImage(nil, for: .normal)
            accountButton.setTitle(String(user.username.prefix(1)).uppercased(), for: .normal)
        }
    }

    private func makeRailButton(symbol: String, label: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.tintColor = AetherTheme.secondary
        button.backgroundColor = AetherTheme.elevated
        button.layer.cornerRadius = 17
        button.accessibilityLabel = label
        button.addTarget(self, action: action, for: .touchUpInside)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 46),
            button.heightAnchor.constraint(equalToConstant: 46)
        ])
        return button
    }

    private func buildInterface() {
        header.translatesAutoresizingMaskIntoConstraints = false
        header.backgroundColor = AetherTheme.background
        view.addSubview(header)

        let logo = UIImageView(image: UIImage(named: "AetherMark"))
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.contentMode = .scaleAspectFit
        logo.layer.cornerRadius = 17
        logo.clipsToBounds = true
        header.addSubview(logo)

        let serverName = serverNameLabel
        serverName.translatesAutoresizingMaskIntoConstraints = false
        serverName.text = AetherLanguage.string("THE LOUNGE")
        serverName.textColor = AetherTheme.text
        serverName.font = .systemFont(ofSize: 17, weight: .bold)
        header.addSubview(serverName)

        let memberLine = memberLineLabel
        memberLine.translatesAutoresizingMaskIntoConstraints = false
        memberLine.text = AetherLanguage.string("LIVE COMMUNITY")
        memberLine.textColor = AetherTheme.secondary
        memberLine.font = .systemFont(ofSize: 10, weight: .bold)
        header.addSubview(memberLine)

        serverStatus.translatesAutoresizingMaskIntoConstraints = false
        serverStatus.backgroundColor = AetherTheme.cyan
        serverStatus.layer.cornerRadius = 5
        header.addSubview(serverStatus)

        channelStrip.translatesAutoresizingMaskIntoConstraints = false
        channelStrip.axis = .horizontal
        channelStrip.alignment = .center
        channelStrip.spacing = 9
        channelStrip.distribution = .fill
        view.addSubview(channelStrip)

        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = AetherTheme.elevated
        view.addSubview(divider)

        let channelHeader = UIView()
        channelHeader.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(channelHeader)

        let hash = UILabel()
        hash.translatesAutoresizingMaskIntoConstraints = false
        hash.text = "#"
        hash.textColor = AetherTheme.accent
        hash.font = .systemFont(ofSize: 27, weight: .medium)
        channelHeader.addSubview(hash)

        channelTitle.translatesAutoresizingMaskIntoConstraints = false
        channelTitle.textColor = AetherTheme.text
        channelTitle.font = .systemFont(ofSize: 19, weight: .bold)
        channelHeader.addSubview(channelTitle)

        channelSubtitle.translatesAutoresizingMaskIntoConstraints = false
        channelSubtitle.textColor = AetherTheme.secondary
        channelSubtitle.font = .systemFont(ofSize: 12)
        channelSubtitle.numberOfLines = 1
        channelHeader.addSubview(channelSubtitle)

        messageScroll.translatesAutoresizingMaskIntoConstraints = false
        messageScroll.alwaysBounceVertical = true
        messageScroll.keyboardDismissMode = .interactive
        view.addSubview(messageScroll)

        messageStack.translatesAutoresizingMaskIntoConstraints = false
        messageStack.axis = .vertical
        messageStack.spacing = 18
        messageScroll.addSubview(messageStack)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = AetherLanguage.string("No messages yet.\nStart the conversation ✨")
        emptyLabel.textColor = AetherTheme.secondary
        emptyLabel.font = .systemFont(ofSize: 15, weight: .medium)
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        messageStack.addArrangedSubview(emptyLabel)

        composer.translatesAutoresizingMaskIntoConstraints = false
        composer.backgroundColor = AetherTheme.background
        view.addSubview(composer)

        let composerLine = UIView()
        composerLine.translatesAutoresizingMaskIntoConstraints = false
        composerLine.backgroundColor = AetherTheme.elevated
        composer.addSubview(composerLine)

        let inputBackground = UIView()
        inputBackground.translatesAutoresizingMaskIntoConstraints = false
        inputBackground.backgroundColor = AetherTheme.panel
        inputBackground.layer.cornerRadius = 20
        composer.addSubview(inputBackground)

        messageInput.translatesAutoresizingMaskIntoConstraints = false
        messageInput.backgroundColor = .clear
        messageInput.textColor = AetherTheme.text
        let messageFontSize = UserDefaults.standard.double(forKey: "aether.messageFontSize")
        messageInput.font = .systemFont(ofSize: messageFontSize == 0 ? 15 : messageFontSize)
        messageInput.isScrollEnabled = true
        messageInput.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 10, right: 4)
        messageInput.textContainer.lineFragmentPadding = 0
        messageInput.returnKeyType = .default
        messageInput.delegate = self
        inputBackground.addSubview(messageInput)

        let placeholder = UILabel()
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.text = "Message #general"
        placeholder.textColor = AetherTheme.muted
        placeholder.font = .systemFont(ofSize: 15)
        placeholder.tag = 702
        inputBackground.addSubview(placeholder)

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.setImage(UIImage(systemName: "arrow.up"), for: .normal)
        sendButton.tintColor = .white
        sendButton.backgroundColor = AetherTheme.accent
        sendButton.layer.cornerRadius = 18
        sendButton.addTarget(self, action: #selector(sendMessage), for: .touchUpInside)
        inputBackground.addSubview(sendButton)

        activity.translatesAutoresizingMaskIntoConstraints = false
        activity.color = AetherTheme.cyan
        view.addSubview(activity)

        channelStripHeightConstraint = channelStrip.heightAnchor.constraint(equalToConstant: 50)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: leftRail.trailingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 66),
            logo.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 18),
            logo.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: 38),
            logo.heightAnchor.constraint(equalToConstant: 38),
            serverName.leadingAnchor.constraint(equalTo: logo.trailingAnchor, constant: 11),
            serverName.topAnchor.constraint(equalTo: header.topAnchor, constant: 14),
            memberLine.leadingAnchor.constraint(equalTo: serverName.leadingAnchor),
            memberLine.topAnchor.constraint(equalTo: serverName.bottomAnchor, constant: 3),
            serverStatus.leadingAnchor.constraint(equalTo: memberLine.trailingAnchor, constant: 7),
            serverStatus.centerYAnchor.constraint(equalTo: memberLine.centerYAnchor),
            serverStatus.widthAnchor.constraint(equalToConstant: 9),
            serverStatus.heightAnchor.constraint(equalToConstant: 9),

            channelStrip.topAnchor.constraint(equalTo: header.bottomAnchor),
            channelStrip.leadingAnchor.constraint(equalTo: leftRail.trailingAnchor, constant: 16),
            channelStrip.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
            channelStripHeightConstraint!,
            divider.topAnchor.constraint(equalTo: channelStrip.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: leftRail.trailingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            channelHeader.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 12),
            channelHeader.leadingAnchor.constraint(equalTo: leftRail.trailingAnchor, constant: 20),
            channelHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            channelHeader.heightAnchor.constraint(equalToConstant: 48),
            hash.leadingAnchor.constraint(equalTo: channelHeader.leadingAnchor),
            hash.centerYAnchor.constraint(equalTo: channelHeader.centerYAnchor, constant: -1),
            channelTitle.leadingAnchor.constraint(equalTo: hash.trailingAnchor, constant: 8),
            channelTitle.topAnchor.constraint(equalTo: channelHeader.topAnchor, constant: 1),
            channelSubtitle.leadingAnchor.constraint(equalTo: channelTitle.leadingAnchor),
            channelSubtitle.topAnchor.constraint(equalTo: channelTitle.bottomAnchor, constant: 3),
            channelSubtitle.trailingAnchor.constraint(lessThanOrEqualTo: channelHeader.trailingAnchor),

            messageScroll.topAnchor.constraint(equalTo: channelHeader.bottomAnchor, constant: 8),
            messageScroll.leadingAnchor.constraint(equalTo: leftRail.trailingAnchor),
            messageScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            messageStack.topAnchor.constraint(equalTo: messageScroll.contentLayoutGuide.topAnchor, constant: 15),
            messageStack.leadingAnchor.constraint(equalTo: messageScroll.frameLayoutGuide.leadingAnchor, constant: 18),
            messageStack.trailingAnchor.constraint(equalTo: messageScroll.frameLayoutGuide.trailingAnchor, constant: -18),
            messageStack.bottomAnchor.constraint(equalTo: messageScroll.contentLayoutGuide.bottomAnchor, constant: -16),
            emptyLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 100),

            composer.topAnchor.constraint(equalTo: messageScroll.bottomAnchor),
            composer.leadingAnchor.constraint(equalTo: leftRail.trailingAnchor),
            composer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            composer.heightAnchor.constraint(equalToConstant: 83),
            composer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            composerLine.topAnchor.constraint(equalTo: composer.topAnchor),
            composerLine.leadingAnchor.constraint(equalTo: composer.leadingAnchor),
            composerLine.trailingAnchor.constraint(equalTo: composer.trailingAnchor),
            composerLine.heightAnchor.constraint(equalToConstant: 1),

            inputBackground.topAnchor.constraint(equalTo: composer.topAnchor, constant: 11),
            inputBackground.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 15),
            inputBackground.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -15),
            inputBackground.heightAnchor.constraint(equalToConstant: 52),
            messageInput.leadingAnchor.constraint(equalTo: inputBackground.leadingAnchor, constant: 10),
            messageInput.topAnchor.constraint(equalTo: inputBackground.topAnchor, constant: 1),
            messageInput.bottomAnchor.constraint(equalTo: inputBackground.bottomAnchor, constant: -1),
            messageInput.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -4),
            placeholder.leadingAnchor.constraint(equalTo: messageInput.leadingAnchor, constant: 2),
            placeholder.topAnchor.constraint(equalTo: inputBackground.topAnchor, constant: 17),
            sendButton.trailingAnchor.constraint(equalTo: inputBackground.trailingAnchor, constant: -7),
            sendButton.centerYAnchor.constraint(equalTo: inputBackground.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 36),
            sendButton.heightAnchor.constraint(equalToConstant: 36),
            activity.centerXAnchor.constraint(equalTo: messageScroll.centerXAnchor),
            activity.centerYAnchor.constraint(equalTo: messageScroll.centerYAnchor)
        ])
        composerBottomConstraint = composer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        composerBottomConstraint?.isActive = false
        updatePlaceholder()
    }

    private func loadChannels() {
        activity.startAnimating()
        ChatService.shared.channels(token: token) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.activity.stopAnimating()
                switch result {
                case .success(let channels):
                    self.channels = channels
                    self.renderChannels()
                    if self.selectedChannel == nil,
                       let general = channels.first(where: { $0.name == "general" }) ?? channels.first {
                        self.select(general)
                    }
                case .failure(let error):
                    self.showNotice(error.localizedDescription)
                }
            }
        }
    }

    private func renderChannels() {
        channelStrip.arrangedSubviews.forEach { view in
            channelStrip.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for channel in channels {
            let button = UIButton(type: .system)
            button.setTitle("#  \(channel.name)", for: .normal)
            button.setTitleColor(
                channel.id == selectedChannel?.id ? .white : AetherTheme.secondary,
                for: .normal
            )
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
            button.backgroundColor = channel.id == selectedChannel?.id ? AetherTheme.accent : AetherTheme.panel
            button.layer.cornerRadius = 16
            button.tag = channels.firstIndex(where: { $0.id == channel.id }) ?? 0
            button.addTarget(self, action: #selector(selectChannel(_:)), for: .touchUpInside)
            channelStrip.addArrangedSubview(button)
        }
    }

    @objc private func selectChannel(_ sender: UIButton) {
        guard channels.indices.contains(sender.tag) else { return }
        select(channels[sender.tag])
    }

    private func select(_ channel: Channel) {
        selectedChannel = channel
        channelTitle.text = channel.name
        channelSubtitle.text = "\(channel.memberCount) members  ·  \(channel.description)"
        if let placeholder = composer.viewWithTag(702) as? UILabel {
            placeholder.text = "\(AetherLanguage.string("Message")) #\(channel.name)"
        }
        renderChannels()
        renderMessages([])
        reloadSelectedChannel()
    }

    private func reloadSelectedChannel() {
        if let directConversation {
            activity.startAnimating()
            ChatService.shared.directMessages(conversationID: directConversation.id, token: token) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.activity.stopAnimating()
                    switch result {
                    case .success(let messages):
                        self.mergeDirectMessages(messages)
                    case .failure(let error):
                        self.showNotice(error.localizedDescription)
                    }
                }
            }
            return
        }
        guard let channel = selectedChannel else { return }
        activity.startAnimating()
        ChatService.shared.messages(channelID: channel.id, token: token) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.selectedChannel?.id == channel.id else { return }
                self.activity.stopAnimating()
                switch result {
                case .success(let messages):
                    let liveMessages = self.messages.filter { $0.channelID == channel.id }
                    let combined = Dictionary(
                        (messages + liveMessages).map { ($0.id, $0) },
                        uniquingKeysWith: { _, newer in newer }
                    ).values.sorted { $0.id < $1.id }
                    self.renderMessages(combined)
                case .failure(let error):
                    self.showNotice(error.localizedDescription)
                }
            }
        }
    }

    private func refreshDirectMessages() {
        guard let directConversation else { return }
        ChatService.shared.directMessages(conversationID: directConversation.id, token: token) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let messages): self.mergeDirectMessages(messages)
                case .failure(let error): self.showNotice(error.localizedDescription)
                }
            }
        }
    }

    private func mergeDirectMessages(_ fetched: [ChatMessage]) {
        let combined = Dictionary(
            (fetched + messages).map { ($0.id, $0) },
            uniquingKeysWith: { _, newer in newer }
        ).values.sorted { $0.id < $1.id }
        renderMessages(combined)
    }

    private func renderMessages(_ items: [ChatMessage]) {
        messages = items
        messageStack.arrangedSubviews.forEach { view in
            messageStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        if items.isEmpty {
            emptyLabel.isHidden = false
            messageStack.addArrangedSubview(emptyLabel)
            return
        }
        items.forEach { messageStack.addArrangedSubview(makeMessageView($0)) }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let bottom = CGPoint(x: 0, y: max(0, self.messageScroll.contentSize.height - self.messageScroll.bounds.height))
            self.messageScroll.setContentOffset(bottom, animated: false)
        }
    }

    private func makeMessageView(_ message: ChatMessage) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 11

        let avatar = UIImageView()
        avatar.contentMode = .scaleAspectFill
        avatar.backgroundColor = avatarColor(for: message.username)
        avatar.layer.cornerRadius = 20
        avatar.clipsToBounds = true
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.widthAnchor.constraint(equalToConstant: 40).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: 40).isActive = true
        if let avatarDataURL = message.avatar,
           let encoded = avatarDataURL.split(separator: ",", maxSplits: 1).last,
           let data = Data(base64Encoded: String(encoded)) {
            avatar.image = UIImage(data: data)
        }
        if avatar.image == nil {
            let initial = UILabel()
            initial.translatesAutoresizingMaskIntoConstraints = false
            initial.text = String(message.username.prefix(1)).uppercased()
            initial.textColor = .white
            initial.font = .systemFont(ofSize: 15, weight: .bold)
            initial.textAlignment = .center
            avatar.addSubview(initial)
            NSLayoutConstraint.activate([
                initial.leadingAnchor.constraint(equalTo: avatar.leadingAnchor),
                initial.trailingAnchor.constraint(equalTo: avatar.trailingAnchor),
                initial.topAnchor.constraint(equalTo: avatar.topAnchor),
                initial.bottomAnchor.constraint(equalTo: avatar.bottomAnchor)
            ])
        }
        row.addArrangedSubview(avatar)

        let column = UIStackView()
        column.axis = .vertical
        column.spacing = 4

        let heading = UIStackView()
        heading.axis = .horizontal
        heading.alignment = .firstBaseline
        heading.spacing = 8
        let name = UILabel()
        name.text = message.username
        name.textColor = AetherTheme.cyan
        name.font = .systemFont(ofSize: 14, weight: .bold)
        let time = UILabel()
        time.text = DateFormatter.localizedString(from: message.createdAt, dateStyle: .none, timeStyle: .short)
        time.textColor = AetherTheme.muted
        time.font = .systemFont(ofSize: 10, weight: .medium)
        heading.addArrangedSubview(name)
        heading.addArrangedSubview(time)

        let body = UILabel()
        body.text = message.content
        body.textColor = AetherTheme.text
        let messageFontSize = UserDefaults.standard.double(forKey: "aether.messageFontSize")
        body.font = .systemFont(ofSize: messageFontSize == 0 ? 15 : messageFontSize)
        body.numberOfLines = 0
        column.addArrangedSubview(heading)
        column.addArrangedSubview(body)
        row.addArrangedSubview(column)
        return row
    }

    private func avatarColor(for username: String) -> UIColor {
        let colors = [AetherTheme.accent, AetherTheme.cyan, UIColor.systemPink, UIColor.systemTeal, UIColor.systemOrange]
        let index = username.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % colors.count }
        return colors[index]
    }

    private func receive(_ message: ChatMessage) {
        let belongsToConversation: Bool
        if let directConversation {
            belongsToConversation = message.conversationID == directConversation.id
        } else {
            belongsToConversation = selectedChannel?.id == message.channelID
        }
        guard belongsToConversation,
              !messages.contains(where: { $0.id == message.id }) else { return }
        messages.append(message)
        emptyLabel.removeFromSuperview()
        messageStack.addArrangedSubview(makeMessageView(message))
        view.layoutIfNeeded()
        let bottom = CGPoint(x: 0, y: max(0, messageScroll.contentSize.height - messageScroll.bounds.height))
        messageScroll.setContentOffset(bottom, animated: true)
    }

    @objc private func sendMessage() {
        let content = messageInput.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        sendButton.isEnabled = false
        let completion: (Result<ChatMessage, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.sendButton.isEnabled = true
                switch result {
                case .success(let message):
                    self.messageInput.text = nil
                    self.updatePlaceholder()
                    self.receive(message)
                case .failure(let error):
                    self.showNotice(error.localizedDescription)
                }
            }
        }
        if let directConversation {
            ChatService.shared.sendDirectMessage(
                content: content,
                conversationID: directConversation.id,
                token: token,
                completion: completion
            )
        } else if let channel = selectedChannel {
            ChatService.shared.send(content: content, channelID: channel.id, token: token, completion: completion)
        } else {
            sendButton.isEnabled = true
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        updatePlaceholder()
    }

    private func updatePlaceholder() {
        (composer.viewWithTag(702) as? UILabel)?.isHidden = !(messageInput.text ?? "").isEmpty
    }

    @objc private func languageDidChange() {
        serverNameLabel.text = AetherLanguage.string("THE LOUNGE")
        memberLineLabel.text = AetherLanguage.string("LIVE COMMUNITY")
        emptyLabel.text = AetherLanguage.string("No messages yet.\nStart the conversation ✨")
        if let directConversation {
            channelTitle.text = directConversation.user.username
            channelSubtitle.text = AetherLanguage.string("Direct message")
        } else if let selectedChannel {
            channelTitle.text = selectedChannel.name
            channelSubtitle.text = "\(selectedChannel.memberCount) \(AetherLanguage.string("members"))  ·  \(selectedChannel.description)"
            if let placeholder = composer.viewWithTag(702) as? UILabel {
                placeholder.text = "\(AetherLanguage.string("Message")) #\(selectedChannel.name)"
            }
            renderChannels()
        }
    }

    @objc private func showAccountMenu() {
        let alert = UIAlertController(title: user.username, message: AetherLanguage.string("Signed in to Aether"), preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: AetherLanguage.string("Account Settings"), style: .default) { [weak self] _ in
            guard let self else { return }
            self.navigationController?.pushViewController(
                CommunityViewController(page: .settings, user: self.user, token: self.token),
                animated: true
            )
        })
        alert.addAction(UIAlertAction(title: AetherLanguage.string("Friends"), style: .default) { [weak self] _ in
            self?.showFriends()
        })
        alert.addAction(UIAlertAction(title: AetherLanguage.string("Your Servers"), style: .default) { [weak self] _ in
            guard let self else { return }
            self.navigationController?.pushViewController(
                CommunityViewController(page: .servers, user: self.user, token: self.token),
                animated: true
            )
        })
        alert.addAction(UIAlertAction(title: AetherLanguage.string("Sign out"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            SessionStore.delete()
            ChatService.shared.disconnectWebSocket()
            self.navigationController?.setViewControllers([AuthViewController()], animated: true)
        })
        alert.addAction(UIAlertAction(title: AetherLanguage.string("Cancel"), style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.maxX - 36, y: view.safeAreaInsets.top + 32, width: 1, height: 1)
        }
        present(alert, animated: true)
    }

    private func showNotice(_ message: String) {
        let alert = UIAlertController(title: "Aether", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func installKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let frame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let keyboardFrame = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - keyboardFrame.minY - view.safeAreaInsets.bottom)
        composerBottomConstraint?.isActive = false
        composerBottomConstraint = composer.bottomAnchor.constraint(
            equalTo: view.bottomAnchor,
            constant: -keyboardFrame.height
        )
        composerBottomConstraint?.isActive = true
        messageScroll.contentInset.bottom = overlap
        view.layoutIfNeeded()
        let duration = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        composerBottomConstraint?.isActive = false
        composerBottomConstraint = composer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        composerBottomConstraint?.isActive = true
        messageScroll.contentInset.bottom = 0
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }
}
