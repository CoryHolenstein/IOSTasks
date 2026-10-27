//
// TaskNotifications.swift
// iOS UIKit Login
//
// Local reminders for tasks. Everything is scheduled on the phone itself
// (no server push needed): every time the task list loads, the app clears
// its old reminders and schedules fresh ones from the latest tasks.
//

import UIKit
import UserNotifications

final class TaskNotifications {
  
  static let shared = TaskNotifications()
  
  static let categoryIdentifier = "TASK_REMINDER"
  static let snoozeActionIdentifier = "SNOOZE_10_MINUTES"
  
  /// iOS keeps at most 64 pending notifications per app. Leave room for snoozes.
  private static let maxScheduled = 60
  
  /// Tasks with a date but no time get reminded at 9:00 AM.
  private static let defaultHour = 9
  
  private static let taskPrefix = "task-"
  private static let snoozePrefix = "snooze-"
  
  private let center = UNUserNotificationCenter.current()
  
  private init() {}
  
  // MARK: Setup
  // ===========
  
  /// Adds the "Snooze 10 Minutes" button to reminders. Call once at launch.
  func registerCategories() {
    let snooze = UNNotificationAction(
      identifier: TaskNotifications.snoozeActionIdentifier,
      title: "Snooze 10 Minutes",
      options: []
    )
    let category = UNNotificationCategory(
      identifier: TaskNotifications.categoryIdentifier,
      actions: [snooze],
      intentIdentifiers: [],
      options: []
    )
    center.setNotificationCategories([category])
  }
  
  /// Current permission, delivered on the main thread.
  func authorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
    center.getNotificationSettings { settings in
      DispatchQueue.main.async {
        completion(settings.authorizationStatus)
      }
    }
  }
  
  /// Shows the iOS permission prompt (only appears the first time).
  func requestPermission(completion: ((Bool) -> Void)? = nil) {
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      if let error = error {
        print("❌ Notification permission error: \(error)")
      }
      DispatchQueue.main.async {
        completion?(granted)
      }
    }
  }
  
  // MARK: Scheduling
  // ================
  
  private struct Plan {
    let request: UNNotificationRequest
    let nextDate: Date
  }
  
  /// Replaces all scheduled task reminders with fresh ones built from `tasks`.
  /// Asks for permission the first time a task actually has a reminder.
  func sync(with tasks: [[String: Any]]) {
    let allPlans = tasks.flatMap { self.plans(for: $0) }
    
    center.getNotificationSettings { settings in
      switch settings.authorizationStatus {
      case .notDetermined:
        guard !allPlans.isEmpty else { return }
        self.center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
          if granted {
            self.replaceScheduled(with: allPlans)
          }
        }
        
      case .denied:
        break
        
      default:
        self.replaceScheduled(with: allPlans)
      }
    }
  }
  
  /// Removes every task reminder and snooze, e.g. on log out.
  func removeAll() {
    center.getPendingNotificationRequests { requests in
      let ids = requests
        .map { $0.identifier }
        .filter { $0.hasPrefix(TaskNotifications.taskPrefix) || $0.hasPrefix(TaskNotifications.snoozePrefix) }
      self.center.removePendingNotificationRequests(withIdentifiers: ids)
    }
    center.removeAllDeliveredNotifications()
  }
  
  /// Shows the same reminder again in 10 minutes.
  func snooze(_ content: UNNotificationContent) {
    guard let copy = content.mutableCopy() as? UNMutableNotificationContent else { return }
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10 * 60, repeats: false)
    let request = UNNotificationRequest(
      identifier: TaskNotifications.snoozePrefix + UUID().uuidString,
      content: copy,
      trigger: trigger
    )
    center.add(request)
  }
  
  private func replaceScheduled(with plans: [Plan]) {
    // Soonest first, so the 64-notification limit drops the far-off ones.
    let chosen = plans
      .sorted { $0.nextDate < $1.nextDate }
      .prefix(TaskNotifications.maxScheduled)
    let keepIds = Set(chosen.map { $0.request.identifier })
    
    center.getPendingNotificationRequests { pending in
      let staleIds = pending
        .map { $0.identifier }
        .filter { $0.hasPrefix(TaskNotifications.taskPrefix) && !keepIds.contains($0) }
      self.center.removePendingNotificationRequests(withIdentifiers: staleIds)
      
      // Adding a request with an existing identifier replaces it.
      for plan in chosen {
        self.center.add(plan.request) { error in
          if let error = error {
            print("❌ Couldn’t schedule reminder: \(error)")
          }
        }
      }
      print("🔔 Scheduled \(chosen.count) reminder(s)")
    }
  }
  
  // MARK: Building reminders for one task
  // =====================================
  
  private func plans(for task: [String: Any]) -> [Plan] {
    guard let taskId = task["taskId"] as? String,
          let minutesBefore = task["reminderMinutesBefore"] as? Int
    else { return [] }
    
    let draft = TaskDraft(task: task)
    let recurrence = draft.recurrence
    let calendar = Calendar.current
    let now = Date()
    
    // When the task "happens"
    let taskTime: Date
    if let dueDate = draft.dueDate {
      if draft.hasTime {
        taskTime = dueDate
      } else {
        taskTime = calendar.date(bySettingHour: TaskNotifications.defaultHour, minute: 0, second: 0, of: dueDate) ?? dueDate
      }
    } else if let recurrence = recurrence {
      taskTime = defaultStart(for: recurrence)
    } else {
      return [] // a reminder needs a date or a repeat rule
    }
    
    // When the reminder fires
    let firstFire = taskTime.addingTimeInterval(-Double(minutesBefore) * 60)
    let content = makeContent(for: task, draft: draft, minutesBefore: minutesBefore)
    let idPrefix = TaskNotifications.taskPrefix + taskId + "-"
    
    // One-time task
    guard let rule = recurrence else {
      guard firstFire > now else { return [] }
      let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: firstFire)
      let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
      let request = UNNotificationRequest(identifier: idPrefix + "0", content: content, trigger: trigger)
      return [Plan(request: request, nextDate: firstFire)]
    }
    
    // Repeating task, already started: let iOS repeat it forever when the rule allows.
    if firstFire <= now {
      let repeating = repeatingComponents(for: rule, firstFire: firstFire)
      if !repeating.isEmpty {
        var result: [Plan] = []
        for (index, components) in repeating.enumerated() {
          let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
          let request = UNNotificationRequest(identifier: idPrefix + "r\(index)", content: content, trigger: trigger)
          result.append(Plan(request: request, nextDate: trigger.nextTriggerDate() ?? .distantFuture))
        }
        return result
      }
    }
    
    // Starts in the future, or an interval iOS can't repeat on its own
    // (e.g. every 45 minutes): schedule the next few occurrences. They're
    // topped up every time the app loads tasks.
    let count = (rule.unit == .minute || rule.unit == .hour) ? 12 : 6
    let dates = upcomingDates(for: rule, firstFire: firstFire, after: now, count: count)
    var result: [Plan] = []
    for (index, date) in dates.enumerated() {
      let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
      let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
      let request = UNNotificationRequest(identifier: idPrefix + "n\(index)", content: content, trigger: trigger)
      result.append(Plan(request: request, nextDate: date))
    }
    return result
  }
  
  /// Start time for a repeating task with no date: the top of the hour for
  /// minute/hour repeats, otherwise 9:00 AM today.
  private func defaultStart(for recurrence: Recurrence) -> Date {
    let calendar = Calendar.current
    let now = Date()
    switch recurrence.unit {
    case .minute, .hour:
      let hour = calendar.component(.hour, from: now)
      return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
    default:
      return calendar.date(bySettingHour: TaskNotifications.defaultHour, minute: 0, second: 0, of: now) ?? now
    }
  }
  
  /// Repeating calendar triggers for rules iOS can repeat by itself.
  /// e.g. every 30 minutes → at :00 and :30 of every hour;
  ///      every 4 hours → at 1:00, 5:00, 9:00... every day.
  /// Returns [] for rules that need explicit dates instead.
  private func repeatingComponents(for rule: Recurrence, firstFire: Date) -> [DateComponents] {
    let calendar = Calendar.current
    let parts = calendar.dateComponents([.month, .day, .weekday, .hour, .minute], from: firstFire)
    guard let hour = parts.hour, let minute = parts.minute else { return [] }
    let n = rule.interval
    
    switch rule.unit {
    case .minute where 60 % n == 0:
      return stride(from: minute % n, to: 60, by: n).map { DateComponents(minute: $0) }
      
    case .hour where 24 % n == 0:
      return stride(from: hour % n, to: 24, by: n).map { DateComponents(hour: $0, minute: minute) }
      
    case .day where n == 1:
      return [DateComponents(hour: hour, minute: minute)]
      
    case .week where n == 1:
      return [DateComponents(hour: hour, minute: minute, weekday: parts.weekday)]
      
    case .month where n == 1:
      return [DateComponents(day: parts.day, hour: hour, minute: minute)]
      
    case .year where n == 1:
      return [DateComponents(month: parts.month, day: parts.day, hour: hour, minute: minute)]
      
    default:
      return []
    }
  }
  
  /// The next `count` times the rule fires after `after`.
  private func upcomingDates(for rule: Recurrence, firstFire: Date, after now: Date, count: Int) -> [Date] {
    let calendar = Calendar.current
    let component = rule.unit.calendarComponent
    
    // Jump straight to roughly "now" instead of stepping from an old start date.
    var step = 0
    if firstFire <= now {
      let elapsed = calendar.dateComponents([component], from: firstFire, to: now).value(for: component) ?? 0
      step = max(0, elapsed / rule.interval)
    }
    
    var dates: [Date] = []
    var attempts = 0
    while dates.count < count && attempts < 1_000 {
      if let date = calendar.date(byAdding: component, value: rule.interval * step, to: firstFire), date > now {
        dates.append(date)
      }
      step += 1
      attempts += 1
    }
    return dates
  }
  
  // MARK: Notification content
  // ==========================
  
  private func makeContent(for task: [String: Any], draft: TaskDraft, minutesBefore: Int) -> UNNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = draft.name.isEmpty ? "Task reminder" : draft.name
    
    // "Due now", "Due in 15 minutes", or "Every 30 minutes" for repeating reminders
    let timing: String
    if minutesBefore == 0 {
      timing = draft.recurrence?.summary ?? "Due now"
    } else {
      timing = "Due in \(TaskNotifications.durationText(minutes: minutesBefore))"
    }
    
    let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    if notes.isEmpty {
      content.body = timing
    } else {
      content.subtitle = timing
      content.body = notes
    }
    
    // Quiet → no sound, straight to Notification Center
    // Standard → normal banner + sound
    // Urgent → Time Sensitive: breaks through Focus
    switch draft.alertStyle {
    case .quiet:
      content.sound = nil
      content.interruptionLevel = .passive
    case .standard:
      content.sound = .default
      content.interruptionLevel = .active
    case .urgent:
      content.sound = .default
      content.interruptionLevel = .timeSensitive
    }
    
    // Helps iOS pick which reminder to feature in a notification summary
    switch draft.importance {
    case .high: content.relevanceScore = 1.0
    case .medium: content.relevanceScore = 0.75
    case .low: content.relevanceScore = 0.5
    case .none: content.relevanceScore = 0.25
    }
    
    content.threadIdentifier = "tasks"
    content.categoryIdentifier = TaskNotifications.categoryIdentifier
    if let taskId = task["taskId"] as? String {
      content.userInfo = ["taskId": taskId]
    }
    return content
  }
  
  private static func durationText(minutes: Int) -> String {
    if minutes % 1440 == 0 {
      let days = minutes / 1440
      return days == 1 ? "1 day" : "\(days) days"
    }
    if minutes % 60 == 0 {
      let hours = minutes / 60
      return hours == 1 ? "1 hour" : "\(hours) hours"
    }
    return minutes == 1 ? "1 minute" : "\(minutes) minutes"
  }
}

extension Recurrence.Unit {
  var calendarComponent: Calendar.Component {
    switch self {
    case .minute: return .minute
    case .hour: return .hour
    case .day: return .day
    case .week: return .weekOfYear
    case .month: return .month
    case .year: return .year
    }
  }
}
