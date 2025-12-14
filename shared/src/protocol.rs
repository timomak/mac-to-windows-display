//! Streaming protocol definitions
//!
//! This module defines the wire format for streaming frames between
//! the Mac sender and Windows receiver.

use bytes::{Buf, BufMut, Bytes, BytesMut};
use serde::{Deserialize, Serialize};

/// Protocol version
pub const PROTOCOL_VERSION: u8 = 1;

/// Maximum frame payload size (8MB)
pub const MAX_FRAME_SIZE: usize = 8 * 1024 * 1024;

/// Frame types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum FrameType {
    /// Raw RGBA pixel data
    RawFrame = 0,

    /// H.264 encoded frame
    H264Frame = 1,

    /// Control message
    Control = 2,

    /// Statistics/heartbeat
    Stats = 3,
}

impl TryFrom<u8> for FrameType {
    type Error = crate::Error;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            0 => Ok(FrameType::RawFrame),
            1 => Ok(FrameType::H264Frame),
            2 => Ok(FrameType::Control),
            3 => Ok(FrameType::Stats),
            _ => Err(crate::Error::protocol(format!(
                "Unknown frame type: {}",
                value
            ))),
        }
    }
}

/// Frame header (fixed size: 26 bytes)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FrameHeader {
    /// Protocol version
    pub version: u8,

    /// Frame type
    pub frame_type: FrameType,

    /// Frame sequence number
    pub sequence: u64,

    /// Timestamp (microseconds since stream start)
    pub timestamp_us: u64,

    /// Frame width (pixels)
    pub width: u16,

    /// Frame height (pixels)
    pub height: u16,

    /// Payload size in bytes
    pub payload_size: u32,
}

impl FrameHeader {
    /// Header size in bytes
    /// version(1) + frame_type(1) + sequence(8) + timestamp_us(8) + width(2) + height(2) + payload_size(4) = 26
    pub const SIZE: usize = 26;

    /// Create a new frame header
    pub fn new(
        frame_type: FrameType,
        sequence: u64,
        timestamp_us: u64,
        width: u16,
        height: u16,
        payload_size: u32,
    ) -> Self {
        Self {
            version: PROTOCOL_VERSION,
            frame_type,
            sequence,
            timestamp_us,
            width,
            height,
            payload_size,
        }
    }

    /// Encode header to bytes
    pub fn encode(&self, buf: &mut BytesMut) {
        buf.put_u8(self.version);
        buf.put_u8(self.frame_type as u8);
        buf.put_u64(self.sequence);
        buf.put_u64(self.timestamp_us);
        buf.put_u16(self.width);
        buf.put_u16(self.height);
        buf.put_u32(self.payload_size);
    }

    /// Decode header from bytes
    pub fn decode(buf: &mut Bytes) -> crate::Result<Self> {
        if buf.remaining() < Self::SIZE {
            return Err(crate::Error::protocol("Header too short"));
        }

        let version = buf.get_u8();
        if version != PROTOCOL_VERSION {
            return Err(crate::Error::protocol(format!(
                "Unsupported version: {}",
                version
            )));
        }

        let frame_type = FrameType::try_from(buf.get_u8())?;
        let sequence = buf.get_u64();
        let timestamp_us = buf.get_u64();
        let width = buf.get_u16();
        let height = buf.get_u16();
        let payload_size = buf.get_u32();

        Ok(Self {
            version,
            frame_type,
            sequence,
            timestamp_us,
            width,
            height,
            payload_size,
        })
    }
}

/// Complete frame (header + payload)
#[derive(Debug, Clone)]
pub struct Frame {
    pub header: FrameHeader,
    pub payload: Bytes,
}

impl Frame {
    /// Create a new frame
    pub fn new(header: FrameHeader, payload: Bytes) -> Self {
        Self { header, payload }
    }

    /// Encode frame to bytes
    pub fn encode(&self) -> BytesMut {
        let mut buf = BytesMut::with_capacity(FrameHeader::SIZE + self.payload.len());
        self.header.encode(&mut buf);
        buf.extend_from_slice(&self.payload);
        buf
    }
}

/// Control message types
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ControlMessage {
    /// Start streaming
    Start { width: u16, height: u16, fps: u8 },

    /// Stop streaming
    Stop,

    /// Request keyframe
    RequestKeyframe,

    /// Resolution change
    ResolutionChange { width: u16, height: u16 },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_frame_header_encode_decode() {
        let header = FrameHeader::new(FrameType::RawFrame, 42, 1000000, 1920, 1080, 8294400);

        let mut buf = BytesMut::new();
        header.encode(&mut buf);

        assert_eq!(buf.len(), FrameHeader::SIZE);

        let mut bytes = buf.freeze();
        let decoded = FrameHeader::decode(&mut bytes).unwrap();

        assert_eq!(decoded.version, PROTOCOL_VERSION);
        assert_eq!(decoded.frame_type, FrameType::RawFrame);
        assert_eq!(decoded.sequence, 42);
        assert_eq!(decoded.width, 1920);
        assert_eq!(decoded.height, 1080);
    }

    #[test]
    fn test_frame_type_conversion() {
        assert_eq!(FrameType::try_from(0).unwrap(), FrameType::RawFrame);
        assert_eq!(FrameType::try_from(1).unwrap(), FrameType::H264Frame);
        assert!(FrameType::try_from(255).is_err());
    }
}
