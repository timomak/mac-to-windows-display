//! Statistics and metrics collection

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};

/// Statistics snapshot
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct StatsSnapshot {
    /// Frames per second
    pub fps: f64,

    /// Bytes per second
    pub bytes_per_sec: u64,

    /// Bitrate in Mbps
    pub bitrate_mbps: f64,

    /// Total frames sent/received
    pub total_frames: u64,

    /// Total bytes sent/received
    pub total_bytes: u64,

    /// Dropped frames
    pub dropped_frames: u64,

    /// Estimated latency in milliseconds (if available)
    pub latency_ms: Option<f64>,

    /// Uptime in seconds
    pub uptime_secs: f64,
}

/// Thread-safe statistics collector
#[derive(Debug)]
pub struct Stats {
    start_time: Instant,
    last_snapshot_time: std::sync::Mutex<Instant>,

    // Atomic counters for thread-safe updates
    frames: AtomicU64,
    bytes: AtomicU64,
    dropped: AtomicU64,

    // Last snapshot values for rate calculation
    last_frames: AtomicU64,
    last_bytes: AtomicU64,
}

impl Stats {
    /// Create new stats collector
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            start_time: Instant::now(),
            last_snapshot_time: std::sync::Mutex::new(Instant::now()),
            frames: AtomicU64::new(0),
            bytes: AtomicU64::new(0),
            dropped: AtomicU64::new(0),
            last_frames: AtomicU64::new(0),
            last_bytes: AtomicU64::new(0),
        })
    }

    /// Record a frame
    pub fn record_frame(&self, bytes: u64) {
        self.frames.fetch_add(1, Ordering::Relaxed);
        self.bytes.fetch_add(bytes, Ordering::Relaxed);
    }

    /// Record a dropped frame
    pub fn record_drop(&self) {
        self.dropped.fetch_add(1, Ordering::Relaxed);
    }

    /// Get current statistics snapshot
    pub fn snapshot(&self) -> StatsSnapshot {
        let now = Instant::now();
        let uptime = now.duration_since(self.start_time);

        let current_frames = self.frames.load(Ordering::Relaxed);
        let current_bytes = self.bytes.load(Ordering::Relaxed);
        let dropped = self.dropped.load(Ordering::Relaxed);

        // Calculate rates
        let mut last_time = self.last_snapshot_time.lock().unwrap();
        let elapsed = now.duration_since(*last_time);

        let (fps, bytes_per_sec) = if elapsed >= Duration::from_millis(100) {
            let last_frames = self.last_frames.swap(current_frames, Ordering::Relaxed);
            let last_bytes = self.last_bytes.swap(current_bytes, Ordering::Relaxed);

            let frame_delta = current_frames.saturating_sub(last_frames);
            let byte_delta = current_bytes.saturating_sub(last_bytes);

            let secs = elapsed.as_secs_f64();
            *last_time = now;

            (frame_delta as f64 / secs, (byte_delta as f64 / secs) as u64)
        } else {
            // Not enough time has passed, return previous rates
            (0.0, 0)
        };

        let bitrate_mbps = (bytes_per_sec as f64 * 8.0) / 1_000_000.0;

        StatsSnapshot {
            fps,
            bytes_per_sec,
            bitrate_mbps,
            total_frames: current_frames,
            total_bytes: current_bytes,
            dropped_frames: dropped,
            latency_ms: None, // Set by transport layer
            uptime_secs: uptime.as_secs_f64(),
        }
    }

    /// Reset all statistics
    pub fn reset(&self) {
        self.frames.store(0, Ordering::Relaxed);
        self.bytes.store(0, Ordering::Relaxed);
        self.dropped.store(0, Ordering::Relaxed);
        self.last_frames.store(0, Ordering::Relaxed);
        self.last_bytes.store(0, Ordering::Relaxed);
    }
}

impl Default for Stats {
    fn default() -> Self {
        Self {
            start_time: Instant::now(),
            last_snapshot_time: std::sync::Mutex::new(Instant::now()),
            frames: AtomicU64::new(0),
            bytes: AtomicU64::new(0),
            dropped: AtomicU64::new(0),
            last_frames: AtomicU64::new(0),
            last_bytes: AtomicU64::new(0),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_stats_recording() {
        let stats = Stats::new();

        stats.record_frame(1000);
        stats.record_frame(1000);
        stats.record_drop();

        let snapshot = stats.snapshot();
        assert_eq!(snapshot.total_frames, 2);
        assert_eq!(snapshot.total_bytes, 2000);
        assert_eq!(snapshot.dropped_frames, 1);
    }
}
