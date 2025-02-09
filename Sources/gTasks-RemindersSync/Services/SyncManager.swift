import Foundation

class SyncManager {
    private let googleTasksService: GoogleTasksService
    private let remindersService: RemindersService
    
    init() async throws {
        googleTasksService = try await GoogleTasksService()
        remindersService = RemindersService()
    }
    
    func setup() async throws {
        // Request access to Reminders
        try await remindersService.requestAccess()
        try remindersService.setup()
        
        // Set up Google Tasks
        try await googleTasksService.setup()
    }
    
    func sync() async throws {
        print("Fetching tasks from Google Tasks...")
        let tasks = try await googleTasksService.fetchTasks()
        print("Found \(tasks.count) tasks in Google Tasks")
        
        print("Fetching reminders from Apple Reminders...")
        let localReminders = try await remindersService.fetchReminders()
        print("Found \(localReminders.count) reminders in Apple Reminders")
        
        // Create a dictionary of existing reminders by title for quick lookup
        let remindersByTitle = localReminders.reduce(into: [String: Task]()) { dict, reminder in
            dict[reminder.title] = reminder
        }
        
        print("\nSyncing Google Tasks to Apple Reminders...")
        
        // Process each Google task
        for task in tasks {
            print("\nProcessing Google task: \(task.title) (ID: \(task.id))")
            
            if let existingReminder = remindersByTitle[task.title] {
                print(" - Found existing reminder with ID: \(existingReminder.id)")
                
                // Update the reminder if needed
                if existingReminder.isCompleted != task.isCompleted || 
                   existingReminder.notes != task.notes ||
                   existingReminder.dueDate != task.dueDate {
                    print(" - Updating reminder to match Google task")
                    var updatedTask = existingReminder
                    updatedTask.isCompleted = task.isCompleted
                    updatedTask.notes = task.notes
                    updatedTask.dueDate = task.dueDate
                    let _ = try await remindersService.updateReminder(updatedTask)
                    print(" - Successfully updated reminder")
                } else {
                    print(" - Reminder is already in sync")
                }
            } else {
                print(" - Creating new reminder")
                // Create a new reminder from the Google task
                var reminderTask = task
                reminderTask.source = .appleReminders(reminderId: "")
                let createdTask = try await remindersService.createReminder(reminderTask)
                print(" - Successfully created reminder with ID: \(createdTask.id)")
            }
        }
        
        print("\nSync completed successfully")
    }
} 