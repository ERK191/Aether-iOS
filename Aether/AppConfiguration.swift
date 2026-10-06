import UIKit

enum AppConfiguration {
    static let apiBaseURL = URL(string: "https://br-sparkling-tooth-b5r4xarr-aether.compute.c-7.us-east-2.aws.neon.tech/")!
}

enum AetherTheme {
    static let background = UIColor(red: 0.043, green: 0.051, blue: 0.082, alpha: 1)
    static let panel = UIColor(red: 0.078, green: 0.090, blue: 0.133, alpha: 1)
    static let elevated = UIColor(red: 0.118, green: 0.137, blue: 0.196, alpha: 1)
    static let accent = UIColor(red: 0.47, green: 0.38, blue: 0.98, alpha: 1)
    static let accentSoft = UIColor(red: 0.25, green: 0.20, blue: 0.52, alpha: 1)
    static let cyan = UIColor(red: 0.36, green: 0.88, blue: 0.83, alpha: 1)
    static let border = UIColor(red: 0.22, green: 0.25, blue: 0.34, alpha: 1)
    static let text = UIColor(red: 0.95, green: 0.96, blue: 0.99, alpha: 1)
    static let secondary = UIColor(red: 0.68, green: 0.72, blue: 0.81, alpha: 1)
    static let muted = UIColor(red: 0.45, green: 0.50, blue: 0.60, alpha: 1)
    static let danger = UIColor(red: 1, green: 0.40, blue: 0.43, alpha: 1)

    static func rounded(_ view: UIView, radius: CGFloat = 14) {
        view.layer.cornerRadius = radius
        view.layer.cornerCurve = .continuous
    }

    static func surface(_ view: UIView, radius: CGFloat = 16) {
        rounded(view, radius: radius)
        view.layer.borderWidth = 1
        view.layer.borderColor = border.withAlphaComponent(0.58).cgColor
    }
}
