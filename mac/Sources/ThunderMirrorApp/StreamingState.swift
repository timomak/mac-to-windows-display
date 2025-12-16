import Foundation
import SwiftUI
import Logging

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
    @Published var targetIP: String = "192.168.50.2"
    @Published var port: UInt16 = 9999
    @Published var mode: StreamMode = .mirror
    @Published var bitrateMbps: Int = 10
    
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
    
    // MARK: - Actions
    
    var isStreaming: Bool {
        if case .streaming = connectionState { return true }
        return false
    }
    
    var canStart: Bool {
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
                        self.logger.error("Send failed: \(error.localizedDescription)")
                        shouldStop = true
                        self.connectionState = .error("Send failed")
                    }
                }
            }
            
            self.sequence += 1
        }
        
        // Handle captured frames
        capture.onFrame = { [weak self] rgbaData, width, height in
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
            
            // Create pixel buffer from RGBA data
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
                
                // Convert RGBA to BGRA
                rgbaData.withUnsafeBytes { srcPtr in
                    guard let src = srcPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                    
                    for y in 0..<Int(height) {
                        for x in 0..<Int(width) {
                            let srcOffset = (y * Int(width) + x) * 4
                            let dstOffset = y * bytesPerRow + x * 4
                            
                            dest[dstOffset + 0] = src[srcOffset + 2]  // B
                            dest[dstOffset + 1] = src[srcOffset + 1]  // G
                            dest[dstOffset + 2] = src[srcOffset + 0]  // R
                            dest[dstOffset + 3] = src[srcOffset + 3]  // A
                        }
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

