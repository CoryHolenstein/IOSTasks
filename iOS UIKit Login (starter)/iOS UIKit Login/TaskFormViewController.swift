//
// TaskFormViewController.swift
// iOS UIKit Login
//
// Full-screen form for creating and editing tasks,
// plus the "Repeat" picker it opens.
//

import UIKit

// MARK: - Task fields
// ===================

enum TaskImportance: String, CaseIterable {
  case none
  case low
  case medium
  case high
  
  var title: String {
    switch self {
    case .none: return "None"
    case .low: return "Low"
    case .medium: return "Medium"
    case .high: return "High"
    }
  }
  
  var color: UIColor {
    switch self {
    case .none: return .secondaryLabel
    case .low: return .systemBlue
    case .medium: return .systemOrange
    case .high: return .systemRed
    }
  }
  
  var symbol: String {
    switch self {
    case .none, .low: return "exclamationmark"
    case .medium: return "exclamationmark.2"
    case .high: return "exclamationmark.3"
    }
  }
}

/// How loud a task's notification is.
enum AlertStyle: String, CaseIterable {
  case quiet     // delivered silently to Notification Center
  case standard  // normal banner + sound
  case urgent    // "Time Sensitive": breaks through Focus modes
  
  var title: String {
    switch self {
    case .quiet: return "Quiet"
    case .standard: return "Standard"
    case .urgent: return "Urgent"
    }
  }
}

/// "Every <interval> <unit>", e.g. every 30 minutes, every 4 hours, every 1 year.
struct Recurrence: Equatable {
  
  enum Unit: String, CaseIterable {
    case minute
    case hour
    case day
    case week
    case month
    case year
    
    func name(for interval: Int) -> String {
      return interval == 1 ? rawValue : rawValue + "s"
    }
  }
  
  var interval: Int
  var unit: Unit
  
  static let presets: [Recurrence] = [
    Recurrence(interval: 30, unit: .minute),
    Recurrence(interval: 1, unit: .hour),
    Recurrence(interval: 4, unit: .hour),
    Recurrence(interval: 1, unit: .day),
    Recurrence(interval: 1, unit: .week),
    Recurrence(interval: 2, unit: .week),
    Recurrence(interval: 1, unit: .month),
    Recurrence(interval: 1, unit: .year),
  ]
  
  init(interval: Int, unit: Unit) {
    self.interval = max(1, interval)
    self.unit = unit
  }
  
  /// Reads a task from the backend: the new "recurrence" field first, then the old "repeat" string.
  init?(task: [String: Any]) {
    if let dict = task["recurrence"] as? [String: Any],
       let unitName = dict["unit"] as? String,
       let unit = Unit(rawValue: unitName) {
      let interval = (dict["interval"] as? Int) ?? Int(dict["interval"] as? String ?? "") ?? 1
      self.init(interval: interval, unit: unit)
      return
    }
    
    let raw = (task["repeat"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch raw {
    case "every minute": self.init(interval: 1, unit: .minute)
    case "hourly": self.init(interval: 1, unit: .hour)
    case "daily": self.init(interval: 1, unit: .day)
    case "weekly": self.init(interval: 1, unit: .week)
    case "monthly": self.init(interval: 1, unit: .month)
    case "yearly": self.init(interval: 1, unit: .year)
    default:
      // e.g. "every 4 hours"
      let words = raw.split(separator: " ").map { String($0) }
      guard words.count == 3, words[0] == "every", let interval = Int(words[1]) else { return nil }
      let unitWord = words[2].hasSuffix("s") ? String(words[2].dropLast()) : words[2]
      guard let unit = Unit(rawValue: unitWord) else { return nil }
      self.init(interval: interval, unit: unit)
    }
  }
  
  /// "Hourly", "Every 30 minutes", "Yearly"...
  var summary: String {
    if interval == 1 {
      switch unit {
      case .minute: return "Every minute"
      case .hour: return "Hourly"
      case .day: return "Daily"
      case .week: return "Weekly"
      case .month: return "Monthly"
      case .year: return "Yearly"
      }
    }
    return "Every \(interval) \(unit.name(for: interval))"
  }
  
  /// Value for the existing "repeat" field: "daily", "weekly", "every 4 hours"...
  var legacyRepeatString: String {
    return summary.lowercased()
  }
  
  var dictionary: [String: Any] {
    return ["interval": interval, "unit": unit.rawValue]
  }
}

/// Everything the form edits. Converted to/from the backend's JSON.
struct TaskDraft {
  var name = ""
  var notes = ""
  var dueDate: Date?            // the day, plus the time when hasTime is true
  var hasTime = false
  var importance: TaskImportance = .none
  var recurrence: Recurrence?
  var reminderMinutesBefore: Int?
  var alertStyle: AlertStyle = .standard
  
  init() {}
  
  init(task: [String: Any]) {
    name = task["name"] as? String ?? ""
    notes = task["description"] as? String ?? ""
    
    if let day = TaskDates.dueDate(of: task) {
      if let time = TaskDates.dueTime(of: task),
         let dayWithTime = Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) {
        dueDate = dayWithTime
        hasTime = true
      } else {
        dueDate = day
      }
    }
    
    importance = TaskImportance(rawValue: task["importance"] as? String ?? "") ?? .none
    recurrence = Recurrence(task: task)
    reminderMinutesBefore = task["reminderMinutesBefore"] as? Int
    alertStyle = AlertStyle(rawValue: task["alertStyle"] as? String ?? "") ?? .standard
  }
  
  /// The JSON body sent to the backend.
  ///
  /// Existing fields: userId, taskId, name, description, dueDate, repeat
  /// New fields:      dueTime ("HH:mm"), importance, recurrence {interval, unit},
  ///                  reminderMinutesBefore, alertStyle
  func payload(userId: String, taskId: String?) -> [String: Any] {
    var payload: [String: Any] = [
      "userId": userId,
      "name": name,
      "description": notes,
      "dueDate": dueDate.map { TaskDates.dateString($0) } ?? "",
      "dueTime": "",
      "importance": importance.rawValue,
      "repeat": recurrence?.legacyRepeatString ?? "never",
      "alertStyle": alertStyle.rawValue,
    ]
    
    if let taskId = taskId {
      payload["taskId"] = taskId
    }
    if let dueDate = dueDate, hasTime {
      payload["dueTime"] = TaskDates.timeString(dueDate)
    }
    if let recurrence = recurrence {
      payload["recurrence"] = recurrence.dictionary
    }
    if let minutes = reminderMinutesBefore {
      payload["reminderMinutesBefore"] = minutes
    }
    
    return payload
  }
}

// MARK: - Small helpers shared by the form screens
// ================================================

enum FormStyle {
  
  /// Settings-style icon: white symbol on a colored rounded square.
  static func icon(_ symbol: String, color: UIColor) -> UIImage {
    let size = CGSize(width: 30, height: 30)
    let renderer = UIGraphicsImageRenderer(size: size)
    let image = renderer.image { _ in
      color.setFill()
      UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8).fill()
      
      let configuration = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
      if let glyph = UIImage(systemName: symbol, withConfiguration: configuration)?
          .withTintColor(.white, renderingMode: .alwaysOriginal) {
        let origin = CGPoint(x: (size.width - glyph.size.width) / 2, y: (size.height - glyph.size.height) / 2)
        glyph.draw(at: origin)
      }
    }
    return image.withRenderingMode(.alwaysOriginal)
  }
  
  /// Pins a view to the cell's margins.
  static func embed(_ subview: UIView, in cell: UITableViewCell, minHeight: CGFloat = 0) {
    subview.translatesAutoresizingMaskIntoConstraints = false
    cell.contentView.addSubview(subview)
    
    let margins = cell.contentView.layoutMarginsGuide
    let bottom = subview.bottomAnchor.constraint(equalTo: margins.bottomAnchor)
    bottom.priority = UILayoutPriority(999) // avoids layout warnings while the cell sizes itself
    
    var constraints = [
      subview.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
      subview.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
      subview.topAnchor.constraint(equalTo: margins.topAnchor),
      bottom,
    ]
    if minHeight > 0 {
      constraints.append(subview.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight))
    }
    NSLayoutConstraint.activate(constraints)
  }
}

// MARK: - Task form
// =================

final class TaskFormViewController: UIViewController {
  
  private enum Section: Int, CaseIterable {
    case details
    case schedule
    case importance
    case notifications
  }
  
  private enum Row: Hashable {
    case name
    case notes
    case dateToggle
    case datePicker
    case timeToggle
    case timePicker
    case repeatRule
    case importance
    case reminder
    case alertStyle
  }
  
  private static let reminderOptions: [(minutes: Int?, title: String)] = [
    (nil, "None"),
    (0, "At time of task"),
    (5, "5 minutes before"),
    (15, "15 minutes before"),
    (30, "30 minutes before"),
    (60, "1 hour before"),
    (1440, "1 day before"),
  ]
  
  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
    return formatter
  }()
  
  private static let dayWithYearFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("EEEMMMdy")
    return formatter
  }()
  
  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter
  }()
  
  /// Called with the finished task when the user taps Add / Save.
  var onSave: ((TaskDraft) -> Void)?
  
  private var draft: TaskDraft
  private let editingExistingTask: Bool
  
  private var hasChanges = false {
    didSet {
      // Stop an accidental swipe-down from throwing away edits.
      isModalInPresentation = hasChanges
      navigationController?.isModalInPresentation = hasChanges
    }
  }
  
  private let tableView = UITableView(frame: .zero, style: .insetGrouped)
  private var cells: [Row: UITableViewCell] = [:]
  
  private let nameField = UITextField()
  private let notesView = UITextView()
  private let notesPlaceholder = UILabel()
  private let dateSwitch = UISwitch()
  private let timeSwitch = UISwitch()
  private let datePicker = UIDatePicker()
  private let timePicker = UIDatePicker()
  private let importanceControl = UISegmentedControl(items: TaskImportance.allCases.map { $0.title })
  private let alertStyleControl = UISegmentedControl(items: AlertStyle.allCases.map { $0.title })
  private let reminderButton = UIButton(type: .system)
  
  init(draft: TaskDraft, editingExistingTask: Bool) {
    self.draft = draft
    self.editingExistingTask = editingExistingTask
    super.init(nibName: nil, bundle: nil)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    title = editingExistingTask ? "Edit Task" : "New Task"
    view.backgroundColor = .systemGroupedBackground
    navigationItem.largeTitleDisplayMode = .never
    
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .cancel,
      target: self,
      action: #selector(cancelTapped)
    )
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: editingExistingTask ? "Save" : "Add",
      style: .done,
      target: self,
      action: #selector(saveTapped)
    )
    
    setupControls()
    setupTableView()
    updateSaveButton()
  }
  
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.presentationController?.delegate = self
  }
  
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if !editingExistingTask && draft.name.isEmpty {
      nameField.becomeFirstResponder()
    }
  }
  
  // MARK: Setup
  // ===========
  
  private func setupControls() {
    // Name
    nameField.text = draft.name
    nameField.placeholder = "Task name"
    nameField.font = Theme.roundedFont(size: 20, weight: .semibold)
    nameField.autocapitalizationType = .sentences
    nameField.returnKeyType = .next
    nameField.clearButtonMode = .whileEditing
    nameField.delegate = self
    nameField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)
    
    // Description
    notesView.text = draft.notes
    notesView.font = .systemFont(ofSize: 17)
    notesView.textColor = .label
    notesView.backgroundColor = .clear
    notesView.isScrollEnabled = false
    notesView.textContainerInset = .zero
    notesView.textContainer.lineFragmentPadding = 0
    notesView.delegate = self
    
    notesPlaceholder.text = "Description"
    notesPlaceholder.font = .systemFont(ofSize: 17)
    notesPlaceholder.textColor = .placeholderText
    notesPlaceholder.isHidden = !draft.notes.isEmpty
    
    // Date & time
    dateSwitch.isOn = draft.dueDate != nil
    dateSwitch.onTintColor = Theme.accent
    dateSwitch.addTarget(self, action: #selector(dateSwitchChanged), for: .valueChanged)
    
    timeSwitch.isOn = draft.hasTime
    timeSwitch.onTintColor = Theme.accent
    timeSwitch.addTarget(self, action: #selector(timeSwitchChanged), for: .valueChanged)
    
    datePicker.datePickerMode = .date
    datePicker.preferredDatePickerStyle = .inline
    datePicker.tintColor = Theme.accent
    datePicker.date = draft.dueDate ?? Date()
    datePicker.addTarget(self, action: #selector(datePickerChanged), for: .valueChanged)
    
    timePicker.datePickerMode = .time
    timePicker.preferredDatePickerStyle = .compact
    timePicker.tintColor = Theme.accent
    timePicker.date = draft.hasTime ? (draft.dueDate ?? nextWholeHour()) : nextWholeHour()
    timePicker.addTarget(self, action: #selector(datePickerChanged), for: .valueChanged)
    
    // Importance
    importanceControl.selectedSegmentIndex = TaskImportance.allCases.firstIndex(of: draft.importance) ?? 0
    importanceControl.addTarget(self, action: #selector(importanceChanged), for: .valueChanged)
    updateSegmentTints()
    
    // Notification style
    alertStyleControl.selectedSegmentIndex = AlertStyle.allCases.firstIndex(of: draft.alertStyle) ?? 1
    alertStyleControl.addTarget(self, action: #selector(alertStyleChanged), for: .valueChanged)
    
    // "Remind me" pop-up menu
    var configuration = UIButton.Configuration.plain()
    configuration.image = UIImage(systemName: "chevron.up.chevron.down")
    configuration.imagePlacement = .trailing
    configuration.imagePadding = 4
    configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0)
    reminderButton.configuration = configuration
    reminderButton.showsMenuAsPrimaryAction = true
    reminderButton.tintColor = Theme.accent
    updateReminderButton()
  }
  
  private func setupTableView() {
    tableView.dataSource = self
    tableView.delegate = self
    tableView.backgroundColor = .systemGroupedBackground
    tableView.keyboardDismissMode = .interactive
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 52
    
    view.addSubview(tableView)
    tableView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      tableView.topAnchor.constraint(equalTo: view.topAnchor),
      tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
  }
  
  private func nextWholeHour() -> Date {
    let calendar = Calendar.current
    let inAnHour = calendar.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    let hour = calendar.component(.hour, from: inAnHour)
    return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: inAnHour) ?? inAnHour
  }
  
  // MARK: Rows
  // ==========
  
  private func rows(in section: Section) -> [Row] {
    switch section {
    case .details:
      return [.name, .notes]
      
    case .schedule:
      var rows: [Row] = [.dateToggle]
      if draft.dueDate != nil {
        rows.append(.datePicker)
        rows.append(.timeToggle)
        if draft.hasTime {
          rows.append(.timePicker)
        }
      }
      rows.append(.repeatRule)
      return rows
      
    case .importance:
      return [.importance]
      
    case .notifications:
      return [.reminder, .alertStyle]
    }
  }
  
  private func row(at indexPath: IndexPath) -> Row? {
    guard let section = Section(rawValue: indexPath.section) else { return nil }
    let sectionRows = rows(in: section)
    guard indexPath.row < sectionRows.count else { return nil }
    return sectionRows[indexPath.row]
  }
  
  /// Runs `change`, then animates the date/time rows in or out.
  private func updateScheduleRows(_ change: () -> Void) {
    let section = Section.schedule.rawValue
    let oldRows = rows(in: .schedule)
    change()
    let newRows = rows(in: .schedule)
    
    let deletions = oldRows.enumerated()
      .filter { !newRows.contains($0.element) }
      .map { IndexPath(row: $0.offset, section: section) }
    let insertions = newRows.enumerated()
      .filter { !oldRows.contains($0.element) }
      .map { IndexPath(row: $0.offset, section: section) }
    
    tableView.performBatchUpdates({
      self.tableView.deleteRows(at: deletions, with: .fade)
      self.tableView.insertRows(at: insertions, with: .fade)
    })
  }
  
  /// Cells are built once and kept, so text fields and pickers keep their state.
  private func cell(for row: Row) -> UITableViewCell {
    if let existing = cells[row] {
      return existing
    }
    let newCell = makeCell(for: row)
    cells[row] = newCell
    return newCell
  }
  
  private func makeCell(for row: Row) -> UITableViewCell {
    let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
    cell.selectionStyle = .none
    
    switch row {
    case .name:
      FormStyle.embed(nameField, in: cell, minHeight: 34)
      
    case .notes:
      FormStyle.embed(notesView, in: cell, minHeight: 66)
      notesPlaceholder.translatesAutoresizingMaskIntoConstraints = false
      cell.contentView.addSubview(notesPlaceholder)
      NSLayoutConstraint.activate([
        notesPlaceholder.leadingAnchor.constraint(equalTo: notesView.leadingAnchor),
        notesPlaceholder.topAnchor.constraint(equalTo: notesView.topAnchor),
      ])
      
    case .dateToggle:
      cell.accessoryView = dateSwitch
      configureToggleCell(cell, row: .dateToggle)
      
    case .datePicker:
      FormStyle.embed(datePicker, in: cell)
      
    case .timeToggle:
      cell.accessoryView = timeSwitch
      configureToggleCell(cell, row: .timeToggle)
      
    case .timePicker:
      let label = UILabel()
      label.text = "Due at"
      label.font = .systemFont(ofSize: 17)
      label.textColor = .secondaryLabel
      
      let stack = UIStackView(arrangedSubviews: [label, UIView(), timePicker])
      stack.axis = .horizontal
      stack.alignment = .center
      FormStyle.embed(stack, in: cell, minHeight: 36)
      
    case .repeatRule:
      cell.selectionStyle = .default
      cell.accessoryType = .disclosureIndicator
      configureRepeatCell(cell)
      
    case .importance:
      FormStyle.embed(importanceControl, in: cell, minHeight: 32)
      
    case .reminder:
      var configuration = cell.defaultContentConfiguration()
      configuration.text = "Remind me"
      configuration.image = FormStyle.icon("bell.fill", color: .systemOrange)
      cell.contentConfiguration = configuration
      cell.accessoryView = reminderButton
      
    case .alertStyle:
      FormStyle.embed(alertStyleControl, in: cell, minHeight: 32)
    }
    
    return cell
  }
  
  private func configureToggleCell(_ cell: UITableViewCell, row: Row) {
    var configuration = UIListContentConfiguration.subtitleCell()
    configuration.secondaryTextProperties.color = Theme.accent
    configuration.secondaryTextProperties.font = .systemFont(ofSize: 14, weight: .medium)
    configuration.textToSecondaryTextVerticalPadding = 2
    
    switch row {
    case .dateToggle:
      configuration.text = "Date"
      configuration.image = FormStyle.icon("calendar", color: .systemRed)
      configuration.secondaryText = draft.dueDate.map { dayText(for: $0) }
      
    case .timeToggle:
      configuration.text = "Time"
      configuration.image = FormStyle.icon("clock.fill", color: .systemBlue)
      if let dueDate = draft.dueDate, draft.hasTime {
        configuration.secondaryText = Self.timeFormatter.string(from: dueDate)
      }
      
    default:
      break
    }
    
    cell.contentConfiguration = configuration
  }
  
  private func configureRepeatCell(_ cell: UITableViewCell) {
    var configuration = UIListContentConfiguration.valueCell()
    configuration.text = "Repeat"
    configuration.secondaryText = draft.recurrence?.summary ?? "Never"
    configuration.image = FormStyle.icon("repeat", color: .systemGreen)
    cell.contentConfiguration = configuration
  }
  
  private func refreshScheduleLabels() {
    if let dateCell = cells[.dateToggle] {
      configureToggleCell(dateCell, row: .dateToggle)
    }
    if let timeCell = cells[.timeToggle] {
      configureToggleCell(timeCell, row: .timeToggle)
    }
    if let repeatCell = cells[.repeatRule] {
      configureRepeatCell(repeatCell)
    }
  }
  
  private func dayText(for date: Date) -> String {
    switch TaskDates.daysFromToday(date) {
    case 0: return "Today"
    case 1: return "Tomorrow"
    case -1: return "Yesterday"
    default:
      let sameYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
      return sameYear ? Self.dayFormatter.string(from: date) : Self.dayWithYearFormatter.string(from: date)
    }
  }
  
  // MARK: Keeping the draft in sync
  // ===============================
  
  /// Combines the date picker's day with the time picker's time.
  private func syncDueDateFromPickers() {
    guard dateSwitch.isOn else {
      draft.dueDate = nil
      draft.hasTime = false
      return
    }
    
    let calendar = Calendar.current
    let day = calendar.startOfDay(for: datePicker.date)
    
    if timeSwitch.isOn {
      let time = calendar.dateComponents([.hour, .minute], from: timePicker.date)
      draft.dueDate = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: day) ?? day
      draft.hasTime = true
    } else {
      draft.dueDate = day
      draft.hasTime = false
    }
  }
  
  private func updateSaveButton() {
    let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    navigationItem.rightBarButtonItem?.isEnabled = !name.isEmpty
  }
  
  private func updateSegmentTints() {
    let importance = TaskImportance.allCases[max(0, importanceControl.selectedSegmentIndex)]
    if importance == .none {
      importanceControl.selectedSegmentTintColor = nil
      importanceControl.setTitleTextAttributes([.foregroundColor: UIColor.label], for: .selected)
    } else {
      importanceControl.selectedSegmentTintColor = importance.color
      importanceControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
    }
  }
  
  private func updateReminderButton() {
    let current = draft.reminderMinutesBefore
    
    let actions = Self.reminderOptions.map { option in
      UIAction(title: option.title, state: option.minutes == current ? .on : .off) { [weak self] _ in
        guard let self = self else { return }
        self.draft.reminderMinutesBefore = option.minutes
        self.hasChanges = true
        self.updateReminderButton()
      }
    }
    reminderButton.menu = UIMenu(children: actions)
    
    let title = Self.reminderOptions.first(where: { $0.minutes == current })?.title
      ?? current.map { "\($0) min before" }
      ?? "None"
    reminderButton.configuration?.title = title
    reminderButton.sizeToFit()
    cells[.reminder]?.setNeedsLayout()
  }
  
  // MARK: Actions
  // =============
  
  @objc private func nameChanged() {
    draft.name = nameField.text ?? ""
    hasChanges = true
    updateSaveButton()
  }
  
  @objc private func dateSwitchChanged() {
    hasChanges = true
    updateScheduleRows {
      self.syncDueDateFromPickers()
    }
    refreshScheduleLabels()
  }
  
  @objc private func timeSwitchChanged() {
    hasChanges = true
    updateScheduleRows {
      self.syncDueDateFromPickers()
    }
    
    // Like Reminders: picking a time turns on a reminder at that time.
    if draft.hasTime && draft.reminderMinutesBefore == nil {
      draft.reminderMinutesBefore = 0
      updateReminderButton()
    }
    refreshScheduleLabels()
  }
  
  @objc private func datePickerChanged() {
    hasChanges = true
    syncDueDateFromPickers()
    refreshScheduleLabels()
  }
  
  @objc private func importanceChanged() {
    hasChanges = true
    draft.importance = TaskImportance.allCases[max(0, importanceControl.selectedSegmentIndex)]
    updateSegmentTints()
    UISelectionFeedbackGenerator().selectionChanged()
  }
  
  @objc private func alertStyleChanged() {
    hasChanges = true
    draft.alertStyle = AlertStyle.allCases[max(0, alertStyleControl.selectedSegmentIndex)]
    UISelectionFeedbackGenerator().selectionChanged()
  }
  
  private func showRepeatPicker() {
    view.endEditing(true)
    let picker = RecurrenceViewController(selection: draft.recurrence)
    picker.onChange = { [weak self] recurrence in
      guard let self = self else { return }
      self.draft.recurrence = recurrence
      self.hasChanges = true
      self.refreshScheduleLabels()
    }
    navigationController?.pushViewController(picker, animated: true)
  }
  
  @objc private func saveTapped() {
    view.endEditing(true)
    
    var finished = draft
    finished.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    finished.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !finished.name.isEmpty else { return }
    
    onSave?(finished)
    dismiss(animated: true)
  }
  
  @objc private func cancelTapped() {
    if hasChanges {
      confirmDiscard()
    } else {
      dismiss(animated: true)
    }
  }
  
  private func confirmDiscard() {
    view.endEditing(true)
    
    let alert = UIAlertController(
      title: "Discard Changes?",
      message: "Your changes to this task won’t be saved.",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "Keep Editing", style: .cancel))
    alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { _ in
      self.dismiss(animated: true)
    })
    present(alert, animated: true)
  }
}

// MARK: Table view

extension TaskFormViewController: UITableViewDataSource, UITableViewDelegate {
  
  func numberOfSections(in tableView: UITableView) -> Int {
    return Section.allCases.count
  }
  
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    guard let section = Section(rawValue: section) else { return 0 }
    return rows(in: section).count
  }
  
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    guard let row = self.row(at: indexPath) else { return UITableViewCell() }
    return self.cell(for: row)
  }
  
  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    switch Section(rawValue: section) {
    case .schedule: return "Schedule"
    case .importance: return "Importance"
    case .notifications: return "Notifications"
    default: return nil
    }
  }
  
  func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    switch Section(rawValue: section) {
    case .notifications:
      return "Quiet reminders arrive silently in Notification Center. Urgent reminders break through Focus modes. Whether banners stay on screen is set for each app in the iOS Settings app."
    default:
      return nil
    }
  }
  
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    
    switch row(at: indexPath) {
    case .name:
      nameField.becomeFirstResponder()
    case .notes:
      notesView.becomeFirstResponder()
    case .repeatRule:
      showRepeatPicker()
    default:
      break
    }
  }
}

// MARK: Text input

extension TaskFormViewController: UITextFieldDelegate, UITextViewDelegate {
  
  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    notesView.becomeFirstResponder()
    return false
  }
  
  func textViewDidChange(_ textView: UITextView) {
    draft.notes = textView.text
    notesPlaceholder.isHidden = !textView.text.isEmpty
    hasChanges = true
    
    // Let the description cell grow as you type.
    UIView.performWithoutAnimation {
      self.tableView.performBatchUpdates(nil)
    }
  }
}

// MARK: Swipe-to-dismiss protection

extension TaskFormViewController: UIAdaptivePresentationControllerDelegate {
  
  func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
    confirmDiscard()
  }
}

// MARK: - Repeat picker
// =====================

final class RecurrenceViewController: UITableViewController {
  
  var onChange: ((Recurrence?) -> Void)?
  
  private var selection: Recurrence?
  private var customInterval: Int
  private var customUnit: Recurrence.Unit
  private var showsCustomPicker: Bool
  
  private static let maxInterval = 99
  private let picker = UIPickerView()
  
  private lazy var pickerCell: UITableViewCell = {
    let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
    cell.selectionStyle = .none
    FormStyle.embed(self.picker, in: cell, minHeight: 180)
    return cell
  }()
  
  init(selection: Recurrence?) {
    self.selection = selection
    customInterval = selection?.interval ?? 2
    customUnit = selection?.unit ?? .hour
    if let selection = selection {
      showsCustomPicker = !Recurrence.presets.contains(selection)
    } else {
      showsCustomPicker = false
    }
    super.init(style: .insetGrouped)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    title = "Repeat"
    navigationItem.largeTitleDisplayMode = .never
    tableView.tintColor = Theme.accent
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "RepeatCell")
    
    picker.dataSource = self
    picker.delegate = self
    picker.selectRow(min(customInterval, Self.maxInterval) - 1, inComponent: 0, animated: false)
    picker.selectRow(Recurrence.Unit.allCases.firstIndex(of: customUnit) ?? 0, inComponent: 1, animated: false)
  }
  
  private var customRecurrence: Recurrence {
    return Recurrence(interval: customInterval, unit: customUnit)
  }
  
  private var isCustomSelected: Bool {
    guard let selection = selection else { return false }
    return showsCustomPicker || !Recurrence.presets.contains(selection)
  }
  
  private func select(_ recurrence: Recurrence?) {
    selection = recurrence
    onChange?(recurrence)
    UISelectionFeedbackGenerator().selectionChanged()
  }
  
  private func refreshCheckmarks() {
    UIView.performWithoutAnimation {
      self.tableView.reloadSections(IndexSet(integer: 0), with: .none)
      self.tableView.reloadRows(at: [IndexPath(row: 0, section: 1)], with: .none)
    }
  }
  
  // MARK: Table view
  
  override func numberOfSections(in tableView: UITableView) -> Int {
    return 2
  }
  
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    if section == 0 {
      return Recurrence.presets.count + 1 // "Never" + presets
    }
    return showsCustomPicker ? 2 : 1
  }
  
  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    return section == 0 ? nil : "Custom"
  }
  
  override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    return section == 0 ? nil : "For anything else, like every 3 days or every 45 minutes."
  }
  
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    if indexPath.section == 1 && indexPath.row == 1 {
      return pickerCell
    }
    
    let cell = tableView.dequeueReusableCell(withIdentifier: "RepeatCell", for: indexPath)
    var configuration = UIListContentConfiguration.valueCell()
    
    if indexPath.section == 0 {
      if indexPath.row == 0 {
        configuration.text = "Never"
        cell.accessoryType = selection == nil ? .checkmark : .none
      } else {
        let preset = Recurrence.presets[indexPath.row - 1]
        configuration.text = preset.summary
        cell.accessoryType = (!showsCustomPicker && selection == preset) ? .checkmark : .none
      }
    } else {
      configuration.text = "Custom"
      configuration.secondaryText = customRecurrence.summary
      cell.accessoryType = isCustomSelected ? .checkmark : .none
    }
    
    cell.contentConfiguration = configuration
    return cell
  }
  
  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    
    if indexPath.section == 0 {
      let recurrence: Recurrence? = indexPath.row == 0 ? nil : Recurrence.presets[indexPath.row - 1]
      if showsCustomPicker {
        showsCustomPicker = false
        tableView.deleteRows(at: [IndexPath(row: 1, section: 1)], with: .fade)
      }
      select(recurrence)
      refreshCheckmarks()
      navigationController?.popViewController(animated: true)
      
    } else if indexPath.row == 0 {
      // Tap "Custom" to show or hide the wheel
      showsCustomPicker.toggle()
      if showsCustomPicker {
        tableView.insertRows(at: [IndexPath(row: 1, section: 1)], with: .fade)
        select(customRecurrence)
      } else {
        tableView.deleteRows(at: [IndexPath(row: 1, section: 1)], with: .fade)
      }
      refreshCheckmarks()
    }
  }
}

extension RecurrenceViewController: UIPickerViewDataSource, UIPickerViewDelegate {
  
  func numberOfComponents(in pickerView: UIPickerView) -> Int {
    return 2
  }
  
  func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
    return component == 0 ? Self.maxInterval : Recurrence.Unit.allCases.count
  }
  
  func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
    if component == 0 {
      return "\(row + 1)"
    }
    return Recurrence.Unit.allCases[row].name(for: customInterval)
  }
  
  func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
    if component == 0 {
      customInterval = row + 1
      pickerView.reloadComponent(1) // "hour" vs "hours"
    } else {
      customUnit = Recurrence.Unit.allCases[row]
    }
    select(customRecurrence)
    refreshCheckmarks()
  }
}
