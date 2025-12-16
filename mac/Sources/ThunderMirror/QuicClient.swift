import Foundation
import Network

/// QUIC client for connecting to Windows receiver
class QuicClient {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.thundermirror.quic")
    private var isConnected = false
    private var timeoutWorkItem: DispatchWorkItem?
    
    /// Default connection timeout in seconds
    static let defaultTimeout: TimeInterval = 10.0
    
    /// Connect to a QUIC server
    /// - Parameters:
    ///   - host: Server hostname or IP address
    ///   - port: Server port
    ///   - timeout: Connection timeout in seconds (default: 10)
    ///   - completion: Called when connection is established or fails
    func connect(host: String, port: UInt16, timeout: TimeInterval = defaultTimeout, completion: @escaping (Result<Void, Error>) -> Void) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: port))
        
        // Create QUIC parameters
        let quicOptions = NWProtocolQUIC.Options()
        let quicParameters = NWParameters(quic: quicOptions)
        // Note: ALPN setup for QUIC in Network framework is complex, skipping for Phase 1
        
        // Allow insecure connections for testing (self-signed certs)
        quicParameters.allowLocalEndpointReuse = true
        
        connection = NWConnection(to: endpoint, using: quicParameters)
        
        // Track if we've already called completion
        var completionCalled = false
        let completionLock = NSLock()
        
        let safeCompletion: (Result<Void, Error>) -> Void = { result in
            completionLock.lock()
            defer { completionLock.unlock() }
            guard !completionCalled else { return }
            completionCalled = true
            completion(result)
        }
        
        // Setup connection timeout
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, !self.isConnected else { return }
            self.connection?.cancel()
            safeCompletion(.failure(NSError(
                domain: "QuicClient",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Connection timeout after \(Int(timeout)) seconds. Is the receiver running at \(host):\(port)?"]
            )))
        }
        timeoutWorkItem = workItem
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: workItem)
        
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.timeoutWorkItem?.cancel()
                self?.isConnected = true
                safeCompletion(.success(()))
            case .failed(let error):
                self?.timeoutWorkItem?.cancel()
                self?.isConnected = false
                safeCompletion(.failure(error))
            case .cancelled:
                self?.isConnected = false
                // Don't call completion here - timeout handler or explicit cancel handles it
            case .waiting(let error):
                // Log waiting state but don't fail yet - timeout will handle it
                print("Connection waiting: \(error)")
            default:
                break
            }
        }
        
        connection?.start(queue: queue)
    }
    
    /// Send data over the QUIC connection
    /// - Parameters:
    ///   - data: Data to send
    ///   - completion: Called when send completes or fails
    func send(_ data: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let connection = connection, isConnected else {
            completion(.failure(NSError(domain: "QuicClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])))
            return
        }
        
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        })
    }
    
    /// Receive data from the QUIC connection
    /// - Parameter completion: Called when data is received or connection closes
    func receive(completion: @escaping (Result<Data?, Error>) -> Void) {
        guard let connection = connection, isConnected else {
            completion(.failure(NSError(domain: "QuicClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])))
            return
        }
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8 * 1024 * 1024) { data, context, isComplete, error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(data))
            }
        }
    }
    
    /// Close the connection
    func close() {
        connection?.cancel()
        connection = nil
        isConnected = false
    }
}

