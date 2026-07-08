//  BIShareNearbyPlugin.swift
//  Offline "Nearby" transfer over MultipeerConnectivity (iOS + macOS), bridged to
//  Flutter via a MethodChannel + EventChannel. This is a faithful port of the
//  native `PeerService` so a Flutter device interoperates BYTE-FOR-BYTE with the
//  native BIShare app on the same `bishare-nearby` service:
//
//    • Send   — `sendResource()` for on-disk files (OS-optimised streaming). The
//               resource name is `RESOURCE:` + base64(JSON meta).
//    • Receive — handles BOTH the `RESOURCE:` flow and the in-memory chunked
//               `META:` / `DATA:` / `END:` framing a native sender may use, and
//               streams either straight to a temp file.
//
//  The plugin does NOT name/move/record the received file — it emits a `received`
//  event with the temp path + metadata and lets Dart finalize it through the SAME
//  ReceiveNaming + save-location + HistoryRepository path as TCP/QUIC receives.
//
//  NOTE: add this file to the Runner target in Xcode (iOS and macOS) — like the
//  Share Extension — so it compiles into the app.

import Foundation
import MultipeerConnectivity

#if canImport(Flutter)
  import Flutter
  public typealias BINPluginRegistrar = FlutterPluginRegistrar
#elseif canImport(FlutterMacOS)
  import FlutterMacOS
  public typealias BINPluginRegistrar = FlutterPluginRegistrar
#endif

public final class BIShareNearbyPlugin: NSObject, FlutterPlugin {
  private static let methodChannelName = "app.bishare/nearby"
  private static let eventChannelName = "app.bishare/nearby/events"
  private static let serviceType = "bishare-nearby"

  private var events: FlutterEventSink?

  // MPC
  private var peerID: MCPeerID?
  private var session: MCSession?
  private var advertiser: MCNearbyServiceAdvertiser?
  private var browser: MCNearbyServiceBrowser?
  private var alias = "BIShare"
  private var fingerprint = ""

  // Discovered peers, keyed by displayName. Value carries the resolved MCPeerID.
  private var peers: [String: MCPeerID] = [:]
  private var aliases: [String: String] = [:]
  private var states: [String: String] = [:] // displayName -> PeerState

  // Stream-to-disk receive state (chunked META/DATA/END path), keyed by peer.
  private var recvHandles: [MCPeerID: FileHandle] = [:]
  private var recvTempURLs: [MCPeerID: URL] = [:]
  private var recvMeta: [MCPeerID: [String: String]] = [:]
  private var recvExpected: [MCPeerID: Int64] = [:]
  private var recvGot: [MCPeerID: Int64] = [:]

  // sendResource() progress KVO retention, keyed by the peer's displayName.
  private var resourceObservations: [String: NSKeyValueObservation] = [:]

  // Adaptive chunk size for the in-memory fallback send (byte-exact with native).
  private let minChunk = 32 * 1024
  private let maxChunk = 1024 * 1024
  private var chunk = 128 * 1024

  // MARK: - Registration

  public static func register(with registrar: BINPluginRegistrar) {
    let instance = BIShareNearbyPlugin()
    #if canImport(FlutterMacOS)
      let messenger = registrar.messenger
    #else
      let messenger = registrar.messenger()
    #endif
    let method = FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
    let event = FlutterEventChannel(name: eventChannelName, binaryMessenger: messenger)
    registrar.addMethodCallDelegate(instance, channel: method)
    event.setStreamHandler(instance)
  }

  // MARK: - MethodChannel

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "configure":
      alias = args["alias"] as? String ?? alias
      fingerprint = args["fingerprint"] as? String ?? ""
      setupIfNeeded()
      result(nil)
    case "start":
      setupIfNeeded()
      advertiser?.startAdvertisingPeer()
      browser?.startBrowsingForPeers()
      result(nil)
    case "stop":
      advertiser?.stopAdvertisingPeer()
      browser?.stopBrowsingForPeers()
      session?.disconnect()
      peers.removeAll(); aliases.removeAll(); states.removeAll()
      emitPeers()
      result(nil)
    case "connect":
      if let id = args["peerId"] as? String { connect(displayName: id) }
      result(nil)
    case "send":
      let id = args["peerId"] as? String ?? ""
      let items = args["items"] as? [[String: Any]] ?? []
      send(displayName: id, items: items)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Setup

  private func setupIfNeeded() {
    if session != nil { return }
    let pid = MCPeerID(displayName: alias)
    peerID = pid
    let s = MCSession(peer: pid, securityIdentity: nil, encryptionPreference: .required)
    s.delegate = self
    session = s
    let adv = MCNearbyServiceAdvertiser(
      peer: pid,
      discoveryInfo: ["alias": alias, "fingerprint": fingerprint],
      serviceType: Self.serviceType
    )
    adv.delegate = self
    advertiser = adv
    let br = MCNearbyServiceBrowser(peer: pid, serviceType: Self.serviceType)
    br.delegate = self
    browser = br
  }

  private func connect(displayName: String) {
    guard let peer = peers[displayName], let session else { return }
    setState(displayName, "connecting")
    browser?.invitePeer(peer, to: session, withContext: nil, timeout: 30)
  }

  // MARK: - Send (sendResource for on-disk files — the Flutter path always has a URL)

  private func send(displayName: String, items: [[String: Any]]) {
    guard let peer = peers[displayName], let session else { return }
    if !session.connectedPeers.contains(peer) {
      connect(displayName: displayName)
      DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
        self?.send(displayName: displayName, items: items)
      }
      return
    }
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else { return }
      for (index, item) in items.enumerated() {
        let name = item["name"] as? String ?? "file"
        let type = item["type"] as? String ?? "application/octet-stream"
        let size = Int64((item["size"] as? Int) ?? 0)
        guard let path = item["path"] as? String,
              FileManager.default.fileExists(atPath: path) else { continue }
        self.emit(["event": "transferStart", "direction": "send", "fileName": name])
        let meta: [String: String] = [
          "fileName": name, "fileType": type, "size": "\(size)",
          "index": "\(index)", "total": "\(items.count)",
        ]
        let metaJSON = (try? JSONSerialization.data(withJSONObject: meta)) ?? Data()
        let resourceName = "RESOURCE:" + metaJSON.base64EncodedString()
        let sem = DispatchSemaphore(value: 0)
        var sendErr: Error?
        let progress = session.sendResource(
          at: URL(fileURLWithPath: path), withName: resourceName, toPeer: peer
        ) { error in sendErr = error; sem.signal() }
        if let progress {
          let obs = progress.observe(\.fractionCompleted) { [weak self] p, _ in
            self?.emit(["event": "progress", "direction": "send",
                        "fileName": name, "progress": p.fractionCompleted])
          }
          sem.wait()
          obs.invalidate()
        } else {
          sem.wait()
        }
        if let sendErr {
          self.emit(["event": "error", "message": sendErr.localizedDescription])
        }
      }
      self.emit(["event": "transferDone", "direction": "send"])
      self.setState(displayName, "completed")
    }
  }

  // MARK: - Events

  private func emit(_ payload: [String: Any]) {
    DispatchQueue.main.async { self.events?(payload) }
  }

  private func emitPeers() {
    let list = peers.keys.map { id -> [String: Any] in
      ["id": id, "alias": aliases[id] ?? id, "state": states[id] ?? "discovered"]
    }
    emit(["event": "peers", "peers": list])
  }

  private func setState(_ displayName: String, _ state: String) {
    states[displayName] = state
    emitPeers()
  }

  // MARK: - Receive helpers

  private func emitReceived(tempURL: URL, meta: [String: String], senderAlias: String) {
    let attrs = try? FileManager.default.attributesOfItem(atPath: tempURL.path)
    let size = (attrs?[.size] as? Int) ?? 0
    emit([
      "event": "received",
      "tempPath": tempURL.path,
      "fileName": meta["fileName"] ?? "file",
      "fileType": meta["fileType"] ?? "application/octet-stream",
      "size": size,
      "senderAlias": senderAlias,
    ])
  }

  private func cleanupRecv(_ peerID: MCPeerID) {
    recvHandles[peerID]?.closeFile()
    if let url = recvTempURLs[peerID] { try? FileManager.default.removeItem(at: url) }
    recvHandles.removeValue(forKey: peerID)
    recvTempURLs.removeValue(forKey: peerID)
    recvMeta.removeValue(forKey: peerID)
    recvExpected.removeValue(forKey: peerID)
    recvGot.removeValue(forKey: peerID)
  }
}

// MARK: - MCSessionDelegate

extension BIShareNearbyPlugin: MCSessionDelegate {
  public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
    switch state {
    case .connected: setState(peerID.displayName, "connected")
    case .connecting: setState(peerID.displayName, "connecting")
    case .notConnected:
      setState(peerID.displayName, "discovered")
      cleanupRecv(peerID)
    @unknown default: setState(peerID.displayName, "discovered")
    }
  }

  // Chunked META/DATA/END protocol → stream straight to a temp file.
  public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
    guard data.count > 4 else { return }
    let prefix = String(data: data.prefix(5), encoding: .utf8) ?? ""
    if prefix == "META:" {
      let json = data.dropFirst(5)
      guard let meta = try? JSONSerialization.jsonObject(with: Data(json)) as? [String: String]
      else { return }
      cleanupRecv(peerID)
      recvMeta[peerID] = meta
      if let s = meta["size"], let n = Int64(s) { recvExpected[peerID] = n; recvGot[peerID] = 0 }
      let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".nearby")
      FileManager.default.createFile(atPath: temp.path, contents: nil)
      if let h = FileHandle(forWritingAtPath: temp.path) {
        recvHandles[peerID] = h
        recvTempURLs[peerID] = temp
      }
      emit(["event": "transferStart", "direction": "receive",
            "fileName": meta["fileName"] ?? ""])
    } else if prefix == "DATA:" {
      let chunk = data.dropFirst(5)
      recvHandles[peerID]?.write(Data(chunk))
      recvGot[peerID] = (recvGot[peerID] ?? 0) + Int64(chunk.count)
      if let exp = recvExpected[peerID], exp > 0 {
        emit(["event": "progress", "direction": "receive",
              "fileName": recvMeta[peerID]?["fileName"] ?? "",
              "progress": Double(recvGot[peerID] ?? 0) / Double(exp)])
      }
    } else if data.prefix(4) == "END:".data(using: .utf8)! {
      guard let meta = recvMeta[peerID] else { return }
      recvHandles[peerID]?.closeFile()
      recvHandles.removeValue(forKey: peerID)
      if let temp = recvTempURLs[peerID] {
        emitReceived(tempURL: temp, meta: meta, senderAlias: peerID.displayName)
        recvTempURLs.removeValue(forKey: peerID)
      }
      recvMeta.removeValue(forKey: peerID)
      recvExpected.removeValue(forKey: peerID)
      recvGot.removeValue(forKey: peerID)
      emit(["event": "transferDone", "direction": "receive"])
    }
  }

  // sendResource() flow.
  public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                      fromPeer peerID: MCPeerID, with progress: Progress) {
    if resourceName.hasPrefix("RESOURCE:"),
       let data = Data(base64Encoded: String(resourceName.dropFirst("RESOURCE:".count))),
       let meta = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
      emit(["event": "transferStart", "direction": "receive",
            "fileName": meta["fileName"] ?? ""])
    }
    let obs = progress.observe(\.fractionCompleted) { [weak self] p, _ in
      self?.emit(["event": "progress", "direction": "receive",
                  "progress": p.fractionCompleted])
    }
    resourceObservations[peerID.displayName] = obs
  }

  public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                      fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
    resourceObservations[peerID.displayName]?.invalidate()
    resourceObservations.removeValue(forKey: peerID.displayName)
    guard error == nil, let localURL else {
      emit(["event": "error", "message": error?.localizedDescription ?? "resource receive failed"])
      return
    }
    var meta: [String: String] = [:]
    if resourceName.hasPrefix("RESOURCE:"),
       let data = Data(base64Encoded: String(resourceName.dropFirst("RESOURCE:".count))),
       let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
      meta = parsed
    }
    // localURL is a temp file owned by MPC; copy to our own temp so Dart can move it.
    let temp = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".nearby")
    do { try FileManager.default.moveItem(at: localURL, to: temp) }
    catch { try? FileManager.default.copyItem(at: localURL, to: temp) }
    emitReceived(tempURL: temp, meta: meta, senderAlias: peerID.displayName)
    emit(["event": "transferDone", "direction": "receive"])
  }

  public func session(_ session: MCSession, didReceive stream: InputStream,
                      withName streamName: String, fromPeer peerID: MCPeerID) {}
}

// MARK: - Advertiser / Browser delegates

extension BIShareNearbyPlugin: MCNearbyServiceAdvertiserDelegate {
  public func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                         didReceiveInvitationFromPeer peerID: MCPeerID,
                         withContext context: Data?,
                         invitationHandler: @escaping (Bool, MCSession?) -> Void) {
    invitationHandler(true, session) // auto-accept nearby invitations (native parity)
  }

  public func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                         didNotStartAdvertisingPeer error: Error) {
    emit(["event": "error", "message": error.localizedDescription])
  }
}

extension BIShareNearbyPlugin: MCNearbyServiceBrowserDelegate {
  public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                      withDiscoveryInfo info: [String: String]?) {
    peers[peerID.displayName] = peerID
    aliases[peerID.displayName] = info?["alias"] ?? peerID.displayName
    if states[peerID.displayName] == nil { states[peerID.displayName] = "discovered" }
    emitPeers()
  }

  public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
    peers.removeValue(forKey: peerID.displayName)
    aliases.removeValue(forKey: peerID.displayName)
    states.removeValue(forKey: peerID.displayName)
    emitPeers()
  }

  public func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
    emit(["event": "error", "message": error.localizedDescription])
  }
}

// MARK: - EventChannel stream handler

extension BIShareNearbyPlugin: FlutterStreamHandler {
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError? {
    self.events = events
    emitPeers()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    events = nil
    return nil
  }
}
