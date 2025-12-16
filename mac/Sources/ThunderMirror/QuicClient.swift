import Foundation
import Network

/// QUIC client for connecting to Windows receiver
class QuicClient {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.thundermirror.quic")
    private var isConnected = false
    
    /// Connect to a QUIC server
    /// - Parameters:
    ///   - host: Server hostname or IP address
    ///   - port: Server port
    ///   - completion: Called when connection is established or fails
    func connect(host: String, port: UInt16, completion: @escaping (Result<Void, Error>) -> Void) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: port))
        
        // Create QUIC parameters
        let quicOptions = NWProtocolQUIC.Options()
        let quicParameters = NWParameters(quic: quicOptions)
        // Note: ALPN setup for QUIC in Network framework is complex, skipping for Phase 1
        
        // Allow insecure connections for testing (self-signed certs)
        quicParameters.allowLocalEndpointReuse = true
        
        connection = NWConnection(to: endpoint, using: quicParameters)
        
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isConnected = true
                completion(.success(()))
            case .failed(let error):
                self?.isConnected = false
                completion(.failure(error))
            case .cancelled:
                self?.isConnected = false
                completion(.failure(NSError(domain: "QuicClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection cancelled"])))
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

