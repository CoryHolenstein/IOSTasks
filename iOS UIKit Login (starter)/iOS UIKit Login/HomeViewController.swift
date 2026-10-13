//
// HomeViewController.swift
// iOS UIKit Login
//
// Settings page after user logs in.
//

import UIKit
import Auth0


class HomeViewController: UIViewController {
  
  private enum Row {
    case email
    case version
    case logOut
  }
  
  private struct SettingsSection {
    let title: String?
    let rows: [Row]
  }
  
  private let sections: [SettingsSection] = [
    SettingsSection(title: "Account", rows: [.email]),
    SettingsSection(title: "About", rows: [.version]),
    SettingsSection(title: nil, rows: [.logOut]),
  ]
  
  private let tableView = UITableView(frame: .zero, style: .insetGrouped)
  private let avatarImageView = UIImageView()
  private let nameLabel = UILabel()
  private let emailLabel = UILabel()
  
  var user: User?
  var credentials: Credentials?
  var onLogout: (() -> Void)?
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    setupUI()
    displayUserInfo()
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
  
  private func logOut() {
    Auth0
      .webAuth()
      .logout(federated: true) { result in
        switch result {
        case .failure(let error):
          print("Logout failed: \(error)")
          DispatchQueue.main.async {
            let alert = UIAlertController(
              title: "Logout Failed",
              message: error.localizedDescription,
              preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
          }
          
        case .success():
          print("Logged out successfully")
          DispatchQueue.main.async {
            self.onLogout?()
            self.dismiss(animated: true)
          }
        }
      }
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
  
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath)
    let row = sections[indexPath.section].rows[indexPath.row]
    
    var config = UIListContentConfiguration.valueCell()
    cell.selectionStyle = .none
    
    switch row {
    case .email:
      config.text = "Email"
      config.secondaryText = user?.email
      config.image = UIImage(systemName: "envelope.fill")
      config.imageProperties.tintColor = Theme.accent
      
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
    }
    
    cell.contentConfiguration = config
    return cell
  }
  
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    
    if sections[indexPath.section].rows[indexPath.row] == .logOut {
      confirmLogout()
    }
  }
}
