import Foundation

/// Where the speech backend runs. The simulator reaches the Mac at localhost; a device
/// needs the Mac's network address and the server started with `--host 0.0.0.0`.
///
/// The `-api <url>` launch argument is remembered, so later launches from the home screen
/// use it too.
public enum ServerSettings {
    public static let defaultBaseURL = URL(string: "http://localhost:8000")!
    public static let key = "apiBaseURL"

    public static var baseURL: URL {
        get {
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-api"), i + 1 < args.count {
                UserDefaults.standard.set(args[i + 1], forKey: key)
            }
            return UserDefaults.standard.string(forKey: key).flatMap(URL.init(string:)) ?? defaultBaseURL
        }
        set { UserDefaults.standard.set(newValue.absoluteString, forKey: key) }
    }

    /// The listening endpoint of a backend: http://mac:8000 -> ws://mac:8000/listen.
    public static func listenURL(base: URL) -> URL? {
        var components = URLComponents(url: base.appendingPathComponent("listen"),
                                       resolvingAgainstBaseURL: false)
        components?.scheme = base.scheme == "https" ? "wss" : "ws"
        return components?.url
    }
}
