import BSWFoundation
import Observation

/// The reusable, UI-framework-agnostic view model shared by the SwiftUI app (`DemoUI`) and the
/// React website (via the `DemoBridge` WASM target). It exercises a cross-section of BSWFoundation:
/// a network GET via `APIClient`, a persisted value via a property wrapper, and observable state.
// SKIP @bridge
@Observable
@MainActor
public final class ViewModel {

    /// The caller's IP, fetched once at init.
    public var ipAddress: String

    /// A value that changes on a timer, to demonstrate live observation.
    public var randomNumber: Int = 0

    /// A persisted, bumpable counter.
    public var counter: Int {
        get {
            access(keyPath: \.counter)
            return ___counter
        }
        set {
            withMutation(keyPath: \.counter) {
                ___counter = newValue
            }
        }
    }

    // `UserDefaultsBacked<Int>` isn't supported on wasm/Android (only Bool/String); the Codable
    // variant serialises through JSON and works on every platform (localStorage on wasm).
    @ObservationIgnored
    @CodableUserDefaultsBacked(key: "counter", defaultValue: 0)
    private var ___counter: Int!

    @ObservationIgnored
    private var ___randomNumberTask: Task<Void, Never>!

    public init() async throws {
        let apiClient = APIClient(environment: HTTPBin.Hosts.production)
        let ipRequest = APIClient.Request<HTTPBin.Responses.IP>(endpoint: HTTPBin.API.ip)
        ipAddress = try await apiClient.perform(ipRequest).origin

        ___randomNumberTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.randomNumber = Int.random(in: 0...100)
            }
        }
    }

    public func bump() {
        counter += 1
    }
}
