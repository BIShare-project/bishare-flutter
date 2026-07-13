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
    /// A staged file on disk. The body is STREAMED from here (never held in
    /// memory) — an iOS extension's ~120 MB jetsam limit would kill a large
    /// video that we buffered as `Data`.
    let url: URL
    let size: Int
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

    // Discovery self-healing: a Local-Network-denied/pending browser sits in
    // `.waiting(PolicyDenied)` and NEVER calls browseResultsChangedHandler, so we
    // must observe `stateUpdateHandler` and recreate the browser with backoff (a
    // permission `.waiting` does NOT auto-recover to `.ready` after the grant).
    private var discoveryRestartAttempts = 0
    private var discoveryRetryWorkItem: DispatchWorkItem?
    // Tier-2 fallback (mirrors the main app's subnet probe) runs at most once.
    private var didSubnetProbe = false

    enum Status {
        case loading, ready, sending, completed, error, needsLocalNetwork
    }

    // MARK: - Start

    func start() {
        loadFiles()
        startDiscovery()
        scheduleSubnetProbeFallback()
    }

    // MARK: - Discovery via Bonjour TXT Records + HTTP Probe

    private func startDiscovery() {
        // Tear down any prior browser/retry so repeated calls (self-heal /
        // Retry) don't leak or stack handlers.
        discoveryRetryWorkItem?.cancel()
        browser?.cancel()

        let params = NWParameters()
        params.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: kBonjourType, domain: nil), using: params)
        self.browser = browser

        // Observe browser state — without this a Local-Network-denied/pending
        // browser fails SILENTLY (empty list forever). `.waiting`/`.failed` ==
        // permission not (yet) granted (PolicyDenied / -65570); recreate with
        // backoff so the moment the grant lands, results flow.
        browser.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.discoveryRestartAttempts = 0
            case .waiting, .failed:
                self.scheduleDiscoveryRestart()
            default:
                break
            }
        }

        browser.browseResultsChangedHandler = { [weak self] _, changes in
            guard let self else { return }
            // Any delivered result proves the grant is live — clear the error UI.
            DispatchQueue.main.async {
                if self.status == .needsLocalNetwork { self.status = .ready }
            }
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

        browser.start(queue: queue)
    }

    /// Recreate the browser with capped backoff after a `.waiting`/`.failed`
    /// state. After several failed bring-ups with nothing to show, surface an
    /// actionable "enable Local Network" screen instead of an infinite spinner.
    private func scheduleDiscoveryRestart() {
        discoveryRestartAttempts += 1
        if discoveryRestartAttempts >= 4 {
            DispatchQueue.main.async {
                if self.devices.isEmpty && self.status == .ready {
                    self.status = .needsLocalNetwork
                }
            }
        }
        let work = DispatchWorkItem { [weak self] in self?.startDiscovery() }
        discoveryRetryWorkItem?.cancel()
        discoveryRetryWorkItem = work
        let delay = Double(min(discoveryRestartAttempts, 4)) * 2.0 // 2s,4s,6s,8s…
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// User-driven retry from the "needs Local Network" screen.
    func retryDiscovery() {
        discoveryRestartAttempts = 0
        didSubnetProbe = false
        status = .ready
        startDiscovery()
        scheduleSubnetProbeFallback()
    }

    // MARK: - Tier-2 fallback: subnet unicast probe (mirrors the main app)

    /// If mDNS yields nothing shortly after launch, sweep the /24 with a short
    /// `GET /api/v1/info` — covers APs/VPNs that throttle multicast but pass
    /// unicast. Needs the SAME Local Network grant as the browser, so it can't
    /// bypass a missing permission; it just widens coverage when the grant IS
    /// present. Runs at most once (extension is modal/short-lived).
    private func scheduleSubnetProbeFallback() {
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.devices.isEmpty, self.status == .ready, !self.didSubnetProbe else { return }
                self.didSubnetProbe = true
                self.queue.async { self.runSubnetProbe() }
            }
        }
    }

    private func runSubnetProbe() {
        guard let selfIP = Self.localIPv4(), let dot = selfIP.lastIndex(of: ".") else { return }
        let base = String(selfIP[selfIP.startIndex..<dot])           // "192.168.1"
        let selfHost = Int(selfIP[selfIP.index(after: dot)...])
        let session = URLSession(configuration: .ephemeral)
        for h in 1...254 where h != selfHost {
            let host = "\(base).\(h)"
            guard let url = URL(string: "http://\(host):\(kMainPort)/api/v1/info") else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 1.2
            session.dataTask(with: req) { [weak self] data, resp, _ in
                guard let self, let data,
                      let http = resp as? HTTPURLResponse, http.statusCode == 200,
                      let info = try? JSONDecoder().decode(ProbeDeviceInfo.self, from: data) else { return }
                let device = ShareDevice(
                    id: info.fingerprint, name: info.alias, host: host,
                    port: kMainPort, model: info.deviceModel ?? "",
                    deviceType: info.deviceType ?? "mobile"
                )
                DispatchQueue.main.async {
                    if self.status == .needsLocalNetwork { self.status = .ready }
                    if let idx = self.devices.firstIndex(where: { $0.id == device.id }) {
                        self.devices[idx] = device
                    } else {
                        self.devices.append(device)
                    }
                }
            }.resume()
        }
    }

    /// This device's Wi-Fi (en0) IPv4, for the /24 base of the subnet sweep.
    private static func localIPv4() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let iface = cur.pointee
            if iface.ifa_addr.pointee.sa_family == UInt8(AF_INET),
               String(cString: iface.ifa_name) == "en0" {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(iface.ifa_addr, socklen_t(iface.ifa_addr.pointee.sa_len),
                               &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    address = String(cString: host)
                }
            }
            ptr = iface.ifa_next
        }
        return address
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

                // Bracket an IPv6 literal (and drop its %zone) so the receiver
                // doesn't throw "Invalid port" parsing `Host: fe80::…:port`.
                let hostHdr = host.contains(":")
                    ? "[\(host.split(separator: "%").first.map(String.init) ?? host)]"
                    : host
                let httpReq = "GET /api/v1/info HTTP/1.1\r\nHost: \(hostHdr):\(kMainPort)\r\nConnection: close\r\n\r\n"
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
                    // Prefer the peer's self-reported IPv4 (`ip`) over the resolved
                    // endpoint host. Apple↔Apple mDNS resolves to an fe80:: link-
                    // local that routes over AWDL (peer-to-peer Wi-Fi) — slow for
                    // bulk transfer (<1 MB/s) — whereas the IPv4 rides the fast
                    // infrastructure Wi-Fi the main app uses.
                    let reported = info.ip ?? ""
                    let resolvedHost = (!reported.isEmpty && !reported.contains(":") && reported != "127.0.0.1")
                        ? reported
                        : host
                    let device = ShareDevice(
                        id: info.fingerprint,
                        name: info.alias,
                        host: resolvedHost,
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
        let tmp = FileManager.default.temporaryDirectory

        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                let type = [UTType.image.identifier, UTType.movie.identifier, UTType.item.identifier]
                    .first { provider.hasItemConformingToTypeIdentifier($0) } ?? UTType.item.identifier
                group.enter()

                // Preferred path: a file-backed item (photo/video). Copy it out of
                // the provider's transient temp into ours by STREAMING (copyItem
                // never loads the bytes into memory) so a large video can't blow
                // the extension's ~120 MB memory limit.
                provider.loadFileRepresentation(forTypeIdentifier: type) { [weak self] srcURL, _ in
                    guard let self else { group.leave(); return }
                    if let srcURL {
                        let dest = tmp.appendingPathComponent("\(UUID().uuidString)-\(srcURL.lastPathComponent)")
                        if (try? FileManager.default.copyItem(at: srcURL, to: dest)) != nil {
                            let size = ((try? FileManager.default.attributesOfItem(atPath: dest.path))?[.size] as? Int) ?? 0
                            let mime = UTType(filenameExtension: dest.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                            DispatchQueue.main.async {
                                self.files.append(ShareFile(name: srcURL.lastPathComponent, url: dest, size: size, mimeType: mime))
                            }
                        }
                        group.leave()
                        return
                    }
                    // Fallback for non-file items (text / URL) — tiny; stage to a temp file.
                    provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                        defer { group.leave() }
                        var payload: Data?
                        var name = "\(UUID().uuidString).dat"
                        if let d = item as? Data {
                            payload = d
                        } else if let u = item as? URL {
                            payload = u.isFileURL ? try? Data(contentsOf: u) : u.absoluteString.data(using: .utf8)
                            name = u.lastPathComponent
                        } else if let s = item as? String {
                            payload = s.data(using: .utf8); name = "shared.txt"
                        }
                        let dest = tmp.appendingPathComponent(name)
                        guard let payload, (try? payload.write(to: dest)) != nil else { return }
                        let mime = UTType(filenameExtension: dest.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                        DispatchQueue.main.async {
                            self.files.append(ShareFile(name: name, url: dest, size: payload.count, mimeType: mime))
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
                    // No sha256: hashing would re-read the whole file into memory,
                    // and a PLAINTEXT upload carrying sha256 makes the receiver run
                    // pure-Dart SHA-256 per chunk — its single biggest speed cost
                    // (the ~600 KB/s). Integrity rides on TCP; the main app also
                    // omits sha256 for large files.
                    fileMetadatas[fid] = [
                        "id": fid, "fileName": file.name,
                        "size": file.size, "fileType": file.mimeType
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

                // Step 2: STREAM each file from disk (`fromFile:` never buffers the
                // whole file in memory → no jetsam on large files) with byte-level
                // progress via the task delegate → the iOS sheet advances instead
                // of sitting at 0%.
                let fileCount = files.count
                for (i, file) in files.enumerated() {
                    let fid = "file-\(i)"
                    let token = prepareResp.files[fid] ?? ""

                    await MainActor.run { currentFileName = file.name }

                    // Upload over a raw NWConnection with Nagle OFF (see uploadFile).
                    // URLSession leaves Nagle ON with no API to disable it, which —
                    // against macOS delayed-ACK — pinned throughput at ~1 MB/s.
                    let query = "sessionId=\(prepareResp.sessionId)&fileId=\(fid)&token=\(token)"
                    var lastEmit = Date.distantPast
                    try await uploadFile(file, to: device.host, port: device.port, query: query) { [weak self] frac in
                        // #2: throttle the main-thread hop to ~10/s — a hop per
                        // socket write would saturate the extension's main thread.
                        let now = Date()
                        if now.timeIntervalSince(lastEmit) < 0.1 { return }
                        lastEmit = now
                        Task { @MainActor in self?.progress = (Double(i) + frac) / Double(fileCount) }
                    }
                    await MainActor.run { progress = Double(i + 1) / Double(fileCount) }
                }

                await MainActor.run {
                    progress = 1.0
                    status = .completed
                }

                // Remove the staged temp files.
                for f in files { try? FileManager.default.removeItem(at: f.url) }

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

    // MARK: - Upload transport (Nagle OFF)

    /// POST the staged file to `/api/v1/upload` over a raw NWConnection with
    /// `tcp.noDelay = true`. URLSession leaves Nagle ON with no public API to
    /// disable it → against macOS delayed-ACK it stalls ~40 ms per window,
    /// pinning throughput at ~1 MB/s. dart:io (the fast main app) sets tcpNoDelay
    /// on its client sockets; this gives the extension the same. The body is
    /// streamed from disk in 1 MB reads (bounded RAM — jetsam-safe).
    private func uploadFile(_ file: ShareFile, to host: String, port: UInt16,
                            query: String, onProgress: @escaping (Double) -> Void) async throws {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true // <-- the fix
        let params = NWParameters(tls: nil, tcp: tcp)
        let conn = NWConnection(host: NWEndpoint.Host(host),
                                port: NWEndpoint.Port(rawValue: port)!, using: params)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            // Connect-timeout: NWConnection sits in `.waiting` indefinitely if the
            // peer is unreachable; cancel it so the send can't hang uncancellably.
            let timeout = DispatchWorkItem { conn.cancel() }
            queue.asyncAfter(deadline: .now() + 15, execute: timeout)
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    timeout.cancel(); conn.stateUpdateHandler = nil; cont.resume()
                case .failed(let e):
                    timeout.cancel(); conn.stateUpdateHandler = nil; cont.resume(throwing: e)
                case .cancelled:
                    conn.stateUpdateHandler = nil
                    cont.resume(throwing: ShareError.uploadFailed(file.name))
                default:
                    break
                }
            }
            conn.start(queue: queue)
        }
        defer { conn.cancel() }

        // HTTP/1.1 request head — Content-Length framing, close after response.
        // Bracket an IPv6 literal (dropping its %zone) so the receiver's dart:io
        // parser doesn't reject `Host: fe80::…:port` with "Invalid port". The
        // connection (NWEndpoint.Host) keeps the zone for link-local routing;
        // HTTP Host headers don't carry zones. Apple↔Apple mDNS often resolves a
        // peer to an fe80:: link-local, so this path is common.
        let hostHdr = host.contains(":")
            ? "[\(host.split(separator: "%").first.map(String.init) ?? host)]"
            : host
        let head = "POST /api/v1/upload?\(query) HTTP/1.1\r\n" +
            "Host: \(hostHdr):\(port)\r\n" +
            "Content-Type: application/octet-stream\r\n" +
            "Content-Length: \(file.size)\r\n" +
            "Connection: close\r\n\r\n"
        try await sendAll(conn, Data(head.utf8))

        // Stream the body in 1 MB reads — never buffers the whole file.
        let fh = try FileHandle(forReadingFrom: file.url)
        defer { try? fh.close() }
        var sent = 0
        while true {
            let chunk = fh.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            try await sendAll(conn, chunk)
            sent += chunk.count
            onProgress(file.size > 0 ? Double(sent) / Double(file.size) : 1)
        }

        switch try await receiveStatus(conn) {
        case 200: return
        case 401: throw ShareError.pinRequired
        case 403: throw ShareError.rejected
        default: throw ShareError.uploadFailed(file.name)
        }
    }

    /// Send `data` and await its handoff to TCP — natural backpressure so the
    /// next 1 MB read waits until this write drains (bounded RAM).
    ///
    /// `isComplete: false` is CRITICAL: on a raw TCP NWConnection the default
    /// `isComplete: true` half-closes the send side (FIN) after the FIRST send —
    /// which would end the stream right after the request head and drop the whole
    /// body. The body is framed by Content-Length, so no FIN is needed; the
    /// connection is torn down (`conn.cancel()`) once the response is read.
    private func sendAll(_ conn: NWConnection, _ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, contentContext: .defaultMessage, isComplete: false,
                      completion: .contentProcessed { error in
                          if let error { cont.resume(throwing: error) } else { cont.resume() }
                      })
        }
    }

    /// Read the response up to the status line and return its code (e.g. 200).
    private func receiveStatus(_ conn: NWConnection) async throws -> Int {
        var buffer = Data()
        while buffer.count < 4096 {
            let (data, isComplete) = try await receiveOnce(conn)
            if let data { buffer.append(data) }
            if let nl = buffer.range(of: Data("\r\n".utf8)) {
                let line = String(data: buffer[..<nl.lowerBound], encoding: .utf8) ?? ""
                let parts = line.split(separator: " ") // "HTTP/1.1 200 OK"
                return parts.count >= 2 ? (Int(parts[1]) ?? 0) : 0
            }
            if isComplete { break }
        }
        return 0
    }

    private func receiveOnce(_ conn: NWConnection) async throws -> (Data?, Bool) {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(Data?, Bool), Error>) in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: (data, isComplete)) }
            }
        }
    }

    func cancel() {
        discoveryRetryWorkItem?.cancel()
        browser?.cancel()
        probeConnections.forEach { $0.cancel() }
        extensionContext?.cancelRequest(withError: NSError(domain: "app.bishare.share", code: 0))
    }

    deinit {
        discoveryRetryWorkItem?.cancel()
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
    let ip: String?
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
                case .needsLocalNetwork:
                    localNetworkHelpView
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

    // MARK: - Needs Local Network

    private var localNetworkHelpView: some View {
        VStack(spacing: 18) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Color.bishareBlue)
            Text(String(localized: "Enable Local Network access"))
                .font(.headline)
            Text(String(localized: "Open Settings › BIShare and turn on Local Network, then tap Retry so BIShare can find nearby devices."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(String(localized: "Retry")) { vm.retryDiscovery() }
                .buttonStyle(.borderedProminent)
                .tint(.bishareBlue)
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
