import SwiftUI
import UIKit

/// Displays and hides a full-screen overlay window above all other content.
/// Currently used to show a "No Wi-Fi" message when the device is offline.
final class WindowManager {
    static let shared = WindowManager()

    private var overlayWindow: UIWindow?

    func showNoWiFi() {
        guard overlayWindow == nil else { return }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first
        else { return }

        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        let hostingController = UIHostingController(rootView: NoWiFiOverlayView())
        hostingController.view.backgroundColor = .clear
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        overlayWindow = window
    }

    func hideNoWiFi() {
        overlayWindow?.isHidden = true
        overlayWindow = nil
    }
}

// MARK: - NoWiFiOverlayView

private struct NoWiFiOverlayView: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            ContentUnavailableView {
                Label("No Wi-Fi Connection", systemImage: "wifi.slash")
            } description: {
                VStack(spacing: 10) {
                    Text("Kodi devices can only be reached over Wi-Fi. Please connect to the same network as your Kodi device.")
                    Button("Enable Debug Mode") {
                        UserDefaults.standard.set(true, forKey: "debug_mode")
                        WindowManager.shared.hideNoWiFi()
                    }
                }
            }
        }
    }
}
