import Foundation
import GoogleAPIClientForREST_Tasks
import GTMAppAuth
import AppAuth

class GoogleTasksService {
    private let service: GTLRTasksService
    private var taskListId: String?
    private let listName = "🗓️ Reclaim"
    
    init() async throws {
        service = GTLRTasksService()
        
        // Configure OAuth
        let clientId = try Environment.googleClientId()
        let clientSecret = try Environment.googleClientSecret()
        
        // Configure OAuth endpoints
        let configuration = OIDServiceConfiguration(
            authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!
        )
        let redirectURI = "urn:ietf:wg:oauth:2.0:oob" // Use manual copy-paste flow for simplicity
        
        // Try to load existing token
        if let tokenString = Environment.googleToken(),
           let tokenData = Data(base64Encoded: tokenString),
           let authorization = try? NSKeyedUnarchiver.unarchivedObject(ofClass: GTMAppAuthFetcherAuthorization.self, from: tokenData) {
            service.authorizer = authorization
        } else {
            // Generate code verifier and challenge
            let codeVerifier = OIDAuthorizationRequest.generateCodeVerifier()
            let codeChallenge = OIDAuthorizationRequest.codeChallengeS256(forVerifier: codeVerifier)
            
            // Create OAuth request
            let request = OIDAuthorizationRequest(
                configuration: configuration,
                clientId: clientId,
                clientSecret: clientSecret,
                scope: "https://www.googleapis.com/auth/tasks",
                redirectURL: URL(string: redirectURI)!,
                responseType: OIDResponseTypeCode,
                state: nil,
                nonce: nil,
                codeVerifier: codeVerifier,
                codeChallenge: codeChallenge,
                codeChallengeMethod: OIDOAuthorizationRequestCodeChallengeMethodS256,
                additionalParameters: nil
            )
            
            print("\nPlease visit this URL to authorize the application:")
            print(request.authorizationRequestURL().absoluteString)
            print("\nAfter authorizing, enter the code here: ", terminator: "")
            
            guard let code = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No code entered"])
            }
            
            // Exchange code for tokens
            let tokenRequest = OIDTokenRequest(
                configuration: configuration,
                grantType: OIDGrantTypeAuthorizationCode,
                authorizationCode: code,
                redirectURL: URL(string: redirectURI)!,
                clientID: clientId,
                clientSecret: clientSecret,
                scope: nil,
                refreshToken: nil,
                codeVerifier: codeVerifier,
                additionalParameters: nil
            )
            
            print("Exchanging authorization code for tokens...")
            let tokenResponse: OIDTokenResponse = try await withCheckedThrowingContinuation { continuation in
                OIDAuthorizationService.perform(tokenRequest) { response, error in
                    if let error = error {
                        print("Error getting token response: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                    if let response = response {
                        print("Successfully received token response")
                        continuation.resume(returning: response)
                    } else {
                        print("No token response received and no error provided")
                        continuation.resume(throwing: NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No token response"]))
                    }
                }
            }
            
            // Create authorization response
            let authResponse = OIDAuthorizationResponse(
                request: request,
                parameters: [
                    "code": code as NSString,
                    "state": (request.state ?? "") as NSString
                ]
            )
            
            // Create GTM authorization
            let authorization = GTMAppAuthFetcherAuthorization(
                authState: OIDAuthState(authorizationResponse: authResponse, tokenResponse: tokenResponse)
            )
            
            // Save the authorization
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: authorization, requiringSecureCoding: true) {
                let tokenString = data.base64EncodedString()
                Environment.saveGoogleToken(tokenString)
            }
            
            service.authorizer = authorization
        }
    }
    
    func setup() async throws {
        // Find or get the Reclaim task list
        let query = GTLRTasksQuery_TasklistsList.query()
        
        return try await withCheckedThrowingContinuation { continuation in
            service.executeQuery(query) { (ticket, result, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let taskLists = result as? GTLRTasks_TaskLists,
                      let items = taskLists.items else {
                    continuation.resume(throwing: NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No task lists found"]))
                    return
                }
                
                // Look for existing list
                if let existingList = items.first(where: { $0.title == self.listName }) {
                    self.taskListId = existingList.identifier
                    continuation.resume()
                    return
                }
                
                // Create new list if not found
                let newList = GTLRTasks_TaskList()
                newList.title = self.listName
                
                let createQuery = GTLRTasksQuery_TasklistsInsert.query(withObject: newList)
                
                self.service.executeQuery(createQuery) { (ticket, result, error) in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard let createdList = result as? GTLRTasks_TaskList,
                          let id = createdList.identifier else {
                        continuation.resume(throwing: NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create task list"]))
                        return
                    }
                    
                    self.taskListId = id
                    continuation.resume()
                }
            }
        }
    }
    
    func fetchTasks() async throws -> [Task] {
        guard let taskListId = taskListId else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Task list not initialized"])
        }
        
        let query = GTLRTasksQuery_TasksList.query(withTasklist: taskListId)
        query.showCompleted = true
        query.showHidden = true
        
        return try await withCheckedThrowingContinuation { continuation in
            service.executeQuery(query) { (ticket, result, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let taskList = result as? GTLRTasks_Tasks,
                      let items = taskList.items else {
                    continuation.resume(returning: [])
                    return
                }
                
                print("\nProcessing Google Tasks response...")
                
                // Create a more lenient date formatter for Google's format
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                
                let tasks = items.compactMap { googleTask -> Task? in
                    guard let id = googleTask.identifier,
                          let title = googleTask.title else { return nil }
                    
                    print("\nProcessing task: \(title)")
                    if let dueString = googleTask.due {
                        print(" - Raw due date string: \(dueString)")
                    }
                    
                    let dueDate = googleTask.due.flatMap { dateString -> Date? in
                        if let date = formatter.date(from: dateString) {
                            print(" - Parsed due date: \(date)")
                            return date
                        } else {
                            print(" - Failed to parse due date: \(dateString)")
                            return nil
                        }
                    }
                    
                    let lastModified = googleTask.updated.flatMap { formatter.date(from: $0) } ?? Date()
                    
                    return Task(
                        id: id,
                        title: title,
                        notes: googleTask.notes,
                        dueDate: dueDate,
                        isCompleted: googleTask.status == "completed",
                        lastModified: lastModified,
                        source: .googleTasks(taskId: id)
                    )
                }
                
                continuation.resume(returning: tasks)
            }
        }
    }
    
    func createTask(_ task: Task) async throws -> Task {
        guard let taskListId = taskListId else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Task list not initialized"])
        }
        
        let newTask = GTLRTasks_Task()
        newTask.title = task.title
        newTask.notes = task.notes
        if let dueDate = task.dueDate {
            newTask.due = ISO8601DateFormatter().string(from: dueDate)
        }
        newTask.status = task.isCompleted ? "completed" : "needsAction"
        
        let query = GTLRTasksQuery_TasksInsert.query(withObject: newTask, tasklist: taskListId)
        
        return try await withCheckedThrowingContinuation { continuation in
            service.executeQuery(query) { (ticket, result, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let createdTask = result as? GTLRTasks_Task,
                      let id = createdTask.identifier,
                      let title = createdTask.title else {
                    continuation.resume(throwing: NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid task created"]))
                    return
                }
                
                let lastModified = ISO8601DateFormatter().date(from: createdTask.updated ?? "") ?? Date()
                
                let formatter = ISO8601DateFormatter()
                let task = Task(
                    id: id,
                    title: title,
                    notes: createdTask.notes,
                    dueDate: createdTask.due.flatMap { formatter.date(from: $0) },
                    isCompleted: createdTask.status == "completed",
                    lastModified: lastModified,
                    source: .googleTasks(taskId: id)
                )
                
                continuation.resume(returning: task)
            }
        }
    }
    
    func updateTask(_ task: Task) async throws -> Task {
        guard let taskListId = taskListId else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Task list not initialized"])
        }
        
        guard case .googleTasks(let taskId) = task.source else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid task source"])
        }
        
        let updatedTask = GTLRTasks_Task()
        updatedTask.title = task.title
        updatedTask.notes = task.notes
        if let dueDate = task.dueDate {
            updatedTask.due = ISO8601DateFormatter().string(from: dueDate)
        }
        updatedTask.status = task.isCompleted ? "completed" : "needsAction"
        
        let query = GTLRTasksQuery_TasksUpdate.query(withObject: updatedTask, tasklist: taskListId, task: taskId)
        
        return try await withCheckedThrowingContinuation { continuation in
            service.executeQuery(query) { (ticket, result, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let updatedTask = result as? GTLRTasks_Task,
                      let id = updatedTask.identifier,
                      let title = updatedTask.title else {
                    continuation.resume(throwing: NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid task updated"]))
                    return
                }
                
                let lastModified = ISO8601DateFormatter().date(from: updatedTask.updated ?? "") ?? Date()
                
                let task = Task(
                    id: id,
                    title: title,
                    notes: updatedTask.notes,
                    dueDate: updatedTask.due.flatMap { ISO8601DateFormatter().date(from: $0) },
                    isCompleted: updatedTask.status == "completed",
                    lastModified: lastModified,
                    source: .googleTasks(taskId: id)
                )
                
                continuation.resume(returning: task)
            }
        }
    }
    
    func deleteTask(_ task: Task) async throws {
        guard let taskListId = taskListId else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Task list not initialized"])
        }
        
        guard case .googleTasks(let taskId) = task.source else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid task source"])
        }
        
        let query = GTLRTasksQuery_TasksDelete.query(withTasklist: taskListId, task: taskId)
        
        return try await withCheckedThrowingContinuation { continuation in
            service.executeQuery(query) { (ticket, result, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume()
            }
        }
    }
} 