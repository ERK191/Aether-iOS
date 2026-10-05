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
        window.rootViewController = UINavigationController(rootViewController: AuthViewController())
        window.rootViewController?.view.backgroundColor = AetherTheme.background
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
