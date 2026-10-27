//
// ViewController.swift
// iOS UIKit Login
// 3 June 2022
//
// Companion project for the Auth0 blog article
// “Get Started with iOS Authentication Using Swift and UIKit”.
//
// See the end of the file for licensing information.
//


import UIKit
import Auth0

class ViewController: UIViewController {
  
  // Controls from Main.storyboard. They stay connected (but hidden) so the
  // storyboard keeps working; the login screen itself is built in code below.
  @IBOutlet weak var titleLabel: UILabel!
  @IBOutlet weak var loginButton: UIButton!
  @IBOutlet weak var logoutButton: UIButton!
  @IBOutlet weak var userInfoStack: UIStackView!
  @IBOutlet weak var userNameLabel: UILabel!
  @IBOutlet weak var userEmailLabel: UILabel!
  @IBOutlet weak var userPicture: UIImageView!
  
  private var userIsAuthenticated = false
  private var user = User.empty
  
  /// Identifier of the API created in Auth0 (Applications → APIs).
  /// Asking for it makes Auth0 issue a signed access token that API Gateway can verify.
  /// Must exactly match the API's Identifier in Auth0 and the Audience on the JWT authorizer.
  static let apiAudience = "https://api.taskorganizer.app"
  
  // Login screen
  private static let appName = "Task Organizer"
  private let backgroundView = GradientBackgroundView()
  private let mainStack = UIStackView()
  private let bottomStack = UIStackView()
  private let continueButton = UIButton(type: .system)
  private var didAnimateIn = false
  
  override var preferredStatusBarStyle: UIStatusBarStyle {
    return .lightContent
  }
}


extension ViewController {
  
  // MARK: View events
  // =================

  override func viewDidLoad() {
    super.viewDidLoad()
    
    // Hide the old storyboard controls
    for subview in view.subviews {
      subview.isHidden = true
    }
    
    buildLoginScreen()
  }
  
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    animateInIfNeeded()
  }
  
  
  // MARK: Actions
  // =============

  // Old storyboard button (hidden), kept so the storyboard connection stays valid.
  @IBAction func loginButtonPressed(_ sender: UIButton) {
    login()
  }
  
  // Old storyboard button (hidden), kept so the storyboard connection stays valid.
  // Logging out now happens from the Settings tab.
  @IBAction func logoutButtonPressed(_ sender: UIButton) {
  }
  
  @objc private func continueTapped() {
    if !userIsAuthenticated {
      login()
    }
  }
  
  
  // MARK: Login screen
  // ==================
  
  private func buildLoginScreen() {
    view.backgroundColor = .systemIndigo
    
    // Gradient background
    backgroundView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(backgroundView)
    
    // App icon
    let iconView = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
    iconView.tintColor = .white
    iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 46, weight: .semibold)
    iconView.translatesAutoresizingMaskIntoConstraints = false
    
    let iconTile = UIView()
    iconTile.backgroundColor = UIColor.white.withAlphaComponent(0.18)
    iconTile.layer.cornerRadius = 28
    iconTile.layer.cornerCurve = .continuous
    iconTile.layer.borderWidth = 1
    iconTile.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
    iconTile.translatesAutoresizingMaskIntoConstraints = false
    iconTile.addSubview(iconView)
    
    // Title + tagline
    let appNameLabel = UILabel()
    appNameLabel.text = ViewController.appName
    appNameLabel.font = Theme.roundedFont(size: 40, weight: .heavy)
    appNameLabel.textColor = .white
    appNameLabel.textAlignment = .center
    appNameLabel.adjustsFontSizeToFitWidth = true
    appNameLabel.minimumScaleFactor = 0.6
    
    let taglineLabel = UILabel()
    taglineLabel.text = "Plan your day. Never miss a thing."
    taglineLabel.font = Theme.roundedFont(size: 18, weight: .medium)
    taglineLabel.textColor = UIColor.white.withAlphaComponent(0.85)
    taglineLabel.textAlignment = .center
    taglineLabel.numberOfLines = 0
    
    let headerStack = UIStackView(arrangedSubviews: [iconTile, appNameLabel, taglineLabel])
    headerStack.axis = .vertical
    headerStack.alignment = .center
    headerStack.spacing = 8
    headerStack.setCustomSpacing(22, after: iconTile)
    
    // Feature highlights card
    let featuresStack = UIStackView(arrangedSubviews: [
      makeFeatureRow(symbol: "sun.max.fill", title: "Today at a glance", detail: "See what’s due and what’s overdue."),
      makeFeatureRow(symbol: "repeat", title: "Repeat anything", detail: "From every 30 minutes to once a year."),
      makeFeatureRow(symbol: "bell.badge.fill", title: "Reminders that fit", detail: "Quiet, standard or urgent alerts."),
    ])
    featuresStack.axis = .vertical
    featuresStack.spacing = 18
    featuresStack.translatesAutoresizingMaskIntoConstraints = false
    
    let featuresCard = UIView()
    featuresCard.backgroundColor = UIColor.white.withAlphaComponent(0.12)
    featuresCard.layer.cornerRadius = 24
    featuresCard.layer.cornerCurve = .continuous
    featuresCard.layer.borderWidth = 1
    featuresCard.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
    featuresCard.addSubview(featuresStack)
    
    mainStack.addArrangedSubview(headerStack)
    mainStack.addArrangedSubview(featuresCard)
    mainStack.axis = .vertical
    mainStack.spacing = 36
    mainStack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(mainStack)
    
    // Continue button
    var configuration = UIButton.Configuration.filled()
    configuration.title = "Continue"
    configuration.image = UIImage(systemName: "arrow.right")
    configuration.imagePlacement = .trailing
    configuration.imagePadding = 8
    configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
    configuration.cornerStyle = .capsule
    configuration.baseBackgroundColor = .white
    configuration.baseForegroundColor = Theme.accent
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
      var updated = attributes
      updated.font = Theme.roundedFont(size: 18, weight: .bold)
      return updated
    }
    continueButton.configuration = configuration
    continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
    continueButton.layer.shadowColor = UIColor.black.cgColor
    continueButton.layer.shadowOpacity = 0.18
    continueButton.layer.shadowRadius = 16
    continueButton.layer.shadowOffset = CGSize(width: 0, height: 8)
    
    let footnoteLabel = UILabel()
    footnoteLabel.text = "New here? You can create an account on the next screen."
    footnoteLabel.font = .systemFont(ofSize: 13, weight: .medium)
    footnoteLabel.textColor = UIColor.white.withAlphaComponent(0.75)
    footnoteLabel.textAlignment = .center
    footnoteLabel.numberOfLines = 0
    
    bottomStack.addArrangedSubview(continueButton)
    bottomStack.addArrangedSubview(footnoteLabel)
    bottomStack.axis = .vertical
    bottomStack.spacing = 14
    bottomStack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(bottomStack)
    
    // Layout
    let safeArea = view.safeAreaLayoutGuide
    
    // Centered, but pushed up if the screen is short
    let centerY = mainStack.centerYAnchor.constraint(equalTo: safeArea.centerYAnchor, constant: -50)
    centerY.priority = .defaultHigh
    
    // Full width on phones, capped on iPad
    let mainWidth = mainStack.widthAnchor.constraint(equalTo: safeArea.widthAnchor, constant: -48)
    mainWidth.priority = .defaultHigh
    let bottomWidth = bottomStack.widthAnchor.constraint(equalTo: safeArea.widthAnchor, constant: -48)
    bottomWidth.priority = .defaultHigh
    
    NSLayoutConstraint.activate([
      backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
      backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      
      iconTile.widthAnchor.constraint(equalToConstant: 100),
      iconTile.heightAnchor.constraint(equalToConstant: 100),
      iconView.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
      iconView.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
      
      featuresStack.topAnchor.constraint(equalTo: featuresCard.topAnchor, constant: 22),
      featuresStack.bottomAnchor.constraint(equalTo: featuresCard.bottomAnchor, constant: -22),
      featuresStack.leadingAnchor.constraint(equalTo: featuresCard.leadingAnchor, constant: 20),
      featuresStack.trailingAnchor.constraint(equalTo: featuresCard.trailingAnchor, constant: -20),
      
      mainStack.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
      mainWidth,
      mainStack.widthAnchor.constraint(lessThanOrEqualToConstant: 480),
      centerY,
      mainStack.topAnchor.constraint(greaterThanOrEqualTo: safeArea.topAnchor, constant: 16),
      mainStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomStack.topAnchor, constant: -24),
      
      continueButton.heightAnchor.constraint(equalToConstant: 56),
      bottomStack.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
      bottomWidth,
      bottomStack.widthAnchor.constraint(lessThanOrEqualToConstant: 480),
      bottomStack.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -20),
    ])
    
    // Start hidden; animateInIfNeeded() fades everything in.
    mainStack.alpha = 0
    bottomStack.alpha = 0
    mainStack.transform = CGAffineTransform(translationX: 0, y: 24)
    bottomStack.transform = CGAffineTransform(translationX: 0, y: 24)
  }
  
  private func makeFeatureRow(symbol: String, title: String, detail: String) -> UIView {
    let iconView = UIImageView(image: UIImage(systemName: symbol))
    iconView.tintColor = .white
    iconView.contentMode = .center
    iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
    iconView.backgroundColor = UIColor.white.withAlphaComponent(0.18)
    iconView.layer.cornerRadius = 12
    iconView.layer.cornerCurve = .continuous
    iconView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      iconView.widthAnchor.constraint(equalToConstant: 40),
      iconView.heightAnchor.constraint(equalToConstant: 40),
    ])
    
    let titleLabel = UILabel()
    titleLabel.text = title
    titleLabel.font = Theme.roundedFont(size: 17, weight: .bold)
    titleLabel.textColor = .white
    
    let detailLabel = UILabel()
    detailLabel.text = detail
    detailLabel.font = .systemFont(ofSize: 15)
    detailLabel.textColor = UIColor.white.withAlphaComponent(0.8)
    detailLabel.numberOfLines = 0
    
    let textStack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
    textStack.axis = .vertical
    textStack.spacing = 2
    
    let row = UIStackView(arrangedSubviews: [iconView, textStack])
    row.axis = .horizontal
    row.alignment = .center
    row.spacing = 14
    return row
  }
  
  private func animateInIfNeeded() {
    guard !didAnimateIn else { return }
    didAnimateIn = true
    
    UIView.animate(withDuration: 0.7, delay: 0.05, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [], animations: {
      self.mainStack.alpha = 1
      self.mainStack.transform = .identity
    })
    UIView.animate(withDuration: 0.7, delay: 0.2, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [], animations: {
      self.bottomStack.alpha = 1
      self.bottomStack.transform = .identity
    })
  }
  
  /// Shows "Signing In…" on the button while the Auth0 page is open.
  private func setLoading(_ loading: Bool) {
    continueButton.isUserInteractionEnabled = !loading
    
    var configuration = continueButton.configuration
    configuration?.title = loading ? "Signing In…" : "Continue"
    configuration?.image = loading ? nil : UIImage(systemName: "arrow.right")
    if #available(iOS 16.0, *) {
      configuration?.showsActivityIndicator = loading
    }
    continueButton.configuration = configuration
  }
  
  
  // MARK: Login, logout, and user information
  // =========================================

  func login() {
    setLoading(true)
    
    Auth0
      .webAuth()
      .audience(ViewController.apiAudience)
      // Private browser session: no "wants to use auth0.com to sign in" pop-up,
      // and no cookies left behind, so logging out doesn't need the browser.
      .useEphemeralSession()
      .start { result in
        DispatchQueue.main.async {
          switch result {
            
          case .failure(let error):
            self.setLoading(false)
            
            // Closing the login page isn't an error, so stay quiet.
            if error == .userCancelled {
              return
            }
            
            print("❌ Login failed: \(error)")
            let alert = UIAlertController(
              title: "Couldn’t Sign In",
              message: error.localizedDescription,
              preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
            
          case .success(let credentials):
            self.userIsAuthenticated = true
            self.user = User.from(credentials.idToken)
            self.presentHomeViewController(with: credentials)
            self.setLoading(false)
          }
        }
      }
  }
  
    func presentHomeViewController(with credentials: Credentials) {
      // Today / Upcoming / All Tasks tabs
      let todayNav = makeTasksTab(
        mode: .today,
        title: "Today",
        image: "sun.max",
        selectedImage: "sun.max.fill",
        tag: 0,
        credentials: credentials
      )
      let upcomingNav = makeTasksTab(
        mode: .upcoming,
        title: "Upcoming",
        image: "calendar",
        selectedImage: "calendar",
        tag: 1,
        credentials: credentials
      )
      let allTasksNav = makeTasksTab(
        mode: .all,
        title: "All Tasks",
        image: "checklist",
        selectedImage: "checklist",
        tag: 2,
        credentials: credentials
      )
      
      // Settings tab
      let settingsVC = HomeViewController()
      settingsVC.user = self.user
      settingsVC.credentials = credentials
      settingsVC.onLogout = { [weak self] in
        self?.userIsAuthenticated = false
        self?.user = User.empty
        TaskNotifications.shared.removeAll() // don't remind the next person who logs in
        DispatchQueue.main.async {
          self?.setLoading(false)
        }
      }
      let settingsNav = UINavigationController(rootViewController: settingsVC)
      Theme.styleNavigationBar(settingsNav)
      settingsNav.tabBarItem = UITabBarItem(
        title: "Settings",
        image: UIImage(systemName: "gearshape"),
        selectedImage: UIImage(systemName: "gearshape.fill")
      )
      settingsNav.tabBarItem.tag = 3
      
      // Tab bar controller
      let tabBarController = UITabBarController()
      tabBarController.viewControllers = [todayNav, upcomingNav, allTasksNav, settingsNav]
      tabBarController.tabBar.tintColor = Theme.accent
      tabBarController.view.tintColor = Theme.accent
      tabBarController.modalPresentationStyle = .fullScreen
      
      self.present(tabBarController, animated: true)
    }
  
    private func makeTasksTab(
      mode: TaskListMode,
      title: String,
      image: String,
      selectedImage: String,
      tag: Int,
      credentials: Credentials
    ) -> UINavigationController {
      let tasksVC = TasksViewController()
      tasksVC.mode = mode
      tasksVC.user = self.user
      tasksVC.credentials = credentials
      
      let nav = UINavigationController(rootViewController: tasksVC)
      Theme.styleNavigationBar(nav)
      nav.tabBarItem = UITabBarItem(
        title: title,
        image: UIImage(systemName: image),
        selectedImage: UIImage(systemName: selectedImage)
      )
      nav.tabBarItem.tag = tag
      return nav
    }

}

// MARK: - Login background
// ========================

/// Indigo → purple → pink gradient with two soft glowing circles.
final class GradientBackgroundView: UIView {
  
  override class var layerClass: AnyClass {
    return CAGradientLayer.self
  }
  
  private let topGlow = UIView()
  private let bottomGlow = UIView()
  
  override init(frame: CGRect) {
    super.init(frame: frame)
    
    isUserInteractionEnabled = false
    clipsToBounds = true
    
    if let gradient = layer as? CAGradientLayer {
      gradient.colors = [
        UIColor(red: 0.33, green: 0.29, blue: 0.93, alpha: 1).cgColor, // indigo
        UIColor(red: 0.53, green: 0.27, blue: 0.88, alpha: 1).cgColor, // purple
        UIColor(red: 0.86, green: 0.33, blue: 0.62, alpha: 1).cgColor, // pink
      ]
      gradient.locations = [0, 0.55, 1]
      gradient.startPoint = CGPoint(x: 0, y: 0)
      gradient.endPoint = CGPoint(x: 1, y: 1)
    }
    
    for glow in [topGlow, bottomGlow] {
      glow.backgroundColor = UIColor.white.withAlphaComponent(0.09)
      addSubview(glow)
    }
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  override func layoutSubviews() {
    super.layoutSubviews()
    
    let topSize: CGFloat = 340
    topGlow.frame = CGRect(x: bounds.width - topSize * 0.6, y: -topSize * 0.4, width: topSize, height: topSize)
    topGlow.layer.cornerRadius = topSize / 2
    
    let bottomSize: CGFloat = 280
    bottomGlow.frame = CGRect(x: -bottomSize * 0.45, y: bounds.height * 0.58, width: bottomSize, height: bottomSize)
    bottomGlow.layer.cornerRadius = bottomSize / 2
  }
}


// License information
// ===================
//
// Copyright (c) 2022 Auth0 (http://auth0.com)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
