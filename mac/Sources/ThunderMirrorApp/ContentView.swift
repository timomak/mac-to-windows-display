import SwiftUI

/// Main content view for ThunderMirror
struct ContentView: View {
    @EnvironmentObject var state: StreamingState
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(hex: 0x0D1117),
                    Color(hex: 0x161B22),
                    Color(hex: 0x0D1117)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Subtle pattern overlay
            GeometryReader { geo in
                Canvas { context, size in
                    for i in stride(from: 0, to: size.width, by: 40) {
                        for j in stride(from: 0, to: size.height, by: 40) {
                            let rect = CGRect(x: i, y: j, width: 1, height: 1)
                            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.03)))
                        }
                    }
                }
            }
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Main content
                ScrollView {
                    VStack(spacing: 24) {
                        connectionCard
                        settingsCard
                        statsCard
                    }
                    .padding(24)
                }
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Action button
                actionButton
                    .padding(20)
            }
        }
        .frame(width: 380, height: 560)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 12) {
            // App icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x58A6FF), Color(hex: 0x1F6FEB)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                
                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("ThunderMirror")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("v0.3.0")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            Spacer()
            
            // Status indicator
            statusBadge
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.connectionState.color)
                .frame(width: 8, height: 8)
                .shadow(color: state.connectionState.color.opacity(0.6), radius: 4)
            
            Text(state.connectionState.displayText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
        )
    }
    
    // MARK: - Cards
    
    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Connection", systemImage: "network")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                
                Spacer()
                
                // Discovery status indicator
                if state.peerDiscovery.isSearching {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                        Text("Searching...")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                    }
                } else if !state.peerDiscovery.peers.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                        Text("\(state.peerDiscovery.peers.count) found")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }
            
            VStack(spacing: 12) {
                // Discovered Receivers
                if !state.peerDiscovery.peers.isEmpty {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Receivers")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                        }
                        
                        ForEach(state.peerDiscovery.peers) { peer in
                            peerRow(peer)
                        }
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                }
                
                // Manual IP Address (always available)
                HStack {
                    Text(state.peerDiscovery.peers.isEmpty ? "Windows IP" : "Or enter IP")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Spacer()
                    
                    TextField("Auto-detecting...", text: $state.targetIP)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 140)
                        .disabled(state.isStreaming)
                }
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Port
                HStack {
                    Text("Port")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Spacer()
                    
                    TextField("9999", value: $state.port, format: .number)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .disabled(state.isStreaming)
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    private func peerRow(_ peer: DiscoveredPeer) -> some View {
        Button(action: {
            state.selectPeer(peer)
        }) {
            HStack(spacing: 10) {
                // Selection indicator
                Image(systemName: state.selectedPeer?.id == peer.id ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(state.selectedPeer?.id == peer.id ? .green : .white.opacity(0.3))
                
                // Device icon
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(peer.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text("\(peer.host):\(peer.port)")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                // Link-local indicator
                if peer.host.hasPrefix("169.254.") {
                    Text("Thunderbolt")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.cyan.opacity(0.15))
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(state.selectedPeer?.id == peer.id ? Color.white.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(state.selectedPeer?.id == peer.id ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(state.isStreaming)
    }
    
    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Settings", systemImage: "slider.horizontal.3")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
            
            VStack(spacing: 12) {
                // Mode
                HStack {
                    Text("Mode")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Spacer()
                    
                    Picker("", selection: $state.mode) {
                        ForEach(StreamingState.StreamMode.allCases) { mode in
                            Text(mode.rawValue)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .disabled(state.isStreaming)
                }
                
                if state.mode == .extend {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        
                        Text("Extend mode coming in Phase 4")
                            .font(.system(size: 11))
                            .foregroundColor(.orange.opacity(0.8))
                    }
                }
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Resolution
                HStack {
                    Text("Max Width")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Spacer()
                    
                    Picker("", selection: $state.maxWidth) {
                        Text("1280").tag(1280)
                        Text("1920").tag(1920)
                        Text("2560").tag(2560)
                        Text("Native").tag(9999)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .disabled(state.isStreaming)
                }
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Bitrate
                HStack {
                    Text("Bitrate")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Slider(value: .init(
                            get: { Double(state.bitrateMbps) },
                            set: { state.bitrateMbps = Int($0) }
                        ), in: 10...100, step: 5)
                        .frame(width: 100)
                        .disabled(state.isStreaming)
                        
                        Text("\(state.bitrateMbps) Mbps")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Statistics", systemImage: "chart.bar.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                statItem(title: "FPS", value: String(format: "%.1f", state.fps), unit: "fps")
                statItem(title: "Bitrate", value: String(format: "%.1f", state.bitrate), unit: "Mbps")
                statItem(title: "Resolution", value: state.resolution, unit: "")
                statItem(title: "Frames", value: formatNumber(state.frameCount), unit: "")
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    private func statItem(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
            
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
    
    // MARK: - Action Button
    
    private var actionButton: some View {
        Button(action: {
            if state.isStreaming {
                state.stopStreaming()
            } else {
                state.startStreaming()
            }
        }) {
            HStack(spacing: 10) {
                if state.isStreaming {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("Stop Streaming")
                        .font(.system(size: 14, weight: .semibold))
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("Start Streaming")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .foregroundColor(.white)
            .background(
                Group {
                    if state.isStreaming {
                        LinearGradient(
                            colors: [Color(hex: 0xF85149), Color(hex: 0xDA3633)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    } else {
                        LinearGradient(
                            colors: [Color(hex: 0x3FB950), Color(hex: 0x238636)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: (state.isStreaming ? Color(hex: 0xF85149) : Color(hex: 0x3FB950)).opacity(0.3), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(!state.canStart && !state.isStreaming)
    }
    
    // MARK: - Helpers
    
    private func formatNumber(_ num: UInt64) -> String {
        if num >= 1_000_000 {
            return String(format: "%.1fM", Double(num) / 1_000_000)
        } else if num >= 1_000 {
            return String(format: "%.1fK", Double(num) / 1_000)
        }
        return "\(num)"
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(StreamingState())
}

