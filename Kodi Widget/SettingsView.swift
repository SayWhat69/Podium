import SwiftUI
import SwiftData

// MARK: - Navigation destination

enum SettingsDestination: Hashable {
    case devicePicker
    case addDevice
}

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings

    @Query private var devices: [Device]

    @State private var skipInterval = "10"
    @State private var path = [SettingsDestination]()
    @State private var isBackgroundModeEnabled = false
    @State private var isLockScreenPlayerEnabled = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                NavigationLink(value: SettingsDestination.devicePicker) {
                    HStack {
                        Text("Device")
                        Spacer()
                        Text(settings.selectedDevice?.name ?? "None")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("General") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Skip Interval")
                        Picker("Skip Interval", selection: $skipInterval) {
                            Text("10s").tag("10")
                            Text("15s").tag("15")
                            Text("30s").tag("30")
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle("Enable Background Mode", isOn: $isBackgroundModeEnabled)
                    Text("When enabled, the app wakes up in the background as soon as Kodi starts playing and begins fetching playback data.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Enable iOS Player Widget", isOn: $isLockScreenPlayerEnabled)
                    Text("Shows playback controls on the Lock Screen and in Control Center while Kodi is playing, so you can pause and skip forward or backward 10 seconds without opening the app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                #if DEBUG
                Section("Debug") {
                    Toggle("Enable Debug Mode", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "debug_mode") },
                        set: { UserDefaults.standard.set($0, forKey: "debug_mode") }
                    ))
                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .devicePicker:
                    SelectDeviceView(settings: settings, path: $path)
                case .addDevice:
                    AddDeviceView(settings: settings, path: $path)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
}

// MARK: - AddDeviceView

struct AddDeviceView: View {
    var settings: AppSettings
    @Binding var path: [SettingsDestination]

    @StateObject private var scanner = NetworkScannerService()

    var body: some View {
        VStack {
            List {
                Section {
                    if scanner.devices.isEmpty && scanner.isScanning {
                        HStack {
                            Text("Searching…")
                                .foregroundStyle(.secondary)
                            Spacer()
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.7)
                                .fixedSize()
                        }
                    }
                    ForEach(scanner.devices) { device in
                        NavigationLink {
                            DeviceDetailView(
                                settings: settings,
                                path: $path,
                                ip: device.host,
                                port: String(device.port)
                            )
                        } label: {
                            HStack {
                                Circle()
                                    .fill(device.jsonRPCEnabled ? .green : .yellow)
                                    .frame(width: 10, height: 10)
                                VStack(alignment: .leading) {
                                    Text(device.host)
                                    Text(String(device.port))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    HStack(spacing: 4) {
                        Text("^[Found \(scanner.devices.count) \("device")](inflect: true)")
                            .font(.footnote)
                        if scanner.isScanning {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.6)
                                .fixedSize()
                        }
                    }
                }

                Section {
                    NavigationLink {
                        DeviceDetailView(settings: settings, path: $path)
                    } label: {
                        HStack {
                            Circle()
                                .fill(.gray)
                                .frame(width: 10, height: 10)
                            Text("Add manually")
                        }
                    }
                } footer: {
                    Text("Use this if your Kodi instance runs on a port other than 8080.")
                }
            }
            .refreshable { await scanner.scanAsync() }
            .onAppear {
                guard !scanner.isScanning && scanner.devices.isEmpty else { return }
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    scanner.scan()
                }
            }
            .onDisappear { scanner.cancel() }
            .navigationTitle("Add Device")
            .navigationBarTitleDisplayMode(.inline)

            Text("Can't find your device? Make sure it's on the same network and that Kodi's web interface is enabled.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
    }
}

// MARK: - DeviceDetailView

struct DeviceDetailView: View {
    var settings: AppSettings
    @Binding var path: [SettingsDestination]
    @Environment(\.modelContext) private var modelContext

    @State private var name: String
    @State private var ip: String
    @State private var port: String
    @State private var isLoading = false
    @State private var showUnreachableAlert = false
    @State private var alertContinuation: CheckedContinuation<Bool, Never>?

    let isHostLocked: Bool
    let isPortLocked: Bool

    init(settings: AppSettings, path: Binding<[SettingsDestination]>, ip: String = "", port: String = "") {
        self.settings = settings
        self._path = path
        self._name = State(initialValue: "")
        self._ip   = State(initialValue: ip)
        self._port = State(initialValue: port)
        self.isHostLocked = !ip.isEmpty
        self.isPortLocked = !port.isEmpty
    }

    var body: some View {
        Form {
            TextField("Device Name", text: $name)
            TextField("Host", text: $ip)
                .disabled(isHostLocked)
                .foregroundStyle(isHostLocked ? .secondary : .primary)
                .keyboardType(.URL)
            TextField("Port", text: $port)
                .disabled(isPortLocked)
                .foregroundStyle(isPortLocked ? .secondary : .primary)
                .keyboardType(.numberPad)
        }
        .navigationTitle("Add Device")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isLoading {
                    ProgressView()
                } else {
                    Button("Add") { Task { await addDevice() } }
                        .disabled(name.isEmpty || ip.isEmpty || port.isEmpty)
                }
            }
        }
        .alert("Device not found", isPresented: $showUnreachableAlert) {
            Button("Add anyway") { resumeContinuation(with: true) }
            Button("Cancel", role: .cancel) { resumeContinuation(with: false) }
        } message: {
            Text("Could not reach \(ip):\(port). Do you still want to add this device?")
        }
    }

    private func resumeContinuation(with result: Bool) {
        alertContinuation?.resume(returning: result)
        alertContinuation = nil
    }

    private func addDevice() async {
        isLoading = true
        defer { isLoading = false }

        let result = await NetworkScannerService().probe(host: ip, port: Int(port) ?? 0)
        if result?.jsonRPCEnabled != true {
            let confirmed = await withCheckedContinuation { continuation in
                alertContinuation = continuation
                showUnreachableAlert = true
            }
            guard confirmed else { return }
        }

        let device = Device(name: name, ip: ip, port: port)
        modelContext.insert(device)
        settings.selectedDevice = device
        path.removeAll()
    }
}

// MARK: - SelectDeviceView

struct SelectDeviceView: View {
    var settings: AppSettings
    @Binding var path: [SettingsDestination]

    @State private var deviceToEdit: Device?
    @Query private var devices: [Device]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            ForEach(devices) { device in
                Button {
                    settings.selectedDevice = device
                    path.removeLast()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text("\(device.ip):\(device.port)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if settings.selectedDevice == device {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .foregroundStyle(.primary)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        modelContext.delete(device)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button { deviceToEdit = device } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
            }
        }
        .navigationTitle("Devices")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: SettingsDestination.addDevice) {
                    Image(systemName: "plus")
                }
            }
        }
        .overlay {
            if devices.isEmpty {
                ContentUnavailableView(
                    "No Devices",
                    systemImage: "tv.slash",
                    description: Text("Add a device to get started.")
                )
            }
        }
        .sheet(item: $deviceToEdit) { device in
            EditDeviceView(device: device)
        }
    }
}

// MARK: - EditDeviceView

struct EditDeviceView: View {
    var device: Device

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var ip: String
    @State private var port: String
    @State private var isLoading = false
    @State private var showUnreachableAlert = false
    @State private var alertContinuation: CheckedContinuation<Bool, Never>?

    init(device: Device) {
        self.device = device
        _name = State(initialValue: device.name)
        _ip   = State(initialValue: device.ip)
        _port = State(initialValue: device.port)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Device Name", text: $name)
                TextField("Host", text: $ip)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Port", text: $port)
                    .keyboardType(.numberPad)
            }
            .navigationTitle("Edit Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(name.isEmpty || ip.isEmpty || port.isEmpty || !hasChanges)
                    }
                }
            }
            .alert("Device not reachable", isPresented: $showUnreachableAlert) {
                Button("Save anyway") { resumeContinuation(with: true) }
                Button("Cancel", role: .cancel) { resumeContinuation(with: false) }
            } message: {
                Text("Could not reach \(ip):\(port). Do you still want to save?")
            }
        }
    }

    private var hasChanges: Bool {
        name != device.name || ip != device.ip || port != device.port
    }

    private func resumeContinuation(with result: Bool) {
        alertContinuation?.resume(returning: result)
        alertContinuation = nil
    }

    private func save() async {
        isLoading = true
        defer { isLoading = false }

        if ip != device.ip || port != device.port {
            let result = await NetworkScannerService().probe(host: ip, port: Int(port) ?? 0)
            if result?.jsonRPCEnabled != true {
                let confirmed = await withCheckedContinuation { continuation in
                    alertContinuation = continuation
                    showUnreachableAlert = true
                }
                guard confirmed else { return }
            }
        }

        device.name = name
        device.ip   = ip
        device.port = port
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
