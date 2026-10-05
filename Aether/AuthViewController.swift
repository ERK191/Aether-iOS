import UIKit

final class AuthViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let iconView = UIImageView(image: UIImage(named: "AetherMark"))
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let usernameField = UITextField()
    private let passwordField = UITextField()
    private let actionButton = UIButton(type: .system)
    private let modeButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let activity = UIActivityIndicatorView(style: .medium)
    private var isCreatingAccount = false

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.setNavigationBarHidden(true, animated: false)
        view.backgroundColor = AetherTheme.background
        buildInterface()
        restoreSession()
    }

    private func buildInterface() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.layer.cornerRadius = 30
        iconView.clipsToBounds = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Aether"
        titleLabel.textColor = AetherTheme.text
        titleLabel.font = .systemFont(ofSize: 36, weight: .bold)
        titleLabel.textAlignment = .center

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Find your people. Join the conversation."
        subtitleLabel.textColor = AetherTheme.secondary
        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 2

        usernameField.translatesAutoresizingMaskIntoConstraints = false
        usernameField.font = .systemFont(ofSize: 16)
        usernameField.placeholder = "Username"
        usernameField.textColor = AetherTheme.text
        usernameField.autocapitalizationType = .none
        usernameField.autocorrectionType = .no
        usernameField.textContentType = .username
        usernameField.returnKeyType = .next
        usernameField.backgroundColor = AetherTheme.panel
        usernameField.layer.borderColor = AetherTheme.elevated.cgColor
        usernameField.layer.borderWidth = 1
        usernameField.layer.cornerRadius = 15
        usernameField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 1))
        usernameField.leftViewMode = .always

        passwordField.translatesAutoresizingMaskIntoConstraints = false
        passwordField.font = .systemFont(ofSize: 16)
        passwordField.placeholder = "Password · 8 characters minimum"
        passwordField.textColor = AetherTheme.text
        passwordField.isSecureTextEntry = true
        passwordField.textContentType = .password
        passwordField.returnKeyType = .go
        passwordField.backgroundColor = AetherTheme.panel
        passwordField.layer.borderColor = AetherTheme.elevated.cgColor
        passwordField.layer.borderWidth = 1
        passwordField.layer.cornerRadius = 15
        passwordField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 1))
        passwordField.leftViewMode = .always

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.setTitle("Log in", for: .normal)
        actionButton.setTitleColor(.white, for: .normal)
        actionButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        actionButton.backgroundColor = AetherTheme.accent
        actionButton.layer.cornerRadius = 15
        actionButton.addTarget(self, action: #selector(submitCredentials), for: .touchUpInside)

        modeButton.translatesAutoresizingMaskIntoConstraints = false
        modeButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        modeButton.setTitle("New here?  Create an account", for: .normal)
        modeButton.setTitleColor(AetherTheme.cyan, for: .normal)
        modeButton.addTarget(self, action: #selector(toggleMode), for: .touchUpInside)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = AetherTheme.danger
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        activity.translatesAutoresizingMaskIntoConstraints = false
        activity.color = .white
        activity.hidesWhenStopped = true

        [iconView, titleLabel, subtitleLabel, usernameField, passwordField, actionButton,
         modeButton, statusLabel, activity].forEach(contentView.addSubview)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 70),
            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 112),
            iconView.heightAnchor.constraint(equalToConstant: 112),
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            usernameField.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 40),
            usernameField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            usernameField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            usernameField.heightAnchor.constraint(equalToConstant: 54),
            passwordField.topAnchor.constraint(equalTo: usernameField.bottomAnchor, constant: 12),
            passwordField.leadingAnchor.constraint(equalTo: usernameField.leadingAnchor),
            passwordField.trailingAnchor.constraint(equalTo: usernameField.trailingAnchor),
            passwordField.heightAnchor.constraint(equalToConstant: 54),
            actionButton.topAnchor.constraint(equalTo: passwordField.bottomAnchor, constant: 18),
            actionButton.leadingAnchor.constraint(equalTo: usernameField.leadingAnchor),
            actionButton.trailingAnchor.constraint(equalTo: usernameField.trailingAnchor),
            actionButton.heightAnchor.constraint(equalToConstant: 54),
            modeButton.topAnchor.constraint(equalTo: actionButton.bottomAnchor, constant: 14),
            modeButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            modeButton.heightAnchor.constraint(equalToConstant: 42),
            statusLabel.topAnchor.constraint(equalTo: modeButton.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: usernameField.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: usernameField.trailingAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -35),
            activity.centerXAnchor.constraint(equalTo: actionButton.centerXAnchor),
            activity.centerYAnchor.constraint(equalTo: actionButton.centerYAnchor)
        ])

        usernameField.addTarget(self, action: #selector(focusPassword), for: .editingDidEndOnExit)
        passwordField.addTarget(self, action: #selector(submitCredentials), for: .editingDidEndOnExit)
        usernameField.attributedPlaceholder = NSAttributedString(
            string: "Username",
            attributes: [.foregroundColor: AetherTheme.muted]
        )
        passwordField.attributedPlaceholder = NSAttributedString(
            string: "Password · 8 characters minimum",
            attributes: [.foregroundColor: AetherTheme.muted]
        )
    }

    private func restoreSession() {
        guard let token = SessionStore.load() else { return }
        setLoading(true)
        ChatService.shared.currentUser(token: token) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.setLoading(false)
                switch result {
                case .success(let user):
                    self.openChat(user: user, token: token)
                case .failure:
                    SessionStore.delete()
                }
            }
        }
    }

    @objc private func focusPassword() {
        passwordField.becomeFirstResponder()
    }

    @objc private func toggleMode() {
        isCreatingAccount.toggle()
        actionButton.setTitle(isCreatingAccount ? "Create account" : "Log in", for: .normal)
        modeButton.setTitle(
            isCreatingAccount ? "Already have an account?  Log in" : "New here?  Create an account",
            for: .normal
        )
        passwordField.textContentType = isCreatingAccount ? .newPassword : .password
        statusLabel.text = nil
    }

    @objc private func submitCredentials() {
        view.endEditing(true)
        statusLabel.text = nil
        guard ChatService.shared.isConfigured else {
            statusLabel.text = "The Aether server address still needs to be set up."
            return
        }
        guard let username = usernameField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let password = passwordField.text else {
            statusLabel.text = "Enter your username and password."
            return
        }
        setLoading(true)
        let finish: (Result<AuthResponse, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.setLoading(false)
                switch result {
                case .success(let response):
                    guard SessionStore.save(token: response.token) else {
                        self.statusLabel.text = "Could not securely save your sign-in. Please try again."
                        return
                    }
                    self.openChat(user: response.user, token: response.token)
                case .failure(let error):
                    self.statusLabel.text = error.localizedDescription
                }
            }
        }

        if isCreatingAccount {
            ChatService.shared.register(username: username, password: password, completion: finish)
        } else {
            ChatService.shared.login(username: username, password: password, completion: finish)
        }
    }

    private func setLoading(_ loading: Bool) {
        actionButton.isEnabled = !loading
        modeButton.isEnabled = !loading
        actionButton.alpha = loading ? 0.7 : 1
        if loading { activity.startAnimating() } else { activity.stopAnimating() }
    }

    private func openChat(user: ChatUser, token: String) {
        let chat = ChatViewController(user: user, token: token)
        navigationController?.setViewControllers([chat], animated: true)
    }
}
