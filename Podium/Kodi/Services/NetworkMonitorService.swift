import Network
import Combine
import SwiftUI

/// Observes the device's network path and publishes whether it is currently
/// connected to a Wi-Fi interface. Used to show the "No Wi-Fi" overlay.
final class NetworkMonitorService: ObservableObject {
    /// `true` when the network path is satisfied over a Wi-Fi interface.
    @Published private(set) var isConnectedToWiFi = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.thaesler.podium.network-monitor", qos: .utility)

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnectedToWiFi =
                    path.status == .satisfied &&
                    path.usesInterfaceType(.wifi)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
