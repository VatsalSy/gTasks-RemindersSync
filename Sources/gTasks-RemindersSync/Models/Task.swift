import Foundation

struct Task: Identifiable {
    let id: String
    var title: String
    var notes: String?
    var dueDate: Date?
    var isCompleted: Bool
    var lastModified: Date
    
    // Source system identifier
    enum Source {
        case googleTasks(taskId: String)
        case appleReminders(reminderId: String)
    }
    var source: Source
    
    // For tracking sync status
    var needsSync: Bool = false
} 