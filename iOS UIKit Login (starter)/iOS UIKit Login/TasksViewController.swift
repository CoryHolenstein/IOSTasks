//
// TasksViewController.swift
// iOS UIKit Login
//
// Task lists (Today / Upcoming / All Tasks) - Create, Read, Update, Delete tasks
//

import UIKit
import Auth0

// MARK: - Theme
// =============

enum Theme {
  static let accent = UIColor.systemIndigo
  
  static func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
    let base = UIFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return UIFont(descriptor: descriptor, size: size)
  }
  
  /// Big rounded titles that shrink into the bar as you scroll.
  static func styleNavigationBar(_ navigationController: UINavigationController) {
    let navigationBar = navigationController.navigationBar
    navigationBar.prefersLargeTitles = true
    navigationBar.tintColor = accent
    
    let largeTitleAttributes: [NSAttributedString.Key: Any] = [.font: roundedFont(size: 34, weight: .bold)]
    let titleAttributes: [NSAttributedString.Key: Any] = [.font: roundedFont(size: 17, weight: .semibold)]
    
    let standard = UINavigationBarAppearance()
    standard.configureWithDefaultBackground()
    standard.largeTitleTextAttributes = largeTitleAttributes
    standard.titleTextAttributes = titleAttributes
    
    let scrollEdge = UINavigationBarAppearance()
    scrollEdge.configureWithTransparentBackground()
    scrollEdge.largeTitleTextAttributes = largeTitleAttributes
    scrollEdge.titleTextAttributes = titleAttributes
    
    navigationBar.standardAppearance = standard
    navigationBar.compactAppearance = standard
    navigationBar.scrollEdgeAppearance = scrollEdge
  }
}

// MARK: - Due date helpers
// ========================

enum TaskDates {
  
  private static let parser: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()
  
  private static let shortDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("MMMd")
    return formatter
  }()
  
  private static let shortDateWithYearFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("MMMdy")
    return formatter
  }()
  
  private static let weekdayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("EEEE")
    return formatter
  }()
  
  private static let sectionDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("EEEEMMMd")
    return formatter
  }()
  
  static let headerDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
    return formatter
  }()
  
  private static let timeParser: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "HH:mm"
    return formatter
  }()
  
  private static let timeDisplayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter
  }()
  
  /// "YYYY-MM-DD", the format the backend stores dates in.
  static func dateString(_ date: Date) -> String {
    return parser.string(from: date)
  }
  
  /// "HH:mm" (24-hour), the format sent to the backend as "dueTime".
  static func timeString(_ date: Date) -> String {
    return timeParser.string(from: date)
  }
  
  static func dueTime(of task: [String: Any]) -> (hour: Int, minute: Int)? {
    let raw = (task["dueTime"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty, let date = timeParser.date(from: raw) else { return nil }
    let components = Calendar.current.dateComponents([.hour, .minute], from: date)
    guard let hour = components.hour, let minute = components.minute else { return nil }
    return (hour, minute)
  }
  
  /// e.g. "3:30 PM", or nil when the task has no time.
  static func displayTime(of task: [String: Any]) -> String? {
    guard let time = dueTime(of: task),
          let date = Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date())
    else { return nil }
    return timeDisplayFormatter.string(from: date)
  }
  
  /// Today's date in the same format the backend stores ("YYYY-MM-DD").
  static var todayString: String {
    return parser.string(from: Date())
  }
  
  static func rawDueDate(of task: [String: Any]) -> String {
    let raw = task["dueDate"] as? String ?? ""
    return raw.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  
  static func dueDate(of task: [String: Any]) -> Date? {
    let raw = rawDueDate(of: task)
    guard !raw.isEmpty else { return nil }
    return parser.date(from: raw)
  }
  
  /// 0 = today, 1 = tomorrow, -1 = yesterday, etc.
  static func daysFromToday(_ date: Date) -> Int {
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: Date())
    let end = calendar.startOfDay(for: date)
    return calendar.dateComponents([.day], from: start, to: end).day ?? 0
  }
  
  static func shortDate(_ date: Date) -> String {
    let sameYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
    return sameYear ? shortDateFormatter.string(from: date) : shortDateWithYearFormatter.string(from: date)
  }
  
  static func sectionTitle(for date: Date, days: Int) -> String {
    if days == 1 { return "Tomorrow" }
    let sameYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
    return sameYear ? sectionDateFormatter.string(from: date) : shortDateWithYearFormatter.string(from: date)
  }
  
  /// Text, icon and color for the due-date badge on a task card. Nil when the task has no due date.
  static func badge(for task: [String: Any]) -> (text: String, symbol: String, color: UIColor)? {
    let raw = rawDueDate(of: task)
    guard !raw.isEmpty else { return nil }
    
    // Typed something that isn't YYYY-MM-DD: show it as-is.
    guard let date = dueDate(of: task) else {
      return (raw, "calendar", .secondaryLabel)
    }
    
    let base: (text: String, symbol: String, color: UIColor)
    let days = daysFromToday(date)
    switch days {
    case ..<0:
      base = ("Overdue · \(shortDate(date))", "exclamationmark.circle.fill", .systemRed)
    case 0:
      base = ("Today", "star.fill", .systemOrange)
    case 1:
      base = ("Tomorrow", "calendar", Theme.accent)
    case 2...6:
      base = (weekdayFormatter.string(from: date), "calendar", Theme.accent)
    default:
      base = (shortDate(date), "calendar", .secondaryLabel)
    }
    
    // "Today · 3:30 PM"
    if let time = displayTime(of: task) {
      return ("\(base.text) · \(time)", base.symbol, base.color)
    }
    return base
  }
}

// MARK: - Task list
// =================

enum TaskListMode {
  case today
  case upcoming
  case all
}

private struct TaskSection {
  let title: String
  let color: UIColor?
  var tasks: [[String: Any]]
}

private struct DatedTask {
  let task: [String: Any]
  let date: Date
  let days: Int
}

class TasksViewController: UIViewController {
  
  /// API Gateway base URL. Routes: get-all-tasks, create-task, edit-task, delete-task
  private static let apiBaseURL = "https://r283rocx67.execute-api.us-east-1.amazonaws.com/dev/tasks"
  
  private let tableView = UITableView(frame: .zero, style: .grouped)
  private let pullToRefresh = UIRefreshControl()
  private let summaryLabel = UILabel()
  private lazy var emptyStateView = makeEmptyStateView()
  
  private var tasks: [[String: Any]] = []
  private var sections: [TaskSection] = []
  private var hasLoaded = false
  
  var mode: TaskListMode = .all
  var user: User?
  var credentials: Credentials?
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    setupUI()
  }
  
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    
    // Reload every time the tab appears, so changes made in other tabs show up.
    loadTasks()
  }
  
  private func setupUI() {
    switch mode {
    case .today: title = "Today"
    case .upcoming: title = "Upcoming"
    case .all: title = "All Tasks"
    }
    view.backgroundColor = .systemGroupedBackground
    
    // "+" button in the navigation bar
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      image: UIImage(systemName: "plus.circle.fill"),
      style: .plain,
      target: self,
      action: #selector(createTaskTapped)
    )
    
    // Table view
    tableView.delegate = self
    tableView.dataSource = self
    tableView.register(TaskCardCell.self, forCellReuseIdentifier: TaskCardCell.reuseID)
    tableView.backgroundColor = .systemGroupedBackground
    tableView.separatorStyle = .none
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 88
    tableView.sectionHeaderHeight = UITableView.automaticDimension
    tableView.estimatedSectionHeaderHeight = 44
    tableView.sectionHeaderTopPadding = 0
    tableView.contentInset.bottom = 16
    
    // Pull down to refresh
    pullToRefresh.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
    tableView.refreshControl = pullToRefresh
    
    // Summary line under the big title, e.g. "Monday, October 12 · 2 due"
    let header = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 30))
    summaryLabel.font = Theme.roundedFont(size: 15, weight: .medium)
    summaryLabel.textColor = .secondaryLabel
    summaryLabel.translatesAutoresizingMaskIntoConstraints = false
    header.addSubview(summaryLabel)
    NSLayoutConstraint.activate([
      summaryLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
      summaryLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
      summaryLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
    ])
    tableView.tableHeaderView = header
    
    // The table fills the whole screen so the large title collapses on scroll.
    view.addSubview(tableView)
    tableView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      tableView.topAnchor.constraint(equalTo: view.topAnchor),
      tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
  }
  
  @objc private func refreshPulled() {
    loadTasks()
  }
  
  // MARK: Building the list
  // =======================
  
  private func taskName(_ task: [String: Any]) -> String {
    return task["name"] as? String ?? ""
  }
  
  private func rebuildSections() {
    let dated: [DatedTask] = tasks.compactMap { (task) -> DatedTask? in
      guard let date = TaskDates.dueDate(of: task) else { return nil }
      return DatedTask(task: task, date: date, days: TaskDates.daysFromToday(date))
    }.sorted { $0.date < $1.date }
    
    let undated = tasks
      .filter { TaskDates.dueDate(of: $0) == nil }
      .sorted { taskName($0).localizedCaseInsensitiveCompare(taskName($1)) == .orderedAscending }
    
    let overdue = dated.filter { $0.days < 0 }.map { $0.task }
    let dueToday = dated.filter { $0.days == 0 }.map { $0.task }
    let future = dated.filter { $0.days > 0 }
    
    var result: [TaskSection] = []
    
    switch mode {
    case .today:
      result = [
        TaskSection(title: "Overdue", color: .systemRed, tasks: overdue),
        TaskSection(title: "Today", color: nil, tasks: dueToday),
      ]
      
    case .upcoming:
      // One section per day
      for item in future {
        let title = TaskDates.sectionTitle(for: item.date, days: item.days)
        if let last = result.last, last.title == title {
          result[result.count - 1].tasks.append(item.task)
        } else {
          result.append(TaskSection(title: title, color: nil, tasks: [item.task]))
        }
      }
      
    case .all:
      result = [
        TaskSection(title: "Overdue", color: .systemRed, tasks: overdue),
        TaskSection(title: "Today", color: nil, tasks: dueToday),
        TaskSection(title: "Upcoming", color: nil, tasks: future.map { $0.task }),
        TaskSection(title: "No Due Date", color: nil, tasks: undated),
      ]
    }
    
    sections = result.filter { !$0.tasks.isEmpty }
  }
  
  private func reloadList() {
    rebuildSections()
    tableView.reloadData()
    updateSummary()
    updateEmptyState()
  }
  
  private func task(at indexPath: IndexPath) -> [String: Any] {
    return sections[indexPath.section].tasks[indexPath.row]
  }
  
  private func indexPath(forTaskId taskId: String) -> IndexPath? {
    for (sectionIndex, section) in sections.enumerated() {
      if let row = section.tasks.firstIndex(where: { ($0["taskId"] as? String) == taskId }) {
        return IndexPath(row: row, section: sectionIndex)
      }
    }
    return nil
  }
  
  private func updateSummary() {
    let count = sections.reduce(0) { $0 + $1.tasks.count }
    
    switch mode {
    case .today:
      let overdueCount = sections.first(where: { $0.title == "Overdue" })?.tasks.count ?? 0
      let dueCount = count - overdueCount
      var parts = [TaskDates.headerDateFormatter.string(from: Date())]
      if count == 0 && hasLoaded {
        parts.append("All clear")
      } else {
        if dueCount > 0 { parts.append("\(dueCount) due") }
        if overdueCount > 0 { parts.append("\(overdueCount) overdue") }
      }
      summaryLabel.text = parts.joined(separator: " · ")
      
    case .upcoming:
      summaryLabel.text = hasLoaded ? (count == 1 ? "1 task coming up" : "\(count) tasks coming up") : nil
      
    case .all:
      summaryLabel.text = hasLoaded ? (count == 1 ? "1 task" : "\(count) tasks") : nil
    }
  }
  
  private func updateEmptyState() {
    tableView.backgroundView = (hasLoaded && sections.isEmpty) ? emptyStateView : nil
  }
  
  private func makeEmptyStateView() -> UIView {
    let symbol: String
    let heading: String
    let message: String
    
    switch mode {
    case .today:
      symbol = "sun.max.fill"
      heading = "You’re all caught up"
      message = "Nothing due today. Enjoy it."
    case .upcoming:
      symbol = "calendar"
      heading = "Nothing coming up"
      message = "Tasks with a future due date will show up here."
    case .all:
      symbol = "checklist"
      heading = "No tasks yet"
      message = "Tap + to create your first task."
    }
    
    let iconView = UIImageView(image: UIImage(systemName: symbol))
    iconView.tintColor = Theme.accent
    iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 52, weight: .regular)
    
    let headingLabel = UILabel()
    headingLabel.text = heading
    headingLabel.font = Theme.roundedFont(size: 22, weight: .bold)
    headingLabel.textAlignment = .center
    
    let messageLabel = UILabel()
    messageLabel.text = message
    messageLabel.font = .systemFont(ofSize: 15)
    messageLabel.textColor = .secondaryLabel
    messageLabel.textAlignment = .center
    messageLabel.numberOfLines = 0
    
    let stack = UIStackView(arrangedSubviews: [iconView, headingLabel, messageLabel])
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 8
    stack.setCustomSpacing(16, after: iconView)
    stack.translatesAutoresizingMaskIntoConstraints = false
    
    let container = UIView()
    container.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -40),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 40),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -40),
    ])
    return container
  }
  
  // MARK: Load
  // ==========
  
  private func loadTasks() {
    guard let userEmail = user?.email else {
      pullToRefresh.endRefreshing()
      return
    }
    guard let credentials = credentials else {
      print("❌ No credentials found")
      pullToRefresh.endRefreshing()
      return
    }
    
    guard let url = URL(string: "\(TasksViewController.apiBaseURL)/get-all-tasks") else { return }
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let payload = ["userId": userEmail]
    
    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: payload)
      
      URLSession.shared.dataTask(with: request) { data, response, error in
        DispatchQueue.main.async {
          self.pullToRefresh.endRefreshing()
          
          if let error = error {
            print("❌ Failed to load tasks: \(error)")
            return
          }
          
          guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("❌ Failed to load tasks (Status: \(status))\(TasksViewController.serverMessage(from: data))")
            return
          }
          
          do {
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            if let dict = jsonObject as? [String: Any], let tasksArray = dict["tasks"] as? [[String: Any]] {
              self.tasks = tasksArray
              self.hasLoaded = true
              self.reloadList()
              
              // Keep reminders in sync with the latest tasks
              TaskNotifications.shared.sync(with: tasksArray)
            }
          } catch {
            print("❌ Failed to parse tasks: \(error)")
          }
        }
      }.resume()
    } catch {
      pullToRefresh.endRefreshing()
      print("❌ Failed to encode request: \(error)")
    }
  }
  
  // MARK: Create
  // ============
  
  @objc private func createTaskTapped() {
    var draft = TaskDraft()
    
    // On the Today tab, new tasks default to today.
    if mode == .today {
      draft.dueDate = Calendar.current.startOfDay(for: Date())
    }
    
    presentTaskForm(draft: draft, taskId: nil)
  }
  
  /// Opens the task form. Pass a taskId to edit an existing task.
  private func presentTaskForm(draft: TaskDraft, taskId: String?) {
    let form = TaskFormViewController(draft: draft, editingExistingTask: taskId != nil)
    form.onSave = { [weak self] savedDraft in
      guard let self = self else { return }
      if let taskId = taskId {
        self.updateTask(taskId: taskId, draft: savedDraft)
      } else {
        self.createTask(draft: savedDraft)
      }
    }
    
    let navigationController = UINavigationController(rootViewController: form)
    navigationController.navigationBar.tintColor = Theme.accent
    present(navigationController, animated: true)
  }
  
  private func createTask(draft: TaskDraft) {
    guard let userEmail = user?.email else { return }
    guard let credentials = credentials else { return }
    
    guard let url = URL(string: "\(TasksViewController.apiBaseURL)/create-task") else { return }
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let payload = draft.payload(userId: userEmail, taskId: nil)
    
    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: payload)
      
      URLSession.shared.dataTask(with: request) { data, response, error in
        DispatchQueue.main.async {
          if let error = error {
            self.showError("Failed to create task: \(error.localizedDescription)")
            return
          }
          
          if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
              print("✅ Task created successfully")
              UINotificationFeedbackGenerator().notificationOccurred(.success)
              self.loadTasks()
            } else {
              self.showError("Failed to create task (Status: \(httpResponse.statusCode))\(TasksViewController.serverMessage(from: data))")
            }
          }
        }
      }.resume()
    } catch {
      showError("Failed to encode request: \(error.localizedDescription)")
    }
  }
  
  // MARK: Delete
  // ============
  
  private func confirmDelete(_ task: [String: Any], completion: @escaping (Bool) -> Void) {
    let name = task["name"] as? String ?? "this task"
    
    let alert = UIAlertController(
      title: "Delete Task?",
      message: "“\(name)” will be permanently deleted.",
      preferredStyle: .alert
    )
    
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
      completion(false)
    })
    
    alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
      completion(true)
    })
    
    present(alert, animated: true)
  }
  
  /// Removes the task from the screen right away, before the server responds.
  private func removeTaskFromList(taskId: String) {
    guard let indexPath = indexPath(forTaskId: taskId) else { return }
    let rowsInSection = sections[indexPath.section].tasks.count
    
    tasks.removeAll { ($0["taskId"] as? String) == taskId }
    rebuildSections()
    
    tableView.performBatchUpdates({
      if rowsInSection == 1 {
        self.tableView.deleteSections(IndexSet(integer: indexPath.section), with: .fade)
      } else {
        self.tableView.deleteRows(at: [indexPath], with: .automatic)
      }
    })
    
    updateSummary()
    updateEmptyState()
  }
  
  private func deleteTask(taskId: String) {
    guard let userEmail = user?.email else { return }
    guard let credentials = credentials else { return }
    
    guard let url = URL(string: "\(TasksViewController.apiBaseURL)/delete-task") else { return }
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let payload: [String: Any] = [
      "userId": userEmail,
      "taskId": taskId
    ]
    
    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: payload)
      
      URLSession.shared.dataTask(with: request) { data, response, error in
        DispatchQueue.main.async {
          if let error = error {
            self.showError("Failed to delete task: \(error.localizedDescription)")
            self.loadTasks() // Put the task back on screen
            return
          }
          
          if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 200 {
              print("✅ Task deleted successfully")
              self.loadTasks()
            } else {
              self.showError("Failed to delete task (Status: \(httpResponse.statusCode))\(TasksViewController.serverMessage(from: data))")
              self.loadTasks() // Put the task back on screen
            }
          }
        }
      }.resume()
    } catch {
      showError("Failed to encode request: \(error.localizedDescription)")
      loadTasks()
    }
  }
  
  // MARK: Edit
  // ==========
  
  private func editTask(_ task: [String: Any]) {
    guard let taskId = task["taskId"] as? String else {
      showError("This task can’t be edited because it has no ID.")
      return
    }
    
    presentTaskForm(draft: TaskDraft(task: task), taskId: taskId)
  }
  
  private func updateTask(taskId: String, draft: TaskDraft) {
    guard let userEmail = user?.email else { return }
    guard let credentials = credentials else { return }
    
    guard let url = URL(string: "\(TasksViewController.apiBaseURL)/edit-task") else { return }
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let payload = draft.payload(userId: userEmail, taskId: taskId)
    
    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: payload)
      
      URLSession.shared.dataTask(with: request) { data, response, error in
        DispatchQueue.main.async {
          if let error = error {
            self.showError("Failed to update task: \(error.localizedDescription)")
            return
          }
          
          if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 200 {
              print("✅ Task updated successfully")
              UINotificationFeedbackGenerator().notificationOccurred(.success)
              self.loadTasks()
            } else {
              self.showError("Failed to update task (Status: \(httpResponse.statusCode))\(TasksViewController.serverMessage(from: data))")
            }
          }
        }
      }.resume()
    } catch {
      showError("Failed to encode request: \(error.localizedDescription)")
    }
  }
  
  /// The reason the server gave for an error, e.g. "\n\nTask not found".
  /// Reads {"error": "..."} from our Lambda or {"message": "..."} from API Gateway.
  private static func serverMessage(from data: Data?) -> String {
    guard let data = data, !data.isEmpty else { return "" }
    
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let message = (json["error"] as? String) ?? (json["message"] as? String) {
      print("   Server said: \(message)")
      return "\n\n\(message)"
    }
    
    let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return "" }
    print("   Server said: \(text)")
    return "\n\n\(String(text.prefix(200)))"
  }
  
  private func showError(_ message: String) {
    UINotificationFeedbackGenerator().notificationOccurred(.error)
    let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
  }
}

// MARK: - Table view
// ==================

extension TasksViewController: UITableViewDelegate, UITableViewDataSource {
  
  func numberOfSections(in tableView: UITableView) -> Int {
    return sections.count
  }
  
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return sections[section].tasks.count
  }
  
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: TaskCardCell.reuseID, for: indexPath)
    if let cardCell = cell as? TaskCardCell {
      cardCell.configure(with: task(at: indexPath))
    }
    return cell
  }
  
  // Big bold section headers ("Overdue", "Today", "Wednesday, Oct 14"...)
  func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
    let container = UIView()
    let label = UILabel()
    label.text = sections[section].title
    label.font = Theme.roundedFont(size: 20, weight: .bold)
    label.textColor = sections[section].color ?? .label
    label.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
      label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
      label.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
      label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
    ])
    return container
  }
  
  func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
    return UITableView.automaticDimension
  }
  
  func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
    return nil
  }
  
  func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
    return .leastNormalMagnitude
  }
  
  // Tap a task to edit it
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    editTask(task(at: indexPath))
  }
  
  // Swipe left on a task for Edit / Delete
  func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
    let task = self.task(at: indexPath)
    let taskId = task["taskId"] as? String ?? ""
    
    let deleteAction = UIContextualAction(style: .destructive, title: nil) { [weak self] _, _, completionHandler in
      guard let self = self, !taskId.isEmpty else {
        completionHandler(false)
        return
      }
      
      self.confirmDelete(task) { confirmed in
        guard confirmed else {
          completionHandler(false)
          return
        }
        
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        self.removeTaskFromList(taskId: taskId)
        completionHandler(true)
        self.deleteTask(taskId: taskId)
      }
    }
    deleteAction.image = UIImage(systemName: "trash.fill")
    
    let editAction = UIContextualAction(style: .normal, title: nil) { [weak self] _, _, completionHandler in
      completionHandler(true)
      self?.editTask(task)
    }
    editAction.image = UIImage(systemName: "pencil")
    editAction.backgroundColor = Theme.accent
    
    let configuration = UISwipeActionsConfiguration(actions: [deleteAction, editAction])
    configuration.performsFirstActionWithFullSwipe = false // avoid accidental deletes
    return configuration
  }
}

// MARK: - Task card cell
// ======================

final class TaskCardCell: UITableViewCell {
  
  static let reuseID = "TaskCardCell"
  
  private let cardView = UIView()
  private let accentBar = UIView()
  private let titleLabel = UILabel()
  private let descriptionLabel = UILabel()
  private let badgeStack = UIStackView()
  private let dueBadge = BadgeView()
  private let repeatBadge = BadgeView()
  private let importanceBadge = BadgeView()
  private let chevronView = UIImageView(image: UIImage(systemName: "chevron.right"))
  
  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    setupViews()
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  private func setupViews() {
    backgroundColor = .clear
    contentView.backgroundColor = .clear
    selectionStyle = .none
    
    // Card
    cardView.backgroundColor = .secondarySystemGroupedBackground
    cardView.layer.cornerRadius = 18
    cardView.layer.cornerCurve = .continuous
    cardView.layer.shadowColor = UIColor.black.cgColor
    cardView.layer.shadowOpacity = 0.06
    cardView.layer.shadowRadius = 10
    cardView.layer.shadowOffset = CGSize(width: 0, height: 3)
    
    // Colored strip on the left, matches the due-date color
    accentBar.layer.cornerRadius = 2
    
    titleLabel.font = Theme.roundedFont(size: 17, weight: .semibold)
    titleLabel.textColor = .label
    titleLabel.numberOfLines = 2
    
    descriptionLabel.font = .systemFont(ofSize: 15)
    descriptionLabel.textColor = .secondaryLabel
    descriptionLabel.numberOfLines = 2
    
    badgeStack.axis = .horizontal
    badgeStack.spacing = 6
    badgeStack.alignment = .center
    badgeStack.addArrangedSubview(importanceBadge)
    badgeStack.addArrangedSubview(dueBadge)
    badgeStack.addArrangedSubview(repeatBadge)
    
    chevronView.tintColor = .tertiaryLabel
    chevronView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
    chevronView.setContentHuggingPriority(.required, for: .horizontal)
    chevronView.setContentCompressionResistancePriority(.required, for: .horizontal)
    
    let textStack = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel, badgeStack])
    textStack.axis = .vertical
    textStack.alignment = .leading
    textStack.spacing = 4
    textStack.setCustomSpacing(10, after: descriptionLabel)
    
    contentView.addSubview(cardView)
    cardView.addSubview(accentBar)
    cardView.addSubview(textStack)
    cardView.addSubview(chevronView)
    
    for subview in [cardView, accentBar, textStack, chevronView] {
      subview.translatesAutoresizingMaskIntoConstraints = false
    }
    
    NSLayoutConstraint.activate([
      cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
      cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
      cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
      cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
      
      accentBar.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
      accentBar.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 14),
      accentBar.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -14),
      accentBar.widthAnchor.constraint(equalToConstant: 4),
      
      textStack.leadingAnchor.constraint(equalTo: accentBar.trailingAnchor, constant: 12),
      textStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 14),
      textStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -14),
      textStack.trailingAnchor.constraint(equalTo: chevronView.leadingAnchor, constant: -10),
      
      chevronView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
      chevronView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
    ])
  }
  
  // Little "press" animation when tapped
  override func setHighlighted(_ highlighted: Bool, animated: Bool) {
    super.setHighlighted(highlighted, animated: animated)
    UIView.animate(withDuration: 0.15) {
      self.cardView.transform = highlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
    }
  }
  
  func configure(with task: [String: Any]) {
    let name = task["name"] as? String ?? ""
    titleLabel.text = name.isEmpty ? "Untitled" : name
    
    let description = (task["description"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    descriptionLabel.text = description
    descriptionLabel.isHidden = description.isEmpty
    
    if let badge = TaskDates.badge(for: task) {
      dueBadge.configure(text: badge.text, symbol: badge.symbol, color: badge.color)
      dueBadge.isHidden = false
      accentBar.backgroundColor = badge.color
    } else {
      dueBadge.isHidden = true
      accentBar.backgroundColor = .systemGray4
    }
    
    if let recurrence = Recurrence(task: task) {
      repeatBadge.configure(text: recurrence.summary, symbol: "repeat", color: .secondaryLabel)
      repeatBadge.isHidden = false
    } else {
      repeatBadge.isHidden = true
    }
    
    let importance = TaskImportance(rawValue: task["importance"] as? String ?? "") ?? .none
    if importance == .none {
      importanceBadge.isHidden = true
    } else {
      importanceBadge.configure(text: importance.title, symbol: importance.symbol, color: importance.color)
      importanceBadge.isHidden = false
    }
    
    badgeStack.isHidden = dueBadge.isHidden && repeatBadge.isHidden && importanceBadge.isHidden
  }
}

// MARK: - Badge ("pill") view
// ===========================

final class BadgeView: UIView {
  
  private let iconView = UIImageView()
  private let label = UILabel()
  
  override init(frame: CGRect) {
    super.init(frame: frame)
    
    layer.cornerRadius = 9
    layer.cornerCurve = .continuous
    
    iconView.contentMode = .scaleAspectFit
    iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
    
    label.font = Theme.roundedFont(size: 13, weight: .semibold)
    
    let stack = UIStackView(arrangedSubviews: [iconView, label])
    stack.axis = .horizontal
    stack.spacing = 4
    stack.alignment = .center
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
    ])
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  func configure(text: String, symbol: String, color: UIColor) {
    label.text = text
    label.textColor = color
    iconView.image = UIImage(systemName: symbol)
    iconView.tintColor = color
    backgroundColor = color.withAlphaComponent(0.14)
  }
}
