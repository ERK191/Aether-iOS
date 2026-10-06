import UIKit

enum AppConfiguration {
    static let apiBaseURL = URL(string: "https://br-sparkling-tooth-b5r4xarr-aether.compute.c-7.us-east-2.aws.neon.tech/")!
}

enum AetherTheme {
    static let background = UIColor(red: 0.97, green: 0.97, blue: 0.95, alpha: 1)
    static let panel = UIColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let elevated = UIColor(red: 0.93, green: 0.95, blue: 0.93, alpha: 1)
    static let accent = UIColor(red: 0.04, green: 0.48, blue: 0.39, alpha: 1)
    static let accentSoft = UIColor(red: 0.85, green: 0.95, blue: 0.89, alpha: 1)
    static let cyan = UIColor(red: 0.08, green: 0.54, blue: 0.45, alpha: 1)
    static let border = UIColor(red: 0.87, green: 0.89, blue: 0.87, alpha: 1)
    static let text = UIColor(red: 0.10, green: 0.14, blue: 0.13, alpha: 1)
    static let secondary = UIColor(red: 0.39, green: 0.44, blue: 0.42, alpha: 1)
    static let muted = UIColor(red: 0.55, green: 0.60, blue: 0.57, alpha: 1)
    static let danger = UIColor(red: 0.78, green: 0.19, blue: 0.21, alpha: 1)

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
