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
  
  // On-screen controls
  @IBOutlet weak var titleLabel: UILabel!
  @IBOutlet weak var loginButton: UIButton!
  @IBOutlet weak var logoutButton: UIButton!
  @IBOutlet weak var userInfoStack: UIStackView!
  @IBOutlet weak var userNameLabel: UILabel!
  @IBOutlet weak var userEmailLabel: UILabel!
  @IBOutlet weak var userPicture: UIImageView!
  
    private var appJustLaunched = true
    private var userIsAuthenticated = false
    private var user = User.empty
  // Auth0 data
  // TODO: Add Auth0 data properties.
  
}


extension ViewController {
  
  // MARK: View events
  // =================

  override func viewDidLoad() {
    super.viewDidLoad()
        
      updateTitle()
          userInfoStack.isHidden = true
          loginButton.isEnabled = true
          logoutButton.isEnabled = false
  }
  
  
  // MARK: Actions
  // =============

  @IBAction func loginButtonPressed(_ sender: UIButton) {
      if !userIsAuthenticated {
            login()
          }
  }
  
  @IBAction func logoutButtonPressed(_ sender: UIButton) {
      Auth0
          .webAuth()
          .logout(federated: true) { result in
            switch result {

            case .failure(let error):
              print("Failed with: \(error)")
              
              case .success():
                self.userIsAuthenticated = false
                self.user = User.empty

                DispatchQueue.main.async {
                  self.updateTitle()
                  self.updateButtonsAndStack()
                }
              
            } // switch
                
        }
  }
  
  
  // MARK: UI updaters
  // =================

  func updateTitle() {
      if appJustLaunched {
            titleLabel.text = "Welcome to the app!"
            appJustLaunched = false
          } else {
            if userIsAuthenticated {
              titleLabel.text = "You’re logged in."
            } else {
              titleLabel.text = "You’re logged out."
            }
          }
  }

  func updateButtonsAndStack() {
      loginButton.isEnabled = !userIsAuthenticated
          logoutButton.isEnabled = userIsAuthenticated
          userInfoStack.isHidden = !userIsAuthenticated
  }
  
  func updateUserInfoUI() {
      userNameLabel.text = user.name
         userEmailLabel.text = user.email
         userPicture.load(url: URL(string: user.picture)!)
  }
  
  
  // MARK: Login, logout, and user information
  // =========================================

  func login() {
      Auth0
            .webAuth()
            .start { result in
         
              switch result {
                        
                case .failure(let error):
                  if error == .userCancelled {
                                let alert = UIAlertController(
                                  title: "Please log in.",
                                  message: "You need to log in to use the app.",
                                  preferredStyle: .alert)
                                alert.addAction(
                                  UIAlertAction(
                                    title: NSLocalizedString(
                                      "OK",
                                      comment: "Default action"
                                    ),
                                    style: .default,
                                    handler: { _ in
                                      NSLog("Displayed the please login alert.")
                                }))
                                self.present(alert, animated: true, completion: nil)
                              
                              } else {
                                print("An unexpected error occurred: \\(error.localizedDescription)")
                              }
                  
                case .success(let credentials):
                   self.userIsAuthenticated = true
                   self.user = User.from(credentials.idToken)
                   
                   DispatchQueue.main.async {
                     self.presentHomeViewController(with: credentials)
                   }
              } // switch
                
            }
  }
  
    func presentHomeViewController(with credentials: Credentials) {
      // Settings tab
      let settingsVC = HomeViewController()
      settingsVC.user = self.user
      settingsVC.credentials = credentials
      settingsVC.onLogout = { [weak self] in
        self?.userIsAuthenticated = false
        self?.user = User.empty
        DispatchQueue.main.async {
          self?.updateTitle()
          self?.updateButtonsAndStack()
        }
      }
      let settingsNav = UINavigationController(rootViewController: settingsVC)
      settingsNav.tabBarItem = UITabBarItem(title: "Settings", image: UIImage(systemName: "gear"), tag: 0)
      
      // Tasks tab
      let tasksVC = TasksViewController()
      tasksVC.user = self.user
      tasksVC.credentials = credentials
      let tasksNav = UINavigationController(rootViewController: tasksVC)
      tasksNav.tabBarItem = UITabBarItem(title: "Tasks", image: UIImage(systemName: "checkmark.circle"), tag: 1)
      
      // Tab bar controller
      let tabBarController = UITabBarController()
      tabBarController.viewControllers = [tasksNav, settingsNav]
      tabBarController.modalPresentationStyle = .fullScreen
      
      self.present(tabBarController, animated: true)
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
