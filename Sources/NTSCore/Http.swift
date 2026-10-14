import Foundation

public enum Http {
    /// Names this app and where it lives, so NTS can tell it apart from its own apps and knows who to ask.
    public static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return "NTS-for-Mac/\(version) (+https://github.com/sanderjn/nts-mac)"
    }()

    public static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: configuration)
    }()
}
