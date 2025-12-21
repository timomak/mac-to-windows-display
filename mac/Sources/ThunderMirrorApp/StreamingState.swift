import Foundation
import SwiftUI
import Logging
import Combine

/// Observable state for the streaming session
@MainActor
class StreamingState: ObservableObject {
    /// Connection state
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case streaming
        case error(String)
        
        var displayText: String {
            switch self {
            case .disconnected:
                return "Ready"
            case .connecting:
                return "Connecting..."
            case .connected:
                return "Connected"
            case .streaming:
                return "Streaming"
            case .error(let message):
                return "Error: \(message)"
            }
        }
        
        var color: Color {
            switch self {
            case .disconnected:
                return .secondary
            case .connecting:
                return .orange
            case .connected:
                return .mint
            case .streaming:
                return .green
            case .error:
                return .red
            }
        }
    }
    
    /// Streaming mode
    enum StreamMode: String, CaseIterable, Identifiable {
        case mirror = "Mirror"
        case extend = "Extend"
        
        var id: String { rawValue }
        
        var isEnabled: Bool {
            switch self {
            case .mirror: return true
            case .extend: return false  // Not yet implemented
            }
        }
    }
    
    // MARK: - Published Properties
    
    @Published var connectionState: ConnectionState = .disconnected
    @Published var targetIP: String = ""  // Empty by default - will auto-discover
    @Published var port: UInt16 = 9999
    
    /// Peer discovery for automatic receiver detection
    @Published var peerDiscovery = PeerDiscovery()
    
    /// Currently selected peer (for UI binding)
    @Published var selectedPeer: DiscoveredPeer?
    
    private var discoverySubscription: AnyCancellable?
    @Published var mode: StreamMode = .mirror
    @Published var bitrateMbps: Int = 50  // Higher default for better quality
    @Published var maxWidth: Int = 1920   // Cap resolution for smooth playback
    @Published var useNativeResolution: Bool = false  // Logical resolution by default
    
    // Stats
    @Published var fps: Double = 0
    @Published var bitrate: Double = 0  // Actual Mbps
    @Published var latencyMs: Double = 0
    @Published var resolution: String = "—"
    @Published var frameCount: UInt64 = 0
    
    // Internal state
    private var streamTask: Task<Void, Never>?
    private var quicClient: QuicClient?
    private var screenCapture: ScreenCapture?
    private var h264Encoder: H264Encoder?
    private var logger = Logger(label: "com.thundermirror.app")
    
    // Stats tracking
    private var lastStatsTime = Date()
    private var framesSinceStats: UInt64 = 0
    private var bytesSinceStats: UInt64 = 0
    private var sequence: UInt64 = 0
    private var startTime = Date()
    
    // Error tracking for resilience
    private var consecutiveSendErrors: Int = 0
    private static let maxConsecutiveErrors: Int = 30  // Allow ~0.5 second of errors at 60fps
    
    // MARK: - Initialization
    
    init() {
        // Start peer discovery automatically
        startDiscovery()
        
        // Subscribe to discovered peers - auto-select first one found
        discoverySubscription = peerDiscovery.$peers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] peers in
                guard let self = self else { return }
                
                // Auto-select first peer if no IP is set
                if self.targetIP.isEmpty, let firstPeer = peers.first {
                    self.selectPeer(firstPeer)
                }
                
                // If selected peer is gone, clear selection
                if let selected = self.selectedPeer,
                   !peers.contains(where: { $0.id == selected.id }) {
                    self.selectedPeer = nil
                    // Don't clear targetIP - user might have typed it manually
                }
            }
    }
    
    /// Start discovering receivers on the network
    func startDiscovery() {
        peerDiscovery.startBrowsing()
    }
    
    /// Stop discovering receivers
    func stopDiscovery() {
        peerDiscovery.stopBrowsing()
    }
    
    /// Select a discovered peer
    func selectPeer(_ peer: DiscoveredPeer) {
        selectedPeer = peer
        targetIP = peer.host
        port = peer.port
        logger.info("Selected peer: \(peer.name) at \(peer.host):\(peer.port)")
    }
    
    // MARK: - Actions
    
    var isStreaming: Bool {
        if case .streaming = connectionState { return true }
        return false
    }
    
    var canStart: Bool {
        // Need valid IP address to connect
        guard !targetIP.isEmpty else { return false }
        
        if case .disconnected = connectionState { return true }
        if case .error = connectionState { return true }
        return false
    }
    
    func startStreaming() {
        guard canStart else { return }
        
        streamTask = Task {
            await performStreaming()
        }
    }
    
    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        
        cleanup()
        connectionState = .disconnected
        resetStats()
    }
    
    // MARK: - Private
    
    private func performStreaming() async {
        connectionState = .connecting
        
        // Initialize client
        let client = QuicClient()
        quicClient = client
        
        // Connect to receiver
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                client.connect(host: targetIP, port: port) { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch {
            connectionState = .error(error.localizedDescription)
            cleanup()
            return
        }
        
        connectionState = .connected
        
        // Start capture
        let capture = ScreenCapture()
        screenCapture = capture
        
        // Configure capture resolution
        capture.captureAtNativeResolution = useNativeResolution
        capture.maxWidth = maxWidth
        // ScreenCapture delivers BGRA by default (convertToRGBA = false), perfect for H.264
        
        let encoder = H264Encoder()
        h264Encoder = encoder
        
        var shouldStop = false
        var encoderInitialized = false
        var currentWidth: UInt16 = 0
        var currentHeight: UInt16 = 0
        let targetBitrate = Int32(bitrateMbps * 1_000_000)
        
        startTime = Date()
        sequence = 0
        
        // Handle encoded frames
        encoder.onEncodedFrame = { [weak self] nalData, isKeyframe in
            guard let self = self, !shouldStop else { return }
            
            let timestampUs = UInt64(Date().timeIntervalSince(self.startTime) * 1_000_000)
            
            let frameData = self.createFrameData(
                sequence: self.sequence,
                timestampUs: timestampUs,
                width: currentWidth,
                height: currentHeight,
                payload: nalData,
                frameType: 1  // H264Frame
            )
            
            client.send(frameData) { [weak self] sendResult in
                guard let self = self else { return }
                
                Task { @MainActor in
                    switch sendResult {
                    case .success:
                        self.consecutiveSendErrors = 0  // Reset error counter on success
                        self.framesSinceStats += 1
                        self.bytesSinceStats += UInt64(frameData.count)
                        self.frameCount = self.sequence
                        
                        // Update stats every second
                        let now = Date()
                        if now.timeIntervalSince(self.lastStatsTime) >= 1.0 {
                            let elapsed = now.timeIntervalSince(self.lastStatsTime)
                            self.fps = Double(self.framesSinceStats) / elapsed
                            self.bitrate = Double(self.bytesSinceStats * 8) / (elapsed * 1_000_000)
                            self.framesSinceStats = 0
                            self.bytesSinceStats = 0
                            self.lastStatsTime = now
                        }
                        
                    case .failure(let error):
                        self.consecutiveSendErrors += 1
                        
                        // Only log every 10th error to avoid log spam
                        if self.consecutiveSendErrors % 10 == 1 {
                            self.logger.warning("Send error (\(self.consecutiveSendErrors)/\(StreamingState.maxConsecutiveErrors)): \(error.localizedDescription)")
                        }
                        
                        // Only stop after many consecutive errors - allows recovery from transient issues
                        if self.consecutiveSendErrors >= StreamingState.maxConsecutiveErrors {
                            self.logger.error("Too many consecutive send failures, stopping stream")
                            shouldStop = true
                            self.connectionState = .error("Connection lost")
                        }
                    }
                }
            }
            
            self.sequence += 1
        }
        
        // Handle captured frames (data is already BGRA from ScreenCapture)
        capture.onFrame = { [weak self] bgraData, width, height in
            guard let self = self, !shouldStop else { return }
            
            currentWidth = width
            currentHeight = height
            
            Task { @MainActor in
                self.resolution = "\(width)×\(height)"
            }
            
            // Initialize encoder on first frame or resolution change
            if !encoderInitialized || width != UInt16(encoder.width) || height != UInt16(encoder.height) {
                do {
                    try encoder.initialize(width: Int32(width), height: Int32(height), bitrate: targetBitrate, fps: 60)
                    encoderInitialized = true
                } catch {
                    Task { @MainActor in
                        self.connectionState = .error("Encoder init failed")
                    }
                    shouldStop = true
                    return
                }
            }
            
            // Create pixel buffer from BGRA data (no conversion needed!)
            var pixelBuffer: CVPixelBuffer?
            let attrs: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                Int(width),
                Int(height),
                kCVPixelFormatType_32BGRA,
                attrs as CFDictionary,
                &pixelBuffer
            )
            
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                return
            }
            
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            
            if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
                let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
                let dest = baseAddress.assumingMemoryBound(to: UInt8.self)
                
                // Fast copy - data is already BGRA, just handle row padding
                bgraData.withUnsafeBytes { srcPtr in
                    guard let src = srcPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                    
                    let srcBytesPerRow = Int(width) * 4
                    for y in 0..<Int(height) {
                        memcpy(dest.advanced(by: y * bytesPerRow), src.advanced(by: y * srcBytesPerRow), srcBytesPerRow)
                    }
                }
            }
            
            // Encode frame
            do {
                try encoder.encode(pixelBuffer: buffer)
            } catch {
                self.logger.error("Encoding failed: \(error.localizedDescription)")
            }
        }
        
        // Handle resolution changes
        capture.onResolutionChange = { width, height in
            Task { @MainActor in
                self.resolution = "\(width)×\(height)"
            }
        }
        
        // Start capture
        do {
            try await capture.startCapture()
            connectionState = .streaming
        } catch {
            connectionState = .error(error.localizedDescription)
            cleanup()
            return
        }
        
        // Wait until cancelled
        await withTaskCancellationHandler {
            while !Task.isCancelled && !shouldStop {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        } onCancel: {
            shouldStop = true
        }
        
        // Cleanup
        await capture.stopCapture()
        encoder.shutdown()
        client.close()
    }
    
    private func cleanup() {
        h264Encoder?.shutdown()
        h264Encoder = nil
        
        Task {
            await screenCapture?.stopCapture()
            screenCapture = nil
        }
        
        quicClient?.close()
        quicClient = nil
    }
    
    private func resetStats() {
        fps = 0
        bitrate = 0
        latencyMs = 0
        resolution = "—"
        frameCount = 0
        framesSinceStats = 0
        bytesSinceStats = 0
        sequence = 0
        lastStatsTime = Date()
        consecutiveSendErrors = 0
    }
    
    /// Create frame data with header
    private func createFrameData(sequence: UInt64, timestampUs: UInt64, width: UInt16, height: UInt16, payload: Data, frameType: UInt8 = 0) -> Data {
        var frameData = Data(capacity: 26 + payload.count)
        frameData.append(1) // version
        frameData.append(frameType) // frame_type
        frameData.append(contentsOf: withUnsafeBytes(of: sequence.bigEndian) { Data($0) })
        frameData.append(contentsOf: withUnsafeBytes(of: timestampUs.bigEndian) { Data($0) })
        frameData.append(contentsOf: withUnsafeBytes(of: width.bigEndian) { Data($0) })
        frameData.append(contentsOf: withUnsafeBytes(of: height.bigEndian) { Data($0) })
        frameData.append(contentsOf: withUnsafeBytes(of: UInt32(payload.count).bigEndian) { Data($0) })
        frameData.append(payload)
        return frameData
    }
}

