import UIKit

final class ChatViewController: UIViewController, UITextViewDelegate {
    private var user: ChatUser
    private let token: String
    private let directConversation: DirectConversation?
    private let serverChannel: Channel?
    private var channels: [Channel] = []
    private var selectedChannel: Channel?
    private var messages: [ChatMessage] = []

    private let header = UIView()
    private let channelScrollView = UIScrollView()
    private let channelStrip = UIStackView()
    private let headerAvatar = UIImageView()
    private let channelTitle = UILabel()
    private let channelSubtitle = UILabel()
    private let messageScroll = UIScrollView()
    private let messageStack = UIStackView()
    private let emptyStateView = UIStackView()
    private let emptyStateIcon = UIImageView(image: UIImage(systemName: "bubble.left.and.bubble.right.fill"))
    private let emptyStateTitle = UILabel()
    private let emptyStateSubtitle = UILabel()
    private let composer = UIView()
    private let messageInput = UITextView()
    private let sendButton = UIButton(type: .system)
    private let activity = UIActivityIndicatorView(style: .medium)
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

    private func updateEmptyStateText() {
        if let directConversation {
            emptyStateTitle.text = "\(AetherLanguage.string("Say hello to")) \(directConversation.user.username)"
            emptyStateSubtitle.text = AetherLanguage.string("Your private conversation starts with your first message.")
        } else if let selectedChannel {
            emptyStateTitle.text = "\(AetherLanguage.string("Welcome to")) #\(selectedChannel.name)"
            emptyStateSubtitle.text = AetherLanguage.string("This channel is quiet for now. Send a message to get things started.")
        } else {
            emptyStateTitle.text = AetherLanguage.string("Welcome to Aether")
            emptyStateSubtitle.text = AetherLanguage.string("Choose a channel and start a conversation.")
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AetherTheme.background
        navigationController?.setNavigationBarHidden(true, animated: false)
        buildInterface()
        updateEmptyStateText()
        installKeyboardObservers()
        if let directConversation {
            updateDirectHeader()
            channelStripHeightConstraint?.constant = 0
            updateEmptyStateText()
            reloadSelectedChannel()
            directRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                self?.refreshDirectMessages()
            }
        } else if let serverChannel {
            channelStripHeightConstraint?.constant = 0
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
            ChatService.shared.currentUser(token: token) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch result {
                    case .success(let currentUser):
                        self.user = currentUser
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

    private func buildInterface() {
        header.translatesAutoresizingMaskIntoConstraints = false
        header.backgroundColor = AetherTheme.panel
        view.addSubview(header)

        let backButton = UIButton(type: .system)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = AetherTheme.accent
        backButton.accessibilityLabel = AetherLanguage.string("Back to chats")
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        header.addSubview(backButton)

        headerAvatar.translatesAutoresizingMaskIntoConstraints = false
        headerAvatar.backgroundColor = AetherTheme.accentSoft
        headerAvatar.tintColor = AetherTheme.accent
        headerAvatar.contentMode = .scaleAspectFill
        headerAvatar.clipsToBounds = true
        headerAvatar.layer.cornerRadius = 22
        if let directConversation {
            headerAvatar.image = avatarImage(from: directConversation.user.avatar) ?? UIImage(systemName: "person.fill")
        } else {
            headerAvatar.image = UIImage(systemName: "number")
        }
        header.addSubview(headerAvatar)

        channelTitle.translatesAutoresizingMaskIntoConstraints = false
        channelTitle.textColor = AetherTheme.text
        channelTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        channelTitle.lineBreakMode = .byTruncatingTail
        header.addSubview(channelTitle)

        channelSubtitle.translatesAutoresizingMaskIntoConstraints = false
        channelSubtitle.textColor = AetherTheme.secondary
        channelSubtitle.font = .systemFont(ofSize: 12)
        channelSubtitle.numberOfLines = 1
        channelSubtitle.lineBreakMode = .byTruncatingTail
        header.addSubview(channelSubtitle)

        channelStrip.translatesAutoresizingMaskIntoConstraints = false
        channelStrip.axis = .horizontal
        channelStrip.alignment = .center
        channelStrip.spacing = 9
        channelStrip.distribution = .fill
        channelScrollView.translatesAutoresizingMaskIntoConstraints = false
        channelScrollView.showsHorizontalScrollIndicator = false
        channelScrollView.alwaysBounceHorizontal = true
        channelScrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 12)
        view.addSubview(channelScrollView)
        channelScrollView.addSubview(channelStrip)

        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = AetherTheme.border.withAlphaComponent(0.55)
        view.addSubview(divider)

        messageScroll.translatesAutoresizingMaskIntoConstraints = false
        messageScroll.alwaysBounceVertical = true
        messageScroll.keyboardDismissMode = .interactive
        messageScroll.backgroundColor = UIColor(red: 0.94, green: 0.93, blue: 0.89, alpha: 1)
        view.addSubview(messageScroll)

        messageStack.translatesAutoresizingMaskIntoConstraints = false
        messageStack.axis = .vertical
        messageStack.spacing = 10
        messageScroll.addSubview(messageStack)

        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.axis = .vertical
        emptyStateView.alignment = .center
        emptyStateView.spacing = 10
        emptyStateView.isLayoutMarginsRelativeArrangement = true
        emptyStateView.layoutMargins = UIEdgeInsets(top: 22, left: 20, bottom: 22, right: 20)
        emptyStateView.backgroundColor = AetherTheme.panel
        AetherTheme.surface(emptyStateView, radius: 22)
        messageScroll.addSubview(emptyStateView)

        emptyStateIcon.translatesAutoresizingMaskIntoConstraints = false
        emptyStateIcon.tintColor = AetherTheme.cyan
        emptyStateIcon.contentMode = .scaleAspectFit
        emptyStateView.addArrangedSubview(emptyStateIcon)
        NSLayoutConstraint.activate([
            emptyStateIcon.widthAnchor.constraint(equalToConstant: 42),
            emptyStateIcon.heightAnchor.constraint(equalToConstant: 42)
        ])

        emptyStateTitle.textColor = AetherTheme.text
        emptyStateTitle.font = .systemFont(ofSize: 17, weight: .bold)
        emptyStateTitle.textAlignment = .center
        emptyStateTitle.numberOfLines = 0
        emptyStateView.addArrangedSubview(emptyStateTitle)

        emptyStateSubtitle.textColor = AetherTheme.secondary
        emptyStateSubtitle.font = .systemFont(ofSize: 13)
        emptyStateSubtitle.textAlignment = .center
        emptyStateSubtitle.numberOfLines = 0
        emptyStateView.addArrangedSubview(emptyStateSubtitle)

        composer.translatesAutoresizingMaskIntoConstraints = false
        composer.backgroundColor = AetherTheme.background
        view.addSubview(composer)

        let composerLine = UIView()
        composerLine.translatesAutoresizingMaskIntoConstraints = false
        composerLine.backgroundColor = AetherTheme.border
        composer.addSubview(composerLine)

        let inputBackground = UIView()
        inputBackground.translatesAutoresizingMaskIntoConstraints = false
        inputBackground.backgroundColor = AetherTheme.panel
        AetherTheme.rounded(inputBackground, radius: 24)
        inputBackground.layer.borderWidth = 1
        inputBackground.layer.borderColor = AetherTheme.border.cgColor
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
        AetherTheme.rounded(sendButton, radius: 18)
        sendButton.addTarget(self, action: #selector(sendMessage), for: .touchUpInside)
        inputBackground.addSubview(sendButton)

        activity.translatesAutoresizingMaskIntoConstraints = false
        activity.color = AetherTheme.cyan
        view.addSubview(activity)

        channelStripHeightConstraint = channelScrollView.heightAnchor.constraint(equalToConstant: 50)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 62),
            backButton.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 8),
            backButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 36),
            backButton.heightAnchor.constraint(equalToConstant: 44),
            headerAvatar.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 2),
            headerAvatar.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            headerAvatar.widthAnchor.constraint(equalToConstant: 44),
            headerAvatar.heightAnchor.constraint(equalToConstant: 44),
            channelTitle.leadingAnchor.constraint(equalTo: headerAvatar.trailingAnchor, constant: 11),
            channelTitle.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -14),
            channelTitle.topAnchor.constraint(equalTo: header.topAnchor, constant: 13),
            channelSubtitle.leadingAnchor.constraint(equalTo: channelTitle.leadingAnchor),
            channelSubtitle.trailingAnchor.constraint(equalTo: channelTitle.trailingAnchor),
            channelSubtitle.topAnchor.constraint(equalTo: channelTitle.bottomAnchor, constant: 3),

            channelScrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            channelScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            channelScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            channelStripHeightConstraint!,
            channelStrip.leadingAnchor.constraint(equalTo: channelScrollView.contentLayoutGuide.leadingAnchor),
            channelStrip.trailingAnchor.constraint(equalTo: channelScrollView.contentLayoutGuide.trailingAnchor),
            channelStrip.topAnchor.constraint(equalTo: channelScrollView.contentLayoutGuide.topAnchor),
            channelStrip.bottomAnchor.constraint(equalTo: channelScrollView.contentLayoutGuide.bottomAnchor),
            channelStrip.heightAnchor.constraint(equalTo: channelScrollView.frameLayoutGuide.heightAnchor),
            divider.topAnchor.constraint(equalTo: channelScrollView.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            messageScroll.topAnchor.constraint(equalTo: divider.bottomAnchor),
            messageScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            messageScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            messageStack.topAnchor.constraint(equalTo: messageScroll.contentLayoutGuide.topAnchor, constant: 14),
            messageStack.leadingAnchor.constraint(equalTo: messageScroll.frameLayoutGuide.leadingAnchor, constant: 12),
            messageStack.trailingAnchor.constraint(equalTo: messageScroll.frameLayoutGuide.trailingAnchor, constant: -12),
            messageStack.bottomAnchor.constraint(equalTo: messageScroll.contentLayoutGuide.bottomAnchor, constant: -14),
            messageStack.heightAnchor.constraint(greaterThanOrEqualTo: messageScroll.frameLayoutGuide.heightAnchor),
            emptyStateView.centerXAnchor.constraint(equalTo: messageScroll.frameLayoutGuide.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: messageScroll.frameLayoutGuide.centerYAnchor),
            emptyStateView.widthAnchor.constraint(lessThanOrEqualTo: messageScroll.frameLayoutGuide.widthAnchor, constant: -36),
            emptyStateView.leadingAnchor.constraint(greaterThanOrEqualTo: messageScroll.frameLayoutGuide.leadingAnchor, constant: 18),
            emptyStateView.trailingAnchor.constraint(lessThanOrEqualTo: messageScroll.frameLayoutGuide.trailingAnchor, constant: -18),

            composer.topAnchor.constraint(equalTo: messageScroll.bottomAnchor),
            composer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
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
            AetherTheme.rounded(button, radius: 14)
            if channel.id == selectedChannel?.id {
                button.layer.shadowColor = AetherTheme.accent.cgColor
                button.layer.shadowOpacity = 0.22
                button.layer.shadowRadius = 6
                button.layer.shadowOffset = CGSize(width: 0, height: 3)
            } else {
                button.layer.borderWidth = 1
                button.layer.borderColor = AetherTheme.border.withAlphaComponent(0.45).cgColor
            }
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
        channelSubtitle.text = channel.serverID == nil
            ? AetherLanguage.string("Aether community")
            : AetherLanguage.string("Community channel")
        headerAvatar.image = UIImage(systemName: "number")
        updateEmptyStateText()
        if let placeholder = composer.viewWithTag(702) as? UILabel {
            placeholder.text = "\(AetherLanguage.string("Message")) #\(channel.name)"
        }
        renderChannels()
        renderMessages([])
        reloadSelectedChannel()
    }

    private func updateDirectHeader() {
        guard let directConversation else { return }
        channelTitle.text = directConversation.user.username
        channelSubtitle.text = AetherLanguage.string("Aether private chat")
        headerAvatar.image = avatarImage(from: directConversation.user.avatar) ?? UIImage(systemName: "person.fill")
    }

    private func avatarImage(from dataURL: String?) -> UIImage? {
        guard let dataURL,
              let encoded = dataURL.split(separator: ",", maxSplits: 1).last,
              let data = Data(base64Encoded: String(encoded)) else { return nil }
        return UIImage(data: data)
    }

    @objc private func goBack() {
        navigationController?.popViewController(animated: true)
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
            messageStack.isHidden = true
            emptyStateView.isHidden = false
            return
        }
        emptyStateView.isHidden = true
        messageStack.isHidden = false
        items.forEach { messageStack.addArrangedSubview(makeMessageView($0)) }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let bottom = CGPoint(x: 0, y: max(0, self.messageScroll.contentSize.height - self.messageScroll.bounds.height))
            self.messageScroll.setContentOffset(bottom, animated: false)
        }
    }

    private func makeMessageView(_ message: ChatMessage) -> UIView {
        let isOutgoing = message.userID == user.id
        let row = UIView()
        let bubble = UIStackView()
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.axis = .vertical
        bubble.spacing = 4
        bubble.isLayoutMarginsRelativeArrangement = true
        bubble.layoutMargins = UIEdgeInsets(top: 7, left: 11, bottom: 6, right: 9)
        bubble.backgroundColor = isOutgoing
            ? UIColor(red: 0.84, green: 0.95, blue: 0.82, alpha: 1)
            : AetherTheme.panel
        AetherTheme.rounded(bubble, radius: 15)
        row.addSubview(bubble)

        if directConversation == nil && !isOutgoing {
            let sender = UILabel()
            sender.text = message.username
            sender.textColor = AetherTheme.accent
            sender.font = .systemFont(ofSize: 12, weight: .semibold)
            bubble.addArrangedSubview(sender)
        }

        let body = UILabel()
        body.text = message.content
        body.textColor = AetherTheme.text
        let messageFontSize = UserDefaults.standard.double(forKey: "aether.messageFontSize")
        body.font = .systemFont(ofSize: messageFontSize == 0 ? 15 : messageFontSize)
        body.numberOfLines = 0
        bubble.addArrangedSubview(body)

        let footer = UIStackView()
        footer.axis = .horizontal
        footer.alignment = .center
        footer.spacing = 3
        let time = UILabel()
        time.text = DateFormatter.localizedString(from: message.createdAt, dateStyle: .none, timeStyle: .short)
        time.textColor = AetherTheme.muted
        time.font = .systemFont(ofSize: 10)
        footer.addArrangedSubview(time)
        if isOutgoing {
            let checkmark = UIImageView(image: UIImage(systemName: "checkmark"))
            checkmark.tintColor = AetherTheme.accent
            checkmark.contentMode = .scaleAspectFit
            NSLayoutConstraint.activate([
                checkmark.widthAnchor.constraint(equalToConstant: 11),
                checkmark.heightAnchor.constraint(equalToConstant: 11)
            ])
            footer.addArrangedSubview(checkmark)
        }
        bubble.addArrangedSubview(footer)

        let isGroupChat = directConversation == nil
        let leading = bubble.leadingAnchor.constraint(equalTo: row.leadingAnchor)
        let trailing = bubble.trailingAnchor.constraint(equalTo: row.trailingAnchor)
        leading.isActive = !isOutgoing
        trailing.isActive = isOutgoing
        if isOutgoing {
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: row.leadingAnchor, constant: 42).isActive = true
        } else {
            bubble.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -42).isActive = true
        }
        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: row.topAnchor, constant: 2),
            bubble.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -2),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: row.widthAnchor, multiplier: isGroupChat ? 0.82 : 0.86)
        ])
        return row
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
        emptyStateView.isHidden = true
        messageStack.isHidden = false
        messages.append(message)
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
        updateEmptyStateText()
        if directConversation != nil {
            updateDirectHeader()
        } else if let selectedChannel {
            channelTitle.text = selectedChannel.name
            channelSubtitle.text = selectedChannel.serverID == nil
                ? AetherLanguage.string("Aether community")
                : AetherLanguage.string("Community channel")
            renderChannels()
            if let placeholder = composer.viewWithTag(702) as? UILabel {
                placeholder.text = "\(AetherLanguage.string("Message")) #\(selectedChannel.name)"
            }
        }
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
