import Foundation
import Network
import Combine
import OSLog

// MARK: - DiscoveredDevice

struct DiscoveredDevice: Identifiable, Hashable {
    let id = UUID()
    let host: String
    let port: Int
    let jsonRPCEnabled: Bool
}

// MARK: - NetworkScannerService

/// Scans the local subnet for Kodi instances by probing TCP port 8080 and
/// confirming a valid JSON-RPC response. Results are published incrementally
/// as hosts are found.
@MainActor
final class NetworkScannerService: ObservableObject {
    private static let logger = Logger(subsystem: "com.kodiwidget", category: "NetworkScanner")
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var statusText: String = "Tap Scan to start"

    private let concurrency = 30
    private let timeout: TimeInterval = 1.0

    // MARK: - Public interface

    /// Starts a network scan in a detached task. Safe to call from sync contexts.
    func scan(port: Int = 8080) {
        guard !isScanning else { return }
        Task { await runScan(port: port) }
    }

    /// Starts a network scan and suspends until it completes.
    /// Use with SwiftUI's `.refreshable` modifier.
    func scanAsync(port: Int = 8080) async {
        guard !isScanning else { return }
        await runScan(port: port)
    }

    func cancel() {
        isScanning = false
    }

    // MARK: - Probe

    /// Checks whether a host responds on the given TCP port and is a Kodi JSON-RPC endpoint.
    func probe(host: String, port: Int) async -> DiscoveredDevice? {
        guard await isTCPReachable(host: host, port: port) else { return nil }
        let isKodi = await verifyKodiJSONRPC(host: host, port: port)
        return DiscoveredDevice(host: host, port: port, jsonRPCEnabled: isKodi)
    }

    // MARK: - Private

    private func runScan(port: Int) async {
        devices = []
        progress = 0
        isScanning = true

        guard let subnet = localSubnet() else {
            statusText = "Could not determine local subnet"
            isScanning = false
            return
        }
        statusText = "Scanning…"

        let hosts = (1...254).map { "\(subnet).\($0)" }
        var checked = 0

        await withTaskGroup(of: DiscoveredDevice?.self) { group in
            var index = 0

            for _ in 0..<min(concurrency, hosts.count) {
                let host = hosts[index]; index += 1
                group.addTask { await self.probe(host: host, port: port) }
            }

            for await result in group {
                guard isScanning else { group.cancelAll(); break }
                if let device = result { devices.append(device) }
                checked += 1
                progress = Double(checked) / Double(hosts.count)
                if index < hosts.count {
                    let host = hosts[index]; index += 1
                    group.addTask { await self.probe(host: host, port: port) }
                }
            }
        }

        statusText = isScanning
            ? "^[Found \(devices.count) \("device")](inflect: true)"
            : "Scan cancelled"
        isScanning = false
    }

    /// Returns the first three octets of the device's Wi-Fi IP (e.g. `"192.168.1"`).
    private func localSubnet() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(first) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = cursor {
            let ifa = ptr.pointee
            let name = String(cString: ifa.ifa_name)
            if name.hasPrefix("en"),
               ifa.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(
                    ifa.ifa_addr, socklen_t(ifa.ifa_addr.pointee.sa_len),
                    &hostname, socklen_t(hostname.count),
                    nil, 0, NI_NUMERICHOST
                )
                let ip = String(cString: hostname)
                let parts = ip.split(separator: ".")
                if parts.count == 4 {
                    return parts.prefix(3).joined(separator: ".")
                }
            }
            cursor = ifa.ifa_next
        }
        return nil
    }

    /// Performs a raw TCP connect with a timeout.
    private func isTCPReachable(host: String, port: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            var resumed = false
            let lock = NSLock()

            func finish(_ value: Bool) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: value)
            }

            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: UInt16(port)),
                using: .tcp
            )

            let timer = DispatchWorkItem {
                connection.cancel()
                finish(false)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    timer.cancel()
                    connection.cancel()
                    finish(true)
                case .failed, .cancelled:
                    timer.cancel()
                    finish(false)
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    /// Sends a JSON-RPC ping to confirm the host is running Kodi.
    private func verifyKodiJSONRPC(host: String, port: Int) async -> Bool {
        guard let url = URL(string: "http://\(host):\(port)/jsonrpc") else { return false }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "method": "JSONRPC.Ping",
            "id": 1
        ])
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["result"] as? String) == "pong"
        else { return false }
        return true
    }
}
