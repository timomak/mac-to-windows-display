import Foundation
import Network
import Combine

/// Discovered ThunderMirror receiver peer
struct DiscoveredPeer: Identifiable, Equatable {
    let id: String
    let name: String
    let host: String
    let port: UInt16
    
    static func == (lhs: DiscoveredPeer, rhs: DiscoveredPeer) -> Bool {
        lhs.id == rhs.id
    }
}

/// mDNS/Bonjour browser for discovering ThunderMirror receivers
@MainActor
class PeerDiscovery: ObservableObject {
    /// Discovered peers
    @Published var peers: [DiscoveredPeer] = []
    
    /// Whether discovery is active
    @Published var isSearching = false
    
    /// Error message if discovery fails
    @Published var errorMessage: String?
    
    private var browser: NWBrowser?
    private var pendingResolutions: [NWEndpoint: NWConnection] = [:]
    
    /// Service type to browse for (must match Windows advertiser)
    static let serviceType = "_thunder-mirror._udp"
    
    /// Start browsing for receivers
    func startBrowsing() {
        guard browser == nil else { return }
        
        isSearching = true
        errorMessage = nil
        peers = []
        
        // Create browser for our service type
        let descriptor = NWBrowser.Descriptor.bonjour(type: Self.serviceType, domain: "local.")
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        
        let browser = NWBrowser(for: descriptor, using: parameters)
        self.browser = browser
        
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    print("PeerDiscovery: Browser ready")
                case .failed(let error):
                    print("PeerDiscovery: Browser failed: \(error)")
                    self?.errorMessage = "Discovery failed: \(error.localizedDescription)"
                    self?.isSearching = false
                case .cancelled:
                    print("PeerDiscovery: Browser cancelled")
                    self?.isSearching = false
                default:
                    break
                }
            }
        }
        
        browser.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                self?.handleBrowseResults(results, changes: changes)
            }
        }
        
        browser.start(queue: .main)
        print("PeerDiscovery: Started browsing for \(Self.serviceType)")
    }
    
    /// Stop browsing
    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        
        // Cancel any pending resolutions
        for (_, connection) in pendingResolutions {
            connection.cancel()
        }
        pendingResolutions.removeAll()
        
        isSearching = false
        print("PeerDiscovery: Stopped browsing")
    }
    
    private func handleBrowseResults(_ results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                resolveEndpoint(result.endpoint, metadata: result.metadata)
            case .removed(let result):
                removePeer(for: result.endpoint)
            case .changed(old: _, new: let result, flags: _):
                // Re-resolve on change
                removePeer(for: result.endpoint)
                resolveEndpoint(result.endpoint, metadata: result.metadata)
            case .identical:
                // No change, ignore
                break
            @unknown default:
                break
            }
        }
    }
    
    private func resolveEndpoint(_ endpoint: NWEndpoint, metadata: NWBrowser.Result.Metadata?) {
        // Extract service name from endpoint
        let serviceName: String
        switch endpoint {
        case .service(let name, _, _, _):
            serviceName = name
        default:
            serviceName = "ThunderMirror Receiver"
        }
        
        print("PeerDiscovery: Resolving endpoint: \(endpoint)")
        
        // Create a connection to resolve the endpoint to an IP address
        let parameters = NWParameters.udp
        let connection = NWConnection(to: endpoint, using: parameters)
        pendingResolutions[endpoint] = connection
        
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    // Get the resolved remote endpoint
                    if let remoteEndpoint = connection.currentPath?.remoteEndpoint {
                        self?.addResolvedPeer(
                            originalEndpoint: endpoint,
                            resolvedEndpoint: remoteEndpoint,
                            name: serviceName
                        )
                    }
                    connection.cancel()
                    self?.pendingResolutions.removeValue(forKey: endpoint)
                case .failed(let error):
                    print("PeerDiscovery: Resolution failed for \(serviceName): \(error)")
                    connection.cancel()
                    self?.pendingResolutions.removeValue(forKey: endpoint)
                case .cancelled:
                    self?.pendingResolutions.removeValue(forKey: endpoint)
                default:
                    break
                }
            }
        }
        
        connection.start(queue: .main)
    }
    
    private func addResolvedPeer(originalEndpoint: NWEndpoint, resolvedEndpoint: NWEndpoint, name: String) {
        guard case .hostPort(let host, let port) = resolvedEndpoint else {
            print("PeerDiscovery: Resolved endpoint is not hostPort: \(resolvedEndpoint)")
            return
        }
        
        let hostString: String
        switch host {
        case .ipv4(let addr):
            hostString = addr.debugDescription
        case .ipv6(let addr):
            hostString = addr.debugDescription
        case .name(let hostname, _):
            hostString = hostname
        @unknown default:
            hostString = host.debugDescription
        }
        
        let portNumber = port.rawValue
        
        // Create unique ID from endpoint description
        let id = "\(hostString):\(portNumber)"
        
        // Check if already exists
        if peers.contains(where: { $0.id == id }) {
            return
        }
        
        let peer = DiscoveredPeer(
            id: id,
            name: name,
            host: hostString,
            port: portNumber
        )
        
        peers.append(peer)
        print("PeerDiscovery: Found receiver '\(name)' at \(hostString):\(portNumber)")
    }
    
    private func removePeer(for endpoint: NWEndpoint) {
        // Remove peer that matches this endpoint
        // We need to match by service name since we might not have the IP yet
        switch endpoint {
        case .service(let name, _, _, _):
            peers.removeAll { $0.name == name }
        default:
            break
        }
    }
    
    deinit {
        // Clean up
        browser?.cancel()
        for (_, connection) in pendingResolutions {
            connection.cancel()
        }
    }
}

