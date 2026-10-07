import Foundation
import Network

public struct CastDevice: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// False for speakers and speaker groups.
    public let hasDisplay: Bool
    let endpoint: NWEndpoint

    init?(_ result: NWBrowser.Result) {
        guard case .service(let serviceName, _, _, _) = result.endpoint else { return nil }
        var record: NWTXTRecord?
        if case .bonjour(let txt) = result.metadata { record = txt }
        id = record?["id"] ?? serviceName
        name = record?["fn"] ?? serviceName
        // Bit 0 of the capabilities mask is video out.
        hasDisplay = (record?["ca"].flatMap(Int.init) ?? 0) & 1 == 1
        endpoint = result.endpoint
    }
}

/// Finds Cast devices on the local network.
@MainActor
public final class CastBrowser {
    public var onChange: (([CastDevice]) -> Void)?

    private var browser: NWBrowser?

    public init() {}

    public func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_googlecast._tcp", domain: nil), using: .tcp)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let devices = results.compactMap(CastDevice.init)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            MainActor.assumeIsolated { self?.onChange?(devices) }
        }
        browser.start(queue: .main)
    }

    public func stop() {
        browser?.browseResultsChangedHandler = nil
        browser?.cancel()
        browser = nil
    }
}
