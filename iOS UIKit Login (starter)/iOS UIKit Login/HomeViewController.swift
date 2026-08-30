//
// HomeViewController.swift
// iOS UIKit Login
//
// Settings page after user logs in.
//

import UIKit
import Auth0


class HomeViewController: UIViewController {
  
  private let userPictureImageView = UIImageView()
  private let userNameLabel = UILabel()
  private let userEmailLabel = UILabel()
  private let logoutButton = UIButton(type: .system)
  
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
    view.backgroundColor = .systemBackground
    
    // User picture
    userPictureImageView.contentMode = .scaleAspectFill
    userPictureImageView.layer.cornerRadius = 50
    userPictureImageView.clipsToBounds = true
    userPictureImageView.backgroundColor = .lightGray
    view.addSubview(userPictureImageView)
    
    // User name label
    userNameLabel.font = .systemFont(ofSize: 18, weight: .bold)
    userNameLabel.textColor = .label
    userNameLabel.textAlignment = .center
    view.addSubview(userNameLabel)
    
    // User email label
    userEmailLabel.font = .systemFont(ofSize: 14, weight: .regular)
    userEmailLabel.textColor = .secondaryLabel
    userEmailLabel.textAlignment = .center
    view.addSubview(userEmailLabel)

    // Logout button
    logoutButton.setTitle("Log Out", for: .normal)
    logoutButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
    logoutButton.addTarget(self, action: #selector(logoutButtonTapped), for: .touchUpInside)
    view.addSubview(logoutButton)
    
    // Layout
    userPictureImageView.translatesAutoresizingMaskIntoConstraints = false
    userNameLabel.translatesAutoresizingMaskIntoConstraints = false
    userEmailLabel.translatesAutoresizingMaskIntoConstraints = false
    logoutButton.translatesAutoresizingMaskIntoConstraints = false
    
    NSLayoutConstraint.activate([
      userPictureImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      userPictureImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 30),
      userPictureImageView.widthAnchor.constraint(equalToConstant: 100),
      userPictureImageView.heightAnchor.constraint(equalToConstant: 100),
      
      userNameLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      userNameLabel.topAnchor.constraint(equalTo: userPictureImageView.bottomAnchor, constant: 20),
      userNameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      userNameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      
      userEmailLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      userEmailLabel.topAnchor.constraint(equalTo: userNameLabel.bottomAnchor, constant: 10),
      userEmailLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      userEmailLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      
      logoutButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      logoutButton.topAnchor.constraint(equalTo: userEmailLabel.bottomAnchor, constant: 30),
      logoutButton.heightAnchor.constraint(equalToConstant: 44),
      logoutButton.widthAnchor.constraint(equalToConstant: 120),
    ])
  }
  
  private func displayUserInfo() {
    guard let user = user else { return }
    
    userNameLabel.text = user.name
    userEmailLabel.text = user.email
    
    if !user.picture.isEmpty, let url = URL(string: user.picture) {
      userPictureImageView.load(url: url)
    }
  }
  
  @objc private func logoutButtonTapped() {
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
