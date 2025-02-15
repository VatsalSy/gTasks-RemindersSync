import Foundation
import Network

class SimpleServer {
    private var listener: NWListener?
    private let port: UInt16
    private var completion: ((String) -> Void)?
    
    init(port: UInt16) {
        self.port = port
    }
    
    func start(completion: @escaping (String) -> Void) throws {
        self.completion = completion
        let parameters = NWParameters.tcp
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))
        
        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Server ready on port \(self?.port ?? 0)")
            case .failed(let error):
                print("Server failed with error: \(error)")
            default:
                break
            }
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
                        if let content = content,
                           let request = String(data: content, encoding: .utf8),
                           let codeParam = request.components(separatedBy: "?code=").last?.components(separatedBy: " ").first {
                            
                            // Send success response
                            let response = """
                            HTTP/1.1 200 OK
                            Content-Type: text/html
                            Connection: close
                            
                            <html><body><h1>Authorization successful!</h1><p>You can close this window and return to the application.</p></body></html>
                            
                            """
                            connection.send(content: response.data(using: .utf8), completion: .idempotent)
                            
                            // Call completion with the authorization code
                            self?.completion?(codeParam)
                            
                            // Stop the server
                            self?.listener?.cancel()
                        }
                    }
                default:
                    break
                }
            }
            connection.start(queue: .main)
        }
        
        listener?.start(queue: .main)
    }
    
    func stop() {
        listener?.cancel()
    }
} 