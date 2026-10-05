import UIKit

enum AppConfiguration {
    static let apiBaseURL = URL(string: "https://br-sparkling-tooth-b5r4xarr-aether.compute.c-7.us-east-2.aws.neon.tech/")!
}

enum AetherTheme {
    static let background = UIColor(red: 0.055, green: 0.063, blue: 0.094, alpha: 1)
    static let panel = UIColor(red: 0.091, green: 0.103, blue: 0.145, alpha: 1)
    static let elevated = UIColor(red: 0.125, green: 0.141, blue: 0.192, alpha: 1)
    static let accent = UIColor(red: 0.55, green: 0.44, blue: 0.96, alpha: 1)
    static let cyan = UIColor(red: 0.31, green: 0.83, blue: 0.90, alpha: 1)
    static let text = UIColor(red: 0.95, green: 0.96, blue: 0.99, alpha: 1)
    static let secondary = UIColor(red: 0.62, green: 0.66, blue: 0.74, alpha: 1)
    static let muted = UIColor(red: 0.38, green: 0.42, blue: 0.51, alpha: 1)
    static let danger = UIColor(red: 1, green: 0.40, blue: 0.43, alpha: 1)

    static func rounded(_ view: UIView, radius: CGFloat = 14) {
        view.layer.cornerRadius = radius
        view.layer.cornerCurve = .continuous
    }
}
