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
        
        // Create dictionaries for quick lookup
        let remindersByTitle = localReminders.reduce(into: [String: Task]()) { dict, reminder in
            dict[reminder.title] = reminder
        }
        let googleTasksByTitle = tasks.reduce(into: [String: Task]()) { dict, task in
            dict[task.title] = task
        }
        
        print("\nStep 1: Syncing completion status for existing tasks...")
        // First sync completion status for tasks that exist in both places
        for task in tasks {
            if let existingReminder = remindersByTitle[task.title] {
                print("\nProcessing task: \(task.title)")
                
                // If either is completed, mark both as completed
                if task.isCompleted || existingReminder.isCompleted {
                    print(" - One or both marked as complete, syncing completion status")
                    
                    // Update reminder if needed
                    if !existingReminder.isCompleted {
                        print(" - Updating reminder completion status")
                        var updatedReminder = existingReminder
                        updatedReminder.isCompleted = true
                        let _ = try await remindersService.updateReminder(updatedReminder)
                    }
                    
                    // Update Google task if needed
                    if !task.isCompleted {
                        print(" - Updating Google task completion status")
                        var updatedTask = task
                        updatedTask.isCompleted = true
                        // Ensure we keep all original task properties
                        updatedTask.title = task.title
                        updatedTask.notes = task.notes
                        updatedTask.dueDate = task.dueDate
                        updatedTask.source = task.source  // Keep the original source with taskId
                        print(" - Updating Google task: \(updatedTask.title) with ID from source: \(updatedTask.id)")
                        let _ = try await googleTasksService.updateTask(updatedTask)
                        print(" - Successfully updated Google task completion status")
                    }
                }
            }
        }
        
        print("\nStep 2: Creating missing reminders from Google Tasks...")
        // Create reminders for Google Tasks that don't exist in Reminders
        for task in tasks {
            if remindersByTitle[task.title] == nil {
                print("\nCreating reminder for task: \(task.title)")
                var reminderTask = task
                reminderTask.source = .appleReminders(reminderId: "")
                let createdTask = try await remindersService.createReminder(reminderTask)
                print(" - Successfully created reminder with ID: \(createdTask.id)")
            }
        }
        
        print("\nStep 3: Creating missing Google Tasks from Reminders...")
        // Create Google Tasks for Reminders that don't exist in Google Tasks
        for reminder in localReminders {
            if googleTasksByTitle[reminder.title] == nil {
                print("\nCreating Google task for reminder: \(reminder.title)")
                var newTask = reminder
                newTask.source = .googleTasks(taskId: "")
                let createdTask = try await googleTasksService.createTask(newTask)
                print(" - Successfully created Google task with ID: \(createdTask.id)")
            }
        }
        
        print("\nSync completed successfully")
    }
} 