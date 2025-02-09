import Foundation

// Load environment variables
Environment.loadEnvFile()

print("Starting application...")

// Create and run sync manager
do {
    print("Initializing sync manager...")
    let syncManager = try await SyncManager()
    
    print("Setting up services...")
    try await syncManager.setup()
    
    print("Starting sync...")
    try await syncManager.sync()
    print("Sync completed successfully!")
    exit(0)
} catch {
    print("Error occurred: \(error)")
    print("Detailed error: \(error.localizedDescription)")
    if let nsError = error as NSError? {
        print("Error domain: \(nsError.domain)")
        print("Error code: \(nsError.code)")
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            print("Underlying error: \(underlyingError)")
        }
    }
    exit(1)
} 