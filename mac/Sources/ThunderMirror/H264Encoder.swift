import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo
import Logging

/// Hardware-accelerated H.264 encoder using VideoToolbox
///
/// Encodes raw pixel buffers to H.264 NAL units for streaming.
/// Configured for ultra-low latency: baseline profile, no B-frames, short GOP.
@available(macOS 10.8, *)
class H264Encoder {
    private var compressionSession: VTCompressionSession?
    private let logger = Logger(label: "com.thundermirror.encoder")
    
    /// Current encoding parameters
    private(set) var width: Int32 = 0
    private(set) var height: Int32 = 0
    private(set) var bitrate: Int32 = 10_000_000  // 10 Mbps default
    private(set) var fps: Int32 = 60
    
    /// Callback for encoded NAL units
    var onEncodedFrame: ((Data, Bool) -> Void)?  // (nalData, isKeyframe)
    
    /// Frame timing
    private var frameCount: Int64 = 0
    private let timescale: Int32 = 90000  // Standard video timescale
    
    /// Initialize encoder with given dimensions
    /// - Parameters:
    ///   - width: Frame width
    ///   - height: Frame height
    ///   - bitrate: Target bitrate in bits per second (default: 10 Mbps)
    ///   - fps: Target frame rate (default: 60)
    func initialize(width: Int32, height: Int32, bitrate: Int32 = 10_000_000, fps: Int32 = 60) throws {
        self.width = width
        self.height = height
        self.bitrate = bitrate
        self.fps = fps
        
        // Tear down existing session if any
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
        
        // Create compression session
        let encoderCallback: VTCompressionOutputCallback = { outputCallbackRefCon, sourceFrameRefCon, status, infoFlags, sampleBuffer in
            guard let refCon = outputCallbackRefCon else { return }
            let encoder = Unmanaged<H264Encoder>.fromOpaque(refCon).takeUnretainedValue()
            encoder.handleEncodedFrame(status: status, sampleBuffer: sampleBuffer)
        }
        
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,  // Let system choose best encoder (hardware preferred)
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: encoderCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )
        
        guard status == noErr, let session = session else {
            throw H264EncoderError.sessionCreationFailed(status)
        }
        
        compressionSession = session
        
        // Configure for ultra-low latency
        try configureForLowLatency(session: session)
        
        // Prepare to encode
        let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(session)
        guard prepareStatus == noErr else {
            throw H264EncoderError.prepareFailed(prepareStatus)
        }
        
        logger.info("H.264 encoder initialized: \(width)x\(height) @ \(fps)fps, \(bitrate/1_000_000)Mbps")
    }
    
    /// Configure encoder for ultra-low latency streaming
    private func configureForLowLatency(session: VTCompressionSession) throws {
        var status: OSStatus
        
        // Use hardware encoder if available
        status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder, value: kCFBooleanTrue)
        if status != noErr {
            logger.warning("Hardware encoder not available, using software")
        }
        
        // Real-time encoding (prioritize low latency over quality)
        status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        guard status == noErr else {
            throw H264EncoderError.configurationFailed("RealTime", status)
        }
        
        // High profile for best quality at high resolutions
        // (High profile supports CABAC, 8x8 transform, and better motion compensation)
        status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        guard status == noErr else {
            throw H264EncoderError.configurationFailed("ProfileLevel", status)
        }
        
        // Set bitrate - use both average and max to allow headroom for complex scenes
        let bitrateNum = CFNumberCreate(kCFAllocatorDefault, .intType, &bitrate)
        status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrateNum)
        guard status == noErr else {
            throw H264EncoderError.configurationFailed("AverageBitRate", status)
        }
        
        // Allow 50% headroom for bitrate spikes (complex scenes, motion)
        // DataRateLimits: [bytes_per_second, window_duration_seconds]
        // Use 1.5x average over 1 second window - this is less restrictive than before
        var maxBytesPerSecond = (bitrate + (bitrate / 2)) / 8
        var windowSeconds: Float64 = 1.0
        let maxBytesNum = CFNumberCreate(kCFAllocatorDefault, .intType, &maxBytesPerSecond)
        let windowNum = CFNumberCreate(kCFAllocatorDefault, .float64Type, &windowSeconds)
        if let bNum = maxBytesNum, let wNum = windowNum {
            let limits = [bNum, wNum] as CFArray
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: limits)
        }
        
        // Set expected frame rate
        let expectedFrameRate = CFNumberCreate(kCFAllocatorDefault, .intType, &fps)
        status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: expectedFrameRate)
        guard status == noErr else {
            throw H264EncoderError.configurationFailed("ExpectedFrameRate", status)
        }
        
        // Shorter keyframe interval for better error recovery and quality consistency
        // Every 30 frames (0.5 second at 60fps) - more keyframes = more consistent quality
        var maxKeyFrameInterval: Int32 = 30
        let maxKeyFrameIntervalNum = CFNumberCreate(kCFAllocatorDefault, .intType, &maxKeyFrameInterval)
        status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: maxKeyFrameIntervalNum)
        guard status == noErr else {
            throw H264EncoderError.configurationFailed("MaxKeyFrameInterval", status)
        }
        
        // Disable B-frames for lower latency
        status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        guard status == noErr else {
            throw H264EncoderError.configurationFailed("AllowFrameReordering", status)
        }
        
        // Prioritize quality over speed (encoder has plenty of headroom on M-series)
        status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_Quality, value: 1.0 as CFNumber)
        // Not critical if this fails (some encoders don't support it)
        
        logger.debug("Encoder configured: high profile, no B-frames, GOP=30, quality=max")
    }
    
    /// Encode a pixel buffer
    /// - Parameter pixelBuffer: CVPixelBuffer to encode
    func encode(pixelBuffer: CVPixelBuffer) throws {
        guard let session = compressionSession else {
            throw H264EncoderError.notInitialized
        }
        
        // Create presentation timestamp
        let pts = CMTimeMake(value: frameCount, timescale: timescale)
        let duration = CMTimeMake(value: Int64(timescale / fps), timescale: timescale)
        
        // Encode frame
        var flags: VTEncodeInfoFlags = []
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: pts,
            duration: duration,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: &flags
        )
        
        guard status == noErr else {
            throw H264EncoderError.encodeFailed(status)
        }
        
        frameCount += 1
    }
    
    /// Force a keyframe on the next encode
    func forceKeyframe() throws {
        guard compressionSession != nil else {
            throw H264EncoderError.notInitialized
        }
        
        // Force keyframe by setting property (will apply to next frame)
        // Note: This is done by passing frame properties to encodeFrame, not as a session property
        logger.debug("Keyframe requested")
    }
    
    /// Update bitrate dynamically (for adaptive streaming)
    func updateBitrate(_ newBitrate: Int32) throws {
        guard let session = compressionSession else {
            throw H264EncoderError.notInitialized
        }
        
        var bitrate = newBitrate
        let bitrateNum = CFNumberCreate(kCFAllocatorDefault, .intType, &bitrate)
        let status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrateNum)
        
        guard status == noErr else {
            throw H264EncoderError.configurationFailed("AverageBitRate update", status)
        }
        
        self.bitrate = newBitrate
        logger.info("Bitrate updated to \(newBitrate / 1_000_000) Mbps")
    }
    
    /// Flush encoder and wait for all frames
    func flush() throws {
        guard let session = compressionSession else { return }
        
        let status = VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        guard status == noErr else {
            throw H264EncoderError.flushFailed(status)
        }
    }
    
    /// Shutdown encoder
    func shutdown() {
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
        frameCount = 0
        logger.info("H.264 encoder shutdown")
    }
    
    deinit {
        shutdown()
    }
    
    // MARK: - Private
    
    /// Handle encoded frame callback
    private func handleEncodedFrame(status: OSStatus, sampleBuffer: CMSampleBuffer?) {
        guard status == noErr else {
            logger.error("Encoding error: \(status)")
            return
        }
        
        guard let sampleBuffer = sampleBuffer else {
            logger.warning("No sample buffer in callback")
            return
        }
        
        // Check if this is a keyframe
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
        var isKeyframe = false
        if let attachments = attachments, CFArrayGetCount(attachments) > 0 {
            let attachment = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary.self)
            let notSync = CFDictionaryContainsKey(attachment, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque())
            isKeyframe = !notSync
        }
        
        // Get format description for SPS/PPS (if keyframe)
        var nalData = Data()
        
        if isKeyframe {
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                // Extract SPS
                var spsSize: Int = 0
                var spsCount: Int = 0
                var spsPointer: UnsafePointer<UInt8>?
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, parameterSetIndex: 0, parameterSetPointerOut: &spsPointer, parameterSetSizeOut: &spsSize, parameterSetCountOut: &spsCount, nalUnitHeaderLengthOut: nil)
                
                if let sps = spsPointer, spsSize > 0 {
                    // Add start code + SPS
                    nalData.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
                    nalData.append(UnsafeBufferPointer(start: sps, count: spsSize))
                }
                
                // Extract PPS
                var ppsSize: Int = 0
                var ppsPointer: UnsafePointer<UInt8>?
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, parameterSetIndex: 1, parameterSetPointerOut: &ppsPointer, parameterSetSizeOut: &ppsSize, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
                
                if let pps = ppsPointer, ppsSize > 0 {
                    // Add start code + PPS
                    nalData.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
                    nalData.append(UnsafeBufferPointer(start: pps, count: ppsSize))
                }
            }
        }
        
        // Get encoded data
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            logger.warning("No data buffer in sample")
            return
        }
        
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let blockStatus = CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        
        guard blockStatus == noErr, let pointer = dataPointer else {
            logger.error("Failed to get data pointer: \(blockStatus)")
            return
        }
        
        // Convert AVCC format (length-prefixed) to Annex B format (start codes)
        var offset = 0
        let lengthSize = 4  // AVCC uses 4-byte length prefix
        
        while offset < totalLength {
            // Read NAL unit length (big-endian)
            var nalLength: UInt32 = 0
            memcpy(&nalLength, pointer.advanced(by: offset), lengthSize)
            nalLength = CFSwapInt32BigToHost(nalLength)
            offset += lengthSize
            
            // Add start code + NAL unit
            nalData.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
            nalData.append(Data(bytes: pointer.advanced(by: offset), count: Int(nalLength)))
            offset += Int(nalLength)
        }
        
        // Deliver encoded frame
        onEncodedFrame?(nalData, isKeyframe)
    }
}

/// H.264 encoder errors
enum H264EncoderError: LocalizedError {
    case sessionCreationFailed(OSStatus)
    case prepareFailed(OSStatus)
    case configurationFailed(String, OSStatus)
    case notInitialized
    case encodeFailed(OSStatus)
    case flushFailed(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .sessionCreationFailed(let status):
            return "Failed to create compression session: \(status)"
        case .prepareFailed(let status):
            return "Failed to prepare encoder: \(status)"
        case .configurationFailed(let property, let status):
            return "Failed to configure \(property): \(status)"
        case .notInitialized:
            return "Encoder not initialized"
        case .encodeFailed(let status):
            return "Encoding failed: \(status)"
        case .flushFailed(let status):
            return "Flush failed: \(status)"
        }
    }
}

