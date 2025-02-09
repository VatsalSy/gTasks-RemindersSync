import Foundation
import EventKit

class RemindersService {
    private let store: EKEventStore
    private let listName = "GTasks"
    private var reminderList: EKCalendar?
    
    init() {
        store = EKEventStore()
    }
    
    func requestAccess() async throws {
        if #available(macOS 14.0, *) {
            try await store.requestFullAccessToReminders()
        } else {
            return try await withCheckedThrowingContinuation { continuation in
                store.requestAccess(to: .reminder) { granted, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if !granted {
                        continuation.resume(throwing: NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Reminders access denied"]))
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    func setup() throws {
        print("Setting up Reminders list...")
        // Find or create the Reminders list
        let calendars = store.calendars(for: .reminder)
        print("Found \(calendars.count) reminder lists:")
        for calendar in calendars {
            print(" - \(calendar.title)")
        }
        
        if let existingList = calendars.first(where: { $0.title == listName }) {
            print("Found existing list: \(listName)")
            reminderList = existingList
        } else {
            print("Creating new list: \(listName)")
            let newList = EKCalendar(for: .reminder, eventStore: store)
            newList.title = listName
            newList.source = store.defaultCalendarForNewReminders()?.source
            
            try store.saveCalendar(newList, commit: true)
            reminderList = newList
            print("Successfully created new list")
        }
    }
    
    func fetchReminders() async throws -> [Task] {
        guard let calendar = reminderList else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Reminders list not found"])
        }
        
        print("Fetching reminders from list: \(calendar.title)")
        let predicate = store.predicateForReminders(in: [calendar])
        
        return try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                guard let reminders = reminders else {
                    continuation.resume(returning: [])
                    return
                }
                
                let tasks = reminders.map { reminder -> Task in
                    Task(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "",
                        notes: reminder.notes,
                        dueDate: reminder.dueDateComponents?.date,
                        isCompleted: reminder.isCompleted,
                        lastModified: reminder.lastModifiedDate ?? Date(),
                        source: .appleReminders(reminderId: reminder.calendarItemIdentifier)
                    )
                }
                
                continuation.resume(returning: tasks)
            }
        }
    }
    
    func createReminder(_ task: Task) async throws -> Task {
        guard let calendar = reminderList else {
            print("Error: Reminders list not found when creating reminder")
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Reminders list not found"])
        }
        
        print("Creating reminder in list '\(calendar.title)': \(task.title)")
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = task.title
        reminder.notes = task.notes
        if let dueDate = task.dueDate {
            print(" - Setting due date: \(dueDate)")
            
            // Create date components
            let calendar = Calendar.current
            let components = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute], from: dueDate)
            print(" - Date components: year=\(components.year ?? 0), month=\(components.month ?? 0), day=\(components.day ?? 0), hour=\(components.hour ?? 0), minute=\(components.minute ?? 0)")
            
            // Set both due date and start date components
            reminder.dueDateComponents = components
            reminder.startDateComponents = components
            
            // Create an alarm for the due date
            let alarm = EKAlarm(absoluteDate: dueDate)
            reminder.addAlarm(alarm)
            
            // Verify the due date was set
            if let setDueDate = reminder.dueDateComponents?.date {
                print(" - Verified due date set to: \(setDueDate)")
            } else {
                print(" - Warning: Due date components did not produce a valid date")
            }
        } else {
            print(" - No due date provided for task")
        }
        reminder.isCompleted = task.isCompleted
        print(" - Completed: \(task.isCompleted)")
        
        do {
            try store.save(reminder, commit: true)
            print("Successfully created reminder: \(reminder.title ?? "")")
            
            // Ensure changes are committed
            try store.commit()
            print("Changes committed to store")
            
            // Verify the reminder was created
            if let savedReminder = store.calendarItem(withIdentifier: reminder.calendarItemIdentifier) as? EKReminder {
                print("Verified reminder exists with ID: \(savedReminder.calendarItemIdentifier)")
            } else {
                print("Warning: Could not verify reminder after save")
            }
        } catch {
            print("Error saving reminder: \(error.localizedDescription)")
            throw error
        }
        
        return Task(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            notes: reminder.notes,
            dueDate: reminder.dueDateComponents?.date,
            isCompleted: reminder.isCompleted,
            lastModified: reminder.lastModifiedDate ?? Date(),
            source: .appleReminders(reminderId: reminder.calendarItemIdentifier)
        )
    }
    
    func updateReminder(_ task: Task) async throws -> Task {
        guard case .appleReminders(let reminderId) = task.source else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid task source"])
        }
        
        guard let reminder = try await fetchReminder(withId: reminderId) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Reminder not found"])
        }
        
        reminder.title = task.title
        reminder.notes = task.notes
        if let dueDate = task.dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        } else {
            reminder.dueDateComponents = nil
        }
        reminder.isCompleted = task.isCompleted
        
        try store.save(reminder, commit: true)
        
        return Task(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            notes: reminder.notes,
            dueDate: reminder.dueDateComponents?.date,
            isCompleted: reminder.isCompleted,
            lastModified: reminder.lastModifiedDate ?? Date(),
            source: .appleReminders(reminderId: reminder.calendarItemIdentifier)
        )
    }
    
    func deleteReminder(_ task: Task) async throws {
        guard case .appleReminders(let reminderId) = task.source else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid task source"])
        }
        
        guard let reminder = try await fetchReminder(withId: reminderId) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Reminder not found"])
        }
        
        try store.remove(reminder, commit: true)
    }
    
    private func fetchReminder(withId id: String) async throws -> EKReminder? {
        guard let calendar = reminderList else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Reminders list not found"])
        }
        
        let predicate = store.predicateForReminders(in: [calendar])
        
        return try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                guard let reminders = reminders else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let reminder = reminders.first { $0.calendarItemIdentifier == id }
                continuation.resume(returning: reminder)
            }
        }
    }
} 