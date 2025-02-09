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
        
        // 2. Create dictionaries for quick lookup using composite keys
        let googleTasksDict = tasks.reduce(into: [String: Task]()) { dict, task in
            let key = "\(task.title)_\(task.id)"
            dict[key] = task
        }
        
        let remindersDict = localReminders.reduce(into: [String: Task]()) { dict, reminder in
            let key = "\(reminder.title)_\(reminder.id)"
            dict[key] = reminder
        }
        
        // Create a title-only dictionary for checking duplicates
        let googleTasksByTitle = tasks.reduce(into: [String: [Task]]()) { dict, task in
            dict[task.title, default: []].append(task)
        }
        
        // 3. Find items that need syncing
        var tasksToCreate: [Task] = []
        var tasksToUpdate: [Task] = []
        let tasksToDelete: [Task] = []
        
        print("\nAnalyzing tasks for sync...")
        
        // Process Google Tasks
        for googleTask in tasks {
            print("Processing Google task: \(googleTask.title) (ID: \(googleTask.id))")
            let key = "\(googleTask.title)_\(googleTask.id)"
            if let reminder = remindersDict[key] {
                print(" - Found matching reminder")
                // Task exists in both places - check if update needed
                if googleTask.lastModified > reminder.lastModified {
                    print(" - Google task is newer, will update reminder")
                    var updatedTask = reminder
                    updatedTask.title = googleTask.title
                    updatedTask.notes = googleTask.notes
                    updatedTask.dueDate = googleTask.dueDate
                    updatedTask.isCompleted = googleTask.isCompleted
                    tasksToUpdate.append(updatedTask)
                }
            } else {
                print(" - No matching reminder found, will create new reminder")
                // Task only exists in Google - create in Reminders
                var newTask = googleTask
                newTask.source = .appleReminders(reminderId: "") // ID will be set when created
                tasksToCreate.append(newTask)
            }
        }
        
        // Process Reminders
        for reminder in localReminders {
            print("Processing Reminder: \(reminder.title) (ID: \(reminder.id))")
            let key = "\(reminder.title)_\(reminder.id)"
            if let googleTask = googleTasksDict[key] {
                print(" - Found matching Google task")
                // Task exists in both places - check if update needed
                if reminder.lastModified > googleTask.lastModified {
                    print(" - Reminder is newer, will update Google task")
                    var updatedTask = googleTask
                    updatedTask.title = reminder.title
                    updatedTask.notes = reminder.notes
                    updatedTask.dueDate = reminder.dueDate
                    updatedTask.isCompleted = reminder.isCompleted
                    tasksToUpdate.append(updatedTask)
                }
            } else {
                // Skip creating Google tasks from reminders in this first sync
                print(" - No matching Google task found, skipping for now")
            }
        }
        
        // 4. Apply changes
        print("\nApplying changes:")
        print("Tasks to create: \(tasksToCreate.count)")
        print("Tasks to update: \(tasksToUpdate.count)")
        print("Tasks to delete: \(tasksToDelete.count)")
        
        // First create all reminders from Google Tasks
        for task in tasks {
            print("\nCreating reminder from Google task: \(task.title)")
            do {
                // Create a new task with source set to Apple Reminders
                var reminderTask = task
                reminderTask.source = .appleReminders(reminderId: "")
                let createdTask = try await remindersService.createReminder(reminderTask)
                print("Successfully created reminder with ID: \(createdTask.id)")
            } catch {
                print("Failed to create reminder: \(error.localizedDescription)")
                throw error
            }
        }
        
        for task in tasksToUpdate {
            switch task.source {
            case .googleTasks:
                let _ = try await googleTasksService.updateTask(task)
            case .appleReminders:
                let _ = try await remindersService.updateReminder(task)
            }
        }
        
        for task in tasksToDelete {
            switch task.source {
            case .googleTasks:
                try await googleTasksService.deleteTask(task)
            case .appleReminders:
                try await remindersService.deleteReminder(task)
            }
        }
    }
} 