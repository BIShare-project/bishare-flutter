import UIKit
import SwiftUI
import Network
import UniformTypeIdentifiers
import CryptoKit

// MARK: - BIShare protocol constants (mirrors lib/core/constants/protocol.dart)
//
// This Share Extension is fully self-contained: it discovers nearby BIShare
// receivers over Bonjour and uploads the shared files directly via the
// LocalSend-compatible HTTP protocol (POST /api/v1/prepare + /api/v1/upload).
// It has ZERO dependency on the Flutter app, plugins, or Swift packages —
// only Apple frameworks. Ported from the native iOS BIShare ShareExtension.

private let kBonjourType = "_bishare._tcp"
private let kMainPort: UInt16 = 58317

extension Color {
    /// BIShare brand blue (#2563EB) — matches the Flutter app's default accent.
    static let bishareBlue = Color(red: 37.0 / 255, green: 99.0 / 255, blue: 235.0 / 255)
}

// MARK: - Share View Controller

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Required for Mac Catalyst share extension to show popover
        preferredContentSize = CGSize(width: 400, height: 500)

        let shareView = ShareExtensionView(extensionContext: extensionContext)
        let hostingController = UIHostingController(rootView: shareView)
        hostingController.preferredContentSize = CGSize(width: 400, height: 500)

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        hostingController.didMove(toParent: self)
    }
}

// MARK: - Discovered Device (Share Extension)

struct ShareDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let host: String
    let port: UInt16
    let model: String
    let deviceType: String

    var icon: String {
        switch deviceType {
        case "desktop": return "desktopcomputer"
        case "tablet": return "tablet.landscape"
        case "mobile": return "candybarphone"
        default: return "desktopcomputer"
        }
    }
}

// MARK: - Share File

struct ShareFile {
    let name: String
    let data: Data
    let mimeType: String
}

// MARK: - View Model

@Observable
class ShareViewModel {
    var devices: [ShareDevice] = []
    var files: [ShareFile] = []
    var status: Status = .loading
    var progress: Double = 0
    var currentFileName: String = ""
    var errorMessage: String?
    var selectedDevice: ShareDevice?

    weak var extensionContext: NSExtensionContext?

    private var browser: NWBrowser?
    private var probeConnections: [NWConnection] = []
    private let queue = DispatchQueue(label: "app.bishare.share.discovery", qos: .userInitiated)

    enum Status {
        case loading, ready, sending, completed, error
    }

    // MARK: - Start

    func start() {
        loadFiles()
        startDiscovery()
    }

    // MARK: - Discovery via Bonjour TXT Records + HTTP Probe

    private func startDiscovery() {
        let params = NWParameters()
        params.includePeerToPeer = true

        browser = NWBrowser(for: .bonjour(type: kBonjourType, domain: nil), using: params)

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self else { return }
            for change in changes {
                switch change {
                case .added(let result):
                    self.resolveDevice(result)
                case .removed(let result):
                    if case .service(let name, _, _, _) = result.endpoint {
                        DispatchQueue.main.async {
                            self.devices.removeAll { $0.id == name }
                        }
                    }
                case .changed(old: _, new: let result, flags: _):
                    self.resolveDevice(result)
                default:
                    break
                }
            }
        }

        browser?.start(queue: queue)
    }

    private func resolveDevice(_ result: NWBrowser.Result) {
        guard case .service(let name, _, _, _) = result.endpoint else { return }

        // Fast path: read TXT record
        if case .bonjour(let txtRecord) = result.metadata {
            let txt = parseTXT(txtRecord)
            let ip = txt["ip"] ?? ""
            let alias = txt["alias"] ?? name

            if !ip.isEmpty && ip != "127.0.0.1" {
                let port = UInt16(txt["port"] ?? "") ?? kMainPort
                let device = ShareDevice(
                    id: txt["fingerprint"] ?? name,
                    name: alias,
                    host: ip,
                    port: port,
                    model: txt["model"] ?? "",
                    deviceType: txt["deviceType"] ?? "mobile"
                )
                DispatchQueue.main.async {
                    if let idx = self.devices.firstIndex(where: { $0.id == device.id }) {
                        self.devices[idx] = device
                    } else {
                        self.devices.append(device)
                    }
                }
                return
            }
        }

        // Slow path: connect to endpoint and probe /api/v1/info
        let connection = NWConnection(to: result.endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state {
                let host = self.extractHost(from: connection)
                guard let host, host != "unknown" else {
                    connection.cancel()
                    return
                }

                let httpReq = "GET /api/v1/info HTTP/1.1\r\nHost: \(host):\(kMainPort)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(httpReq.utf8), completion: .contentProcessed { _ in
                    self.receiveProbeResponse(connection: connection, host: host, serviceName: name)
                })
            } else if case .failed = state {
                connection.cancel()
            }
        }

        probeConnections.append(connection)
        connection.start(queue: queue)

        // Timeout
        queue.asyncAfter(deadline: .now() + 4) {
            if connection.state != .cancelled { connection.cancel() }
        }
    }

    private func receiveProbeResponse(connection: NWConnection, host: String, serviceName: String, buffer: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { connection.cancel(); return }

            var accumulated = buffer
            if let content { accumulated.append(content) }

            let separator = Data("\r\n\r\n".utf8)
            if let headerEnd = accumulated.range(of: separator) {
                let body = accumulated[headerEnd.upperBound...]
                if let info = try? JSONDecoder().decode(ProbeDeviceInfo.self, from: Data(body)) {
                    let device = ShareDevice(
                        id: info.fingerprint,
                        name: info.alias,
                        host: host,
                        port: kMainPort,
                        model: info.deviceModel ?? "",
                        deviceType: info.deviceType ?? "mobile"
                    )
                    DispatchQueue.main.async {
                        if let idx = self.devices.firstIndex(where: { $0.id == device.id }) {
                            self.devices[idx] = device
                        } else {
                            self.devices.append(device)
                        }
                    }
                }
                connection.cancel()
                return
            }

            if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receiveProbeResponse(connection: connection, host: host, serviceName: serviceName, buffer: accumulated)
            }
        }
    }

    private func extractHost(from connection: NWConnection) -> String? {
        guard let endpoint = connection.currentPath?.remoteEndpoint,
              case .hostPort(let host, _) = endpoint else { return nil }
        switch host {
        case .ipv4(let addr): return "\(addr)"
        case .ipv6(let addr): return "\(addr)"
        case .name(let n, _): return n
        @unknown default: return nil
        }
    }

    private func parseTXT(_ txtRecord: NWTXTRecord) -> [String: String] {
        var dict: [String: String] = [:]
        for key in ["alias", "model", "deviceType", "fingerprint", "version", "ip", "port", "quicPort"] {
            if let value = txtRecord[key] { dict[key] = value }
        }
        return dict
    }

    // MARK: - Load Shared Files

    private func loadFiles() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            status = .ready
            return
        }

        let group = DispatchGroup()

        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                group.enter()

                let types = [UTType.image.identifier, UTType.movie.identifier, UTType.item.identifier]
                let matchedType = types.first { provider.hasItemConformingToTypeIdentifier($0) } ?? UTType.item.identifier

                provider.loadItem(forTypeIdentifier: matchedType, options: nil) { [weak self] item, _ in
                    defer { group.leave() }

                    if let url = item as? URL {
                        let accessing = url.startAccessingSecurityScopedResource()
                        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                        if let data = try? Data(contentsOf: url) {
                            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                            DispatchQueue.main.async {
                                self?.files.append(ShareFile(name: url.lastPathComponent, data: data, mimeType: mime))
                            }
                        }
                    } else if let data = item as? Data {
                        let ext = matchedType == UTType.image.identifier ? "jpg" : "dat"
                        let mime = matchedType == UTType.image.identifier ? "image/jpeg" : "application/octet-stream"
                        DispatchQueue.main.async {
                            self?.files.append(ShareFile(name: "\(UUID().uuidString).\(ext)", data: data, mimeType: mime))
                        }
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.status = .ready
        }
    }

    // MARK: - URL Helper

    private func baseURL(for device: ShareDevice) -> String {
        // IPv6 addresses need brackets in URLs
        let host = device.host.contains(":") ? "[\(device.host)]" : device.host
        return "http://\(host):\(device.port)"
    }

    // MARK: - Send Transfer

    func sendTo(device: ShareDevice) {
        if files.isEmpty {
            errorMessage = String(localized: "No files to send")
            status = .error
            return
        }
        if device.host.isEmpty {
            errorMessage = String(localized: "Device address not resolved. Try again.")
            status = .error
            return
        }

        selectedDevice = device
        status = .sending
        progress = 0

        Task {
            do {
                let base = baseURL(for: device)

                // Step 1: POST /api/v1/prepare
                var fileMetadatas: [String: [String: Any]] = [:]
                for (i, file) in files.enumerated() {
                    let fid = "file-\(i)"
                    let sha = SHA256.hash(data: file.data).map { String(format: "%02x", $0) }.joined()
                    fileMetadatas[fid] = [
                        "id": fid, "fileName": file.name,
                        "size": file.data.count, "fileType": file.mimeType, "sha256": sha
                    ]
                }

                let body: [String: Any] = [
                    "info": [
                        "alias": UIDevice.current.name,
                        "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0",
                        "deviceModel": UIDevice.current.model,
                        "deviceType": "mobile",
                        "fingerprint": UUID().uuidString,
                        "port": Int(kMainPort),
                        "protocol": "https",
                        "download": false
                    ],
                    "files": fileMetadatas
                ]

                guard let url = URL(string: "\(base)/api/v1/prepare") else {
                    throw ShareError.invalidResponse
                }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
                req.timeoutInterval = 30

                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse else { throw ShareError.invalidResponse }

                switch http.statusCode {
                case 200: break
                case 401: throw ShareError.pinRequired
                case 403: throw ShareError.rejected
                default: throw ShareError.serverError(http.statusCode)
                }

                let prepareResp = try JSONDecoder().decode(PrepareResp.self, from: data)

                // Step 2: Upload each file
                for (i, file) in files.enumerated() {
                    let fid = "file-\(i)"
                    let token = prepareResp.files[fid] ?? ""

                    await MainActor.run {
                        currentFileName = file.name
                        progress = Double(i) / Double(files.count)
                    }

                    guard let uploadURL = URL(string: "\(base)/api/v1/upload?sessionId=\(prepareResp.sessionId)&fileId=\(fid)&token=\(token)") else {
                        throw ShareError.uploadFailed(file.name)
                    }
                    var uploadReq = URLRequest(url: uploadURL)
                    uploadReq.httpMethod = "POST"
                    uploadReq.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                    uploadReq.httpBody = file.data
                    uploadReq.timeoutInterval = 120

                    let (_, uploadResp) = try await URLSession.shared.data(for: uploadReq)
                    guard let uploadHttp = uploadResp as? HTTPURLResponse, uploadHttp.statusCode == 200 else {
                        throw ShareError.uploadFailed(file.name)
                    }
                }

                await MainActor.run {
                    progress = 1.0
                    status = .completed
                }

                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run { self.extensionContext?.completeRequest(returningItems: nil) }

            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    status = .error
                }
            }
        }
    }

    func cancel() {
        browser?.cancel()
        probeConnections.forEach { $0.cancel() }
        extensionContext?.cancelRequest(withError: NSError(domain: "app.bishare.share", code: 0))
    }

    deinit {
        browser?.cancel()
        probeConnections.forEach { $0.cancel() }
    }
}

// MARK: - Response Types

struct PrepareResp: Codable {
    let sessionId: String
    let files: [String: String]
}

struct ProbeDeviceInfo: Codable {
    let alias: String
    let fingerprint: String
    let deviceModel: String?
    let deviceType: String?
}

enum ShareError: LocalizedError {
    case invalidResponse, rejected, pinRequired, serverError(Int), uploadFailed(String)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return String(localized: "Invalid response")
        case .rejected: return String(localized: "Transfer rejected")
        case .pinRequired: return String(localized: "PIN required — open BIShare to enter PIN")
        case .serverError(let c): return String(localized: "Server error (\(c))")
        case .uploadFailed(let n): return String(localized: "Failed: \(n)")
        }
    }
}

// MARK: - Share Extension View

struct ShareExtensionView: View {
    weak var extensionContext: NSExtensionContext?
    @State private var vm = ShareViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                switch vm.status {
                case .loading:
                    ProgressView("Loading files…")
                        .tint(.bishareBlue)
                case .ready:
                    if vm.devices.isEmpty { searchingView } else { deviceList }
                case .sending:
                    sendingView
                case .completed:
                    completedView
                case .error:
                    errorView
                }
            }
            .navigationTitle("Send via BIShare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { vm.cancel() }
                }
            }
        }
        .tint(.bishareBlue)
        .onAppear {
            vm.extensionContext = extensionContext
            vm.start()
        }
    }

    // MARK: - Searching

    private var searchingView: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.bishareBlue.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Color.bishareBlue)
            }
            ProgressView().tint(.bishareBlue)
            Text("Searching nearby devices…")
                .font(.headline)
            Text("Make sure BIShare is open on the other device")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !vm.files.isEmpty {
                Text("^[\(vm.files.count) file](inflect: true) ready to send")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.bishareBlue)
                    .padding(.top, 4)
            }
        }
        .padding(32)
    }

    // MARK: - Device list

    private var deviceList: some View {
        List {
            if !vm.files.isEmpty {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.on.doc.fill")
                            .foregroundStyle(Color.bishareBlue)
                        Text("^[\(vm.files.count) file](inflect: true)")
                            .fontWeight(.medium)
                        Spacer()
                        Text(vm.files.map { $0.name }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } header: {
                    Text("Files")
                }
            }

            Section {
                ForEach(vm.devices) { device in
                    deviceRow(device)
                }
            } header: {
                Text("Nearby Devices")
            }
        }
    }

    @ViewBuilder
    private func deviceRow(_ device: ShareDevice) -> some View {
        if device.host.isEmpty {
            HStack(spacing: 12) {
                ProgressView().frame(width: 40).tint(.bishareBlue)
                Text(device.name).foregroundStyle(.secondary)
                Spacer()
                Text("Connecting…").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        } else {
            Button { vm.sendTo(device: device) } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.bishareBlue.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: device.icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.bishareBlue)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name).foregroundStyle(.primary)
                        Text(device.host).font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(Color.bishareBlue)
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Sending

    private var sendingView: some View {
        VStack(spacing: 20) {
            if let device = vm.selectedDevice {
                Text("Sending to \(device.name)").font(.headline)
            }
            ProgressView(value: vm.progress)
                .progressViewStyle(.linear)
                .tint(.bishareBlue)
                .frame(width: 220)
            Text(vm.currentFileName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("\(Int(vm.progress * 100))%")
                .font(.title.bold().monospacedDigit())
                .foregroundStyle(Color.bishareBlue)
        }
        .padding(32)
    }

    // MARK: - Completed

    private var completedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Sent!").font(.title2.bold())
            if let device = vm.selectedDevice {
                Text("to \(device.name)").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Error

    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text(vm.errorMessage ?? String(localized: "Transfer failed"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") { vm.status = .ready }
                .buttonStyle(.borderedProminent)
                .tint(.bishareBlue)
        }
        .padding(32)
    }
}
