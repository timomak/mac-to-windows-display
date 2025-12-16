# Performance Step - Stress Test Command

This command runs performance benchmarks and stress tests for Phase 5.

## Instructions for Cursor Agent

When this command is invoked:

### 1. Verify Baseline Works

Before any performance testing, ensure streaming works:
```bash
# Quick sanity check
cd mac && swift build
ssh blade18-tb "cd /path/to/project/win && cargo build --release"
```

If baseline streaming is broken, STOP. Fix it first.

### 2. Read Phase 5 Items from PHASE.md

Check `docs/PHASE.md` for Phase 5 checklist items. Identify which benchmark or feature to test.

### 3. Run Benchmark Configuration

For each resolution/framerate combination, run a structured test:

```bash
# Create benchmark log directory
mkdir -p logs/benchmarks

# Run Mac sender with specific config
cd mac && swift run ThunderMirror \
  --resolution <WxH> \
  --fps <target_fps> \
  --codec <h264|hevc> \
  --bitrate <mbps> \
  2>&1 | tee logs/benchmarks/mac_<config>.log &

# Run Windows receiver and collect stats
ssh blade18-tb "cd /path/to/project/win && \
  cargo run --release 2>&1" | tee logs/benchmarks/win_<config>.log
```

### 4. Benchmark Configurations to Test

Run these configurations in order (stop if one fails to maintain target):

| Config | Resolution | FPS | Codec | Target Latency |
|--------|------------|-----|-------|----------------|
| 1080p60 | 1920×1080 | 60 | H.264 | <16ms |
| 1440p60 | 2560×1440 | 60 | H.264 | <16ms |
| 4K60 | 3840×2160 | 60 | H.264 | <16ms |
| 4K60-HEVC | 3840×2160 | 60 | HEVC | <16ms |
| 4K120 | 3840×2160 | 120 | HEVC | <8ms |
| 5K60 | 5120×2880 | 60 | HEVC | <16ms |

### 5. Collect Metrics

For each configuration, record:

```
## Benchmark: <config_name>
Date: <timestamp>
Duration: 60 seconds

### Settings
- Resolution: <WxH>
- Target FPS: <N>
- Codec: <codec>
- Bitrate: <N> Mbps

### Results
- Actual FPS: <N> (min/avg/max)
- Frame Latency: <N>ms (min/avg/max/p99)
- Bandwidth: <N> Gbps
- Thunderbolt Utilization: <N>%
- Dropped Frames: <N> (<percent>%)
- Encoder Time: <N>ms avg
- Decoder Time: <N>ms avg

### Verdict
- [ ] PASS - Meets target
- [ ] FAIL - Below target (reason: ___)
```

### 6. Log Results

Save benchmark results:
```bash
# Individual run logs
logs/benchmarks/
  ├── mac_4k60_h264_20240115_143022.log
  ├── win_4k60_h264_20240115_143022.log
  └── results.md  # Summary of all benchmarks
```

### 7. Update Documentation

After benchmarks complete:

1. Update `logs/benchmarks/results.md` with new results
2. Update `README.md` "Performance" section with max achievable specs
3. Update `docs/PHASE.md` - check off completed items

### 8. On Success

If benchmark meets target:
1. Log results to `logs/benchmarks/results.md`
2. Check off item in `docs/PHASE.md`
3. Commit with message:
   ```
   phase 5 perf: <config> benchmark - <result>
   ```
4. Push to origin

### 9. On Failure

If benchmark fails to meet target:
1. Log the failure with detailed metrics
2. Analyze bottleneck:
   - Encoder too slow? → Check VideoToolbox settings
   - Network saturated? → Check bandwidth utilization
   - Decoder too slow? → Check Media Foundation settings
   - Dropped frames? → Check buffer sizes
3. Document findings in `logs/benchmarks/results.md`
4. Suggest optimization or note as hardware limit

## Stress Test Scenarios

### Sustained Load Test
Run 4K60 for 10 minutes, check for:
- Memory leaks
- Thermal throttling
- Frame timing degradation

### Resolution Switch Test
Rapidly switch between resolutions:
```
1080p → 4K → 1440p → 4K → 1080p
```
Check for crashes or artifacts.

### Network Stress Test
Introduce artificial constraints to test adaptation:
- Limit bandwidth to 5Gbps, 2Gbps, 1Gbps
- Check bitrate adaptation kicks in

## Performance Optimization Checklist

If targets aren't met, try:

- [ ] Enable hardware encoder (VideoToolbox)
- [ ] Reduce GOP size (more keyframes = faster recovery)
- [ ] Tune encoder preset (speed vs quality)
- [ ] Adjust buffer sizes
- [ ] Profile CPU/GPU usage
- [ ] Check for memory copies (zero-copy path?)
- [ ] Verify Thunderbolt link speed (40Gbps expected)

## Notes

- Always run release builds for benchmarks
- Close other applications during tests
- Run multiple iterations for consistent results
- Document hardware (Mac model, Windows GPU) in results
- Thunderbolt 3/4 theoretical max: 40Gbps (~5GB/s)
- Realistic sustained throughput: ~20-32Gbps

## SSH Between Machines

| From | To | SSH Command |
|------|----|-------------|
| Mac | Windows | `ssh blade18-tb` |
| Windows | Mac | `ssh mac-tb` |

