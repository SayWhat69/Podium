import Foundation
import SwiftData

// MARK: - Device

@Model
final class Device {
    var name: String
    var ip: String
    var port: String

    init(name: String, ip: String, port: String) {
        self.name = name
        self.ip = ip
        self.port = port
    }
}

// MARK: - AppSettings

@Model
final class AppSettings {
    var selectedDevice: Device?

    init(selectedDevice: Device? = nil) {
        self.selectedDevice = selectedDevice
    }
}
