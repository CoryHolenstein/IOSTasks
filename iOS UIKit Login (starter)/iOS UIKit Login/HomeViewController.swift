//
// HomeViewController.swift
// iOS UIKit Login
//
// Settings page after user logs in.
//

import UIKit
import Auth0
import UserNotifications


class HomeViewController: UIViewController {
  
  private enum Row {
    case email
    case notifications
    case version
    case logOut
    case deleteAccount
  }
  
  private struct SettingsSection {
    let title: String?
    let rows: [Row]
    var footer: String? = nil
  }
  
  private let sections: [SettingsSection] = [
    SettingsSection(title: "Account", rows: [.email]),
    SettingsSection(title: "Notifications", rows: [.notifications]),
    SettingsSection(title: "About", rows: [.version]),
    SettingsSection(title: nil, rows: [.logOut]),
    SettingsSection(
      title: nil,
      rows: [.deleteAccount],
      footer: "Permanently deletes your account, all of your tasks and their reminders."
    ),
  ]
  
  private let tableView = UITableView(frame: .zero, style: .insetGrouped)
  private lazy var busyOverlay = makeBusyOverlay()
  private let avatarImageView = UIImageView()
  private let nameLabel = UILabel()
  private let emailLabel = UILabel()
  
  var user: User?
  var credentials: Credentials?
  var onLogout: (() -> Void)?
  
  private var notificationStatus: UNAuthorizationStatus?
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    setupUI()
    displayUserInfo()
    
    // Coming back from the iOS Settings app may have changed the permission
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(refreshNotificationStatus),
      name: UIApplication.willEnterForegroundNotification,
      object: nil
    )
  }
  
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    refreshNotificationStatus()
  }
  
  @objc private func refreshNotificationStatus() {
    TaskNotifications.shared.authorizationStatus { [weak self] status in
      guard let self = self else { return }
      self.notificationStatus = status
      self.tableView.reloadData()
    }
  }
  
  private var notificationStatusText: String {
    switch notificationStatus {
    case .authorized, .provisional, .ephemeral: return "On"
    case .denied: return "Off"
    case .notDetermined: return "Turn On"
    default: return ""
    }
  }
  
  private func notificationsRowTapped() {
    if notificationStatus == .notDetermined {
      TaskNotifications.shared.requestPermission { [weak self] _ in
        self?.refreshNotificationStatus()
      }
    } else if let url = URL(string: UIApplication.openSettingsURLString) {
      // Permission can only be changed in the iOS Settings app
      UIApplication.shared.open(url)
    }
  }
  
  private func setupUI() {
    title = "Settings"
    view.backgroundColor = .systemGroupedBackground
    
    tableView.delegate = self
    tableView.dataSource = self
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SettingsCell")
    tableView.backgroundColor = .systemGroupedBackground
    tableView.tableHeaderView = makeProfileHeader()
    
    view.addSubview(tableView)
    tableView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      tableView.topAnchor.constraint(equalTo: view.topAnchor),
      tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
  }
  
  /// Big profile picture with an accent ring, name and email.
  private func makeProfileHeader() -> UIView {
    let header = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 200))
    
    avatarImageView.contentMode = .scaleAspectFill
    avatarImageView.clipsToBounds = true
    avatarImageView.layer.cornerRadius = 48
    avatarImageView.layer.borderWidth = 3
    avatarImageView.layer.borderColor = Theme.accent.cgColor
    avatarImageView.backgroundColor = .tertiarySystemFill
    avatarImageView.tintColor = .secondaryLabel
    
    nameLabel.font = Theme.roundedFont(size: 24, weight: .bold)
    nameLabel.textColor = .label
    nameLabel.textAlignment = .center
    nameLabel.adjustsFontSizeToFitWidth = true
    nameLabel.minimumScaleFactor = 0.7
    
    emailLabel.font = .systemFont(ofSize: 15)
    emailLabel.textColor = .secondaryLabel
    emailLabel.textAlignment = .center
    
    let stack = UIStackView(arrangedSubviews: [avatarImageView, nameLabel, emailLabel])
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 4
    stack.setCustomSpacing(14, after: avatarImageView)
    stack.translatesAutoresizingMaskIntoConstraints = false
    header.addSubview(stack)
    
    NSLayoutConstraint.activate([
      avatarImageView.widthAnchor.constraint(equalToConstant: 96),
      avatarImageView.heightAnchor.constraint(equalToConstant: 96),
      
      stack.centerXAnchor.constraint(equalTo: header.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: header.leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -20),
    ])
    
    return header
  }
  
  private func displayUserInfo() {
    guard let user = user else { return }
    
    nameLabel.text = user.name
    emailLabel.text = user.email
    
    if !user.picture.isEmpty, let url = URL(string: user.picture) {
      avatarImageView.contentMode = .scaleAspectFill
      avatarImageView.load(url: url)
    } else {
      // No profile picture: show a person symbol instead
      avatarImageView.contentMode = .center
      avatarImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 40, weight: .medium)
      avatarImageView.image = UIImage(systemName: "person.fill")
    }
  }
  
  private var appVersion: String {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    return "\(version) (\(build))"
  }
  
  // MARK: Delete account
  // ====================
  
  private func confirmDeleteAccount() {
    let alert = UIAlertController(
      title: "Delete Account?",
      message: "This permanently deletes your account and all of your tasks and reminders. This can’t be undone.",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert.addAction(UIAlertAction(title: "Delete Account", style: .destructive) { _ in
      self.deleteAccount()
    })
    present(alert, animated: true)
  }
  
  private func deleteAccount() {
    setBusy(true)
    
    // Use a fresh access token (renewed if it has expired)
    LoginSession.shared.credentials { [weak self] fresh in
      guard let self = self else { return }
      guard let credentials = fresh ?? self.credentials else {
        self.setBusy(false)
        return
      }
      self.credentials = credentials
      self.sendDeleteAccount(using: credentials)
    }
  }
  
  private func sendDeleteAccount(using credentials: Credentials) {
    guard let url = URL(string: "\(TasksViewController.apiBaseURL)/delete-account") else {
      setBusy(false)
      return
    }
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data("{}".utf8) // the server deletes whoever is signed in
    request.timeoutInterval = 30
    
    URLSession.shared.dataTask(with: request) { data, response, error in
      DispatchQueue.main.async {
        self.setBusy(false)
        
        if let error = error {
          self.showMessage(title: "Couldn’t Delete Account", message: error.localizedDescription)
          return
        }
        
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
          let detail = TasksViewController.serverMessage(from: data)
          self.showMessage(title: "Couldn’t Delete Account", message: "Something went wrong (Status: \(status)).\(detail)")
          return
        }
        
        print("✅ Account deleted")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        TaskNotifications.shared.removeAll()
        
        let done = UIAlertController(
          title: "Account Deleted",
          message: "Your account and all of your tasks have been deleted.",
          preferredStyle: .alert
        )
        done.addAction(UIAlertAction(title: "OK", style: .default) { _ in
          self.signOutAfterDeletion()
        })
        self.present(done, animated: true)
      }
    }.resume()
  }
  
  /// The account no longer exists, so just return to the login screen.
  private func signOutAfterDeletion() {
    logOut()
  }
  
  private func showMessage(title: String, message: String) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
  }
  
  /// Dims the screen with a spinner while the account is being deleted.
  private func setBusy(_ busy: Bool) {
    let host: UIView = tabBarController?.view ?? view
    if busy {
      busyOverlay.frame = host.bounds
      host.addSubview(busyOverlay)
    } else {
      busyOverlay.removeFromSuperview()
    }
  }
  
  private func makeBusyOverlay() -> UIView {
    let overlay = UIView()
    overlay.backgroundColor = UIColor.black.withAlphaComponent(0.35)
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    
    let spinner = UIActivityIndicatorView(style: .large)
    spinner.color = .white
    spinner.startAnimating()
    
    let label = UILabel()
    label.text = "Deleting account…"
    label.font = Theme.roundedFont(size: 17, weight: .semibold)
    label.textColor = .white
    
    let stack = UIStackView(arrangedSubviews: [spinner, label])
    stack.axis = .vertical
    stack.spacing = 12
    stack.alignment = .center
    stack.translatesAutoresizingMaskIntoConstraints = false
    overlay.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
    ])
    return overlay
  }
  
  // MARK: Log out
  // =============
  
  private func confirmLogout() {
    let alert = UIAlertController(
      title: "Log Out?",
      message: "You’ll need to log in again to see your tasks.",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert.addAction(UIAlertAction(title: "Log Out", style: .destructive) { _ in
      self.logOut()
    })
    present(alert, animated: true)
  }
  
  /// Logins use a private browser session that saves no cookies, so logging
  /// out only needs to forget the user on this phone. No browser pop-up needed.
  private func logOut() {
    print("Logged out")
    onLogout?()
    dismiss(animated: true)
  }
}

// MARK: - Table view
// ==================

extension HomeViewController: UITableViewDelegate, UITableViewDataSource {
  
  func numberOfSections(in tableView: UITableView) -> Int {
    return sections.count
  }
  
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return sections[section].rows.count
  }
  
  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    return sections[section].title
  }
  
  func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    return sections[section].footer
  }
  
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath)
    let row = sections[indexPath.section].rows[indexPath.row]
    
    var config = UIListContentConfiguration.valueCell()
    cell.selectionStyle = .none
    cell.accessoryType = .none
    
    switch row {
    case .email:
      config.text = "Email"
      config.secondaryText = user?.email
      config.image = UIImage(systemName: "envelope.fill")
      config.imageProperties.tintColor = Theme.accent
      
    case .notifications:
      config.text = "Reminders"
      config.secondaryText = notificationStatusText
      config.image = UIImage(systemName: "bell.badge.fill")
      config.imageProperties.tintColor = Theme.accent
      cell.accessoryType = .disclosureIndicator
      cell.selectionStyle = .default
      
    case .version:
      config.text = "Version"
      config.secondaryText = appVersion
      config.image = UIImage(systemName: "info.circle.fill")
      config.imageProperties.tintColor = Theme.accent
      
    case .logOut:
      config = UIListContentConfiguration.cell()
      config.text = "Log Out"
      config.textProperties.color = .systemRed
      config.textProperties.font = .systemFont(ofSize: 17, weight: .semibold)
      config.textProperties.alignment = .center
      cell.selectionStyle = .default
      
    case .deleteAccount:
      config = UIListContentConfiguration.cell()
      config.text = "Delete Account"
      config.textProperties.color = .systemRed
      config.textProperties.alignment = .center
      cell.selectionStyle = .default
    }
    
    cell.contentConfiguration = config
    return cell
  }
  
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    
    switch sections[indexPath.section].rows[indexPath.row] {
    case .logOut:
      confirmLogout()
    case .notifications:
      notificationsRowTapped()
    case .deleteAccount:
      confirmDeleteAccount()
    default:
      break
    }
  }
}
