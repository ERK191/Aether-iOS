import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.backgroundColor = AetherTheme.background
        self.window = window
        showAuthentication(animated: false)
        window.makeKeyAndVisible()
        return true
    }

    func showAuthentication(animated: Bool = true) {
        let navigationController = UINavigationController(rootViewController: AuthViewController())
        navigationController.view.backgroundColor = AetherTheme.background
        setRootViewController(navigationController, animated: animated)
    }

    func showMain(user: ChatUser, token: String) {
        setRootViewController(MainTabBarController(user: user, token: token), animated: true)
    }

    private func setRootViewController(_ controller: UIViewController, animated: Bool) {
        guard let window else { return }
        guard animated, window.rootViewController != nil else {
            window.rootViewController = controller
            return
        }
        UIView.transition(
            with: window,
            duration: 0.25,
            options: .transitionCrossDissolve,
            animations: { window.rootViewController = controller }
        )
    }
}
