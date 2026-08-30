//
// TasksViewController.swift
// iOS UIKit Login
//
// Task management page - Create, Read, Update, Delete tasks
//

import UIKit
import Auth0

class TasksViewController: UIViewController {
  
  private let tableView = UITableView()
  private let createButton = UIButton(type: .system)
  private var tasks: [[String: Any]] = []
  
  var user: User?
  var credentials: Credentials?
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    setupUI()
    loadTasks()
  }
  
  private func setupUI() {
    title = "Tasks"
    view.backgroundColor = .systemBackground
    
    // Table view
    tableView.delegate = self
    tableView.dataSource = self
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "TaskCell")
    tableView.backgroundColor = .systemBackground
    view.addSubview(tableView)
    
    // Create button
    createButton.setTitle("+ Create Task", for: .normal)
    createButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
    createButton.addTarget(self, action: #selector(createTaskTapped), for: .touchUpInside)
    view.addSubview(createButton)
    
    // Layout
    tableView.translatesAutoresizingMaskIntoConstraints = false
    createButton.translatesAutoresizingMaskIntoConstraints = false
    
    NSLayoutConstraint.activate([
      createButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 15),
      createButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      createButton.heightAnchor.constraint(equalToConstant: 44),
      
      tableView.topAnchor.constraint(equalTo: createButton.bottomAnchor, constant: 15),
      tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
  }
  
  private func loadTasks() {
    guard let userEmail = user?.email else { return }
    guard let credentials = credentials else {
      print("❌ No credentials found")
      return
    }
    
    guard let url = URL(string: "https://r283rocx67.execute-api.us-east-1.amazonaws.com/dev/tasks/get-all-tasks") else { return }
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let payload = ["userId": userEmail]
    
    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: payload)
      
      URLSession.shared.dataTask(with: request) { data, response, error in
        DispatchQueue.main.async {
          if let error = error {
            print("❌ Failed to load tasks: \(error)")
            return
          }
          
          if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            if let data = data {
              do {
                let jsonObject = try JSONSerialization.jsonObject(with: data)
                if let dict = jsonObject as? [String: Any], let tasksArray = dict["tasks"] as? [[String: Any]] {
                  self.tasks = tasksArray
                  self.tableView.reloadData()
                }
              } catch {
                print("❌ Failed to parse tasks: \(error)")
              }
            }
          }
        }
      }.resume()
    } catch {
      print("❌ Failed to encode request: \(error)")
    }
  }
  
  @objc private func createTaskTapped() {
    let alert = UIAlertController(title: "Create Task", message: nil, preferredStyle: .alert)
    
    alert.addTextField { textField in
      textField.placeholder = "Task name"
    }
    
    alert.addTextField { textField in
      textField.placeholder = "Description (optional)"
    }
    
    alert.addTextField { textField in
      textField.placeholder = "Due date (YYYY-MM-DD, optional)"
    }
    
    alert.addAction(UIAlertAction(title: "Create", style: .default) { _ in
      guard let name = alert.textFields?[0].text, !name.isEmpty else {
        self.showError("Task name is required")
        return
      }
      
      let description = alert.textFields?[1].text ?? ""
      let dueDate = alert.textFields?[2].text ?? ""
      
      self.createTask(name: name, description: description, dueDate: dueDate)
    })
    
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    
    present(alert, animated: true)
  }
  
  private func createTask(name: String, description: String, dueDate: String) {
    guard let userEmail = user?.email else { return }
    guard let credentials = credentials else { return }
    
    guard let url = URL(string: "https://r283rocx67.execute-api.us-east-1.amazonaws.com/dev/tasks/create") else { return }
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let payload: [String: Any] = [
      "userId": userEmail,
      "name": name,
      "description": description,
      "dueDate": dueDate,
      "repeat": "weekly"
    ]
    
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
              self.loadTasks()
            } else {
              self.showError("Failed to create task (Status: \(httpResponse.statusCode))")
            }
          }
        }
      }.resume()
    } catch {
      showError("Failed to encode request: \(error.localizedDescription)")
    }
  }
  
  private func deleteTask(taskId: String) {
    guard let credentials = credentials else { return }
    
    guard let url = URL(string: "https://r283rocx67.execute-api.us-east-1.amazonaws.com/dev/tasks/\(taskId)") else { return }
    
    var request = URLRequest(url: url)
    request.httpMethod = "DELETE"
    request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
    
    URLSession.shared.dataTask(with: request) { data, response, error in
      DispatchQueue.main.async {
        if let error = error {
          self.showError("Failed to delete task: \(error.localizedDescription)")
          return
        }
        
        if let httpResponse = response as? HTTPURLResponse {
          if httpResponse.statusCode == 200 {
            print("✅ Task deleted successfully")
            self.loadTasks()
          } else {
            self.showError("Failed to delete task (Status: \(httpResponse.statusCode))")
          }
        }
      }
    }.resume()
  }
  
  private func editTask(_ task: [String: Any]) {
    guard let taskId = task["taskId"] as? String else { return }
    
    let alert = UIAlertController(title: "Edit Task", message: nil, preferredStyle: .alert)
    
    alert.addTextField { textField in
      textField.placeholder = "Task name"
      textField.text = task["name"] as? String
    }
    
    alert.addTextField { textField in
      textField.placeholder = "Description (optional)"
      textField.text = task["description"] as? String
    }
    
    alert.addTextField { textField in
      textField.placeholder = "Due date (YYYY-MM-DD, optional)"
      textField.text = task["dueDate"] as? String
    }
    
    alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
      guard let name = alert.textFields?[0].text, !name.isEmpty else {
        self.showError("Task name is required")
        return
      }
      
      let description = alert.textFields?[1].text ?? ""
      let dueDate = alert.textFields?[2].text ?? ""
      
      self.updateTask(taskId: taskId, name: name, description: description, dueDate: dueDate)
    })
    
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    
    present(alert, animated: true)
  }
  
  private func updateTask(taskId: String, name: String, description: String, dueDate: String) {
    guard let userEmail = user?.email else { return }
    guard let credentials = credentials else { return }
    
    guard let url = URL(string: "https://r283rocx67.execute-api.us-east-1.amazonaws.com/dev/tasks/\(taskId)") else { return }
    
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let payload: [String: Any] = [
      "userId": userEmail,
      "name": name,
      "description": description,
      "dueDate": dueDate,
      "repeat": "weekly"
    ]
    
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
              self.loadTasks()
            } else {
              self.showError("Failed to update task (Status: \(httpResponse.statusCode))")
            }
          }
        }
      }.resume()
    } catch {
      showError("Failed to encode request: \(error.localizedDescription)")
    }
  }
  
  private func showError(_ message: String) {
    let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
  }
}

extension TasksViewController: UITableViewDelegate, UITableViewDataSource {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return tasks.count
  }
  
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "TaskCell", for: indexPath)
    let task = tasks[indexPath.row]
    
    let taskName = task["name"] as? String ?? "Untitled"
    let dueDate = task["dueDate"] as? String ?? ""
    let dueDateText = dueDate.isEmpty ? "" : " | Due: \(dueDate)"
    
    var config = cell.defaultContentConfiguration()
    config.text = taskName
    config.secondaryText = dueDateText
    cell.contentConfiguration = config
    
    return cell
  }
  
  func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
    let task = tasks[indexPath.row]
    let taskId = task["taskId"] as? String ?? ""
    
    let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { _, _, completionHandler in
      self.deleteTask(taskId: taskId)
      completionHandler(true)
    }
    
    let editAction = UIContextualAction(style: .normal, title: "Edit") { _, _, completionHandler in
      self.editTask(task)
      completionHandler(true)
    }
    editAction.backgroundColor = .systemBlue
    
    let configuration = UISwipeActionsConfiguration(actions: [deleteAction, editAction])
    return configuration
  }
}
