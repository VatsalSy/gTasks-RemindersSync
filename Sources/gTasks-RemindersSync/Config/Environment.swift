import Foundation

enum Environment {
    enum Error: Swift.Error {
        case missingClientId
        case missingClientSecret
    }
    
    static func googleClientId() throws -> String {
        guard let clientId = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_ID"] else {
            throw Error.missingClientId
        }
        return clientId
    }
    
    static func googleClientSecret() throws -> String {
        guard let clientSecret = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_SECRET"] else {
            throw Error.missingClientSecret
        }
        return clientSecret
    }
    
    static func googleToken() -> String? {
        return ProcessInfo.processInfo.environment["GOOGLE_TOKEN"]
    }
    
    static func saveGoogleToken(_ token: String) {
        let fileManager = FileManager.default
        let currentPath = fileManager.currentDirectoryPath
        let envPath = currentPath + "/.envlocal"
        
        do {
            var envContents = try String(contentsOfFile: envPath, encoding: .utf8)
            
            // Remove existing token if present
            let lines = envContents.components(separatedBy: .newlines)
            envContents = lines.filter { !$0.starts(with: "GOOGLE_TOKEN=") }.joined(separator: "\n")
            
            // Add new token
            envContents += "\nGOOGLE_TOKEN=\(token)\n"
            
            try envContents.write(to: URL(fileURLWithPath: envPath), atomically: true, encoding: .utf8)
        } catch {
            print("Error saving token to .envlocal: \(error)")
        }
    }
    
    static func loadEnvFile() {
        let fileManager = FileManager.default
        let currentPath = fileManager.currentDirectoryPath
        let envPath = currentPath + "/.envlocal"
        
        guard fileManager.fileExists(atPath: envPath) else {
            print("Warning: .envlocal file not found at \(envPath)")
            return
        }
        
        do {
            let envContents = try String(contentsOfFile: envPath, encoding: .utf8)
            let envVars = envContents.components(separatedBy: .newlines)
            
            for var line in envVars {
                line = line.trimmingCharacters(in: .whitespaces)
                
                if line.isEmpty || line.hasPrefix("#") {
                    continue
                }
                
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespaces)
                    var value = parts[1].trimmingCharacters(in: .whitespaces)
                    
                    // Remove quotes if present
                    if value.hasPrefix("\"") && value.hasSuffix("\"") {
                        value = String(value.dropFirst().dropLast())
                    }
                    
                    setenv(key, value, 1)
                }
            }
        } catch {
            print("Error loading .envlocal file: \(error)")
        }
    }
} 