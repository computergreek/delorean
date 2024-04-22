import Cocoa
import UserNotifications

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var isBackupRunning = false
    var backupTimer: Timer?
    var backupHour = ""  // Default values removed since they'll be loaded from config
    var backupMinute = ""
    var rangeStart = ""
    var rangeEnd = ""
    var frequency: TimeInterval = 30  // This could remain as a default, or be set in the script
    
    // MARK: - App Lifecycle
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Set up listeners for backup status
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidStart), name: .backupDidStart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidFinish), name: .backupDidFinish, object: nil)
        
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
        }
        loadConfig()
    }
    
    @objc func backupDidStart(notification: Notification) {
        isBackupRunning = true
    }
    
    @objc func backupDidFinish(notification: Notification) {
        isBackupRunning = false
    }

//    func applicationWillTerminate(_ aNotification: Notification) {
//        backupTimer?.invalidate()
//    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        backupTimer?.invalidate()
        
        // Terminate the backup process if it's running
        if let task = StatusMenuController.shared.backupTask {
            task.terminate()
        }
    }


    // MARK: - Backup Configuration and Schedule
    private func loadConfig() {
//    print("I'm in loadConfig now")
        // Assuming 'sync_files.sh' is within the app bundle
        guard let scriptPath = Bundle.main.path(forResource: "sync_files", ofType: "sh") else {
            print("Failed to locate sync_files.sh")
            return
        }

        let command = "grep '=' \(scriptPath) | grep -v '^#' | tr -d '\"' | tr -d ' '"
        //print (command)
        executeShellCommand(command) { output in
            output.forEach { line in
                let components = line.split(separator: "=").map { String($0) }
                //print (line)
                if components.count == 2 {
                    switch components[0] {
                    case "scheduledBackupTime":
                        let timeComponents = components[1].split(separator: ":").map { String($0) }
                        if timeComponents.count == 2 {
                            self.backupHour = timeComponents[0]
                            self.backupMinute = timeComponents[1]
                        }
                        //print("ScheduledBackupTime Found")
                    case "rangeStart":
                        self.rangeStart = components[1]
                        //print("rangeStart Found")
                    case "rangeEnd":
                        self.rangeEnd = components[1]
                        //print("rangeEnd Found")
                    case "frequencyCheck":
                        self.frequency = TimeInterval(components[1]) ?? 3600
                        //print("frequencyCheck Found")
                        print("Frequency set to " + String(format: "%f",  self.frequency))
                    default: break
                    }
                }
            }
            // Once configuration is loaded, (re)start the timer
            self.startBackupTimer()
        }
    }
    
    private func startBackupTimer() {
        // Invalidate the existing timer if it exists
        backupTimer?.invalidate()

        // Setup the timer again
        backupTimer = Timer.scheduledTimer(timeInterval: frequency, target: self, selector: #selector(checkBackupSchedule), userInfo: nil, repeats: true)
        checkBackupSchedule()  // Also perform an immediate check.
    }
    
    @objc private func checkBackupSchedule() {
        // Configure the time formatter
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        timeFormatter.timeZone = TimeZone.current  // Ensure the formatter uses the current time zone

        // Configure the date formatter for reading dates from the log
        let logDateFormatter = DateFormatter()
        logDateFormatter.dateFormat = "yyyy-MM-dd"
        logDateFormatter.timeZone = TimeZone.current  // Match the log's time zone with the current

        // Get strings representing the current time and date
        let currentTimeString = timeFormatter.string(from: Date())
        let currentDate = logDateFormatter.string(from: Date())

        // Parse times from strings
        guard let currentTime = timeFormatter.date(from: currentTimeString),
              let rangeStart = timeFormatter.date(from: self.rangeStart),
              let rangeEnd = timeFormatter.date(from: self.rangeEnd),
              let backupTime = timeFormatter.date(from: "\(self.backupHour):\(self.backupMinute)") else {
            print("There was an error parsing the date or time.")
            return
        }

        let logFilePath = "/Volumes/SFA-All/User Data/\(NSUserName())/dBackup.log"
        var didRunBackupToday = false

        // Read from the log file and determine if a backup has already been done today
        if FileManager.default.fileExists(atPath: logFilePath),
           let logContent = try? String(contentsOfFile: logFilePath, encoding: .utf8) {
            didRunBackupToday = logContent.contains(currentDate)
            print("Backup log found. Did run backup today? \(didRunBackupToday)")
        } else {
            print("Backup log file not found or inaccessible.")
            DispatchQueue.main.async {
                self.notifyUser(title: "Backup Error", informativeText: "The network drive is not accessible. Ensure you are connected to the network and try again.")
            }
            return
        }

        if !didRunBackupToday && currentTime >= rangeStart && currentTime <= rangeEnd {
            if currentTime >= backupTime {
                print("Conditions met for starting backup.")
                performBackup() // This should initiate the backup using the existing performBackup method
            } else {
                print("Not yet time for scheduled backup.")
            }
        } else if didRunBackupToday {
            print("Backup already completed for today.")
        } else {
            print("Current time is outside the backup window.")
        }
    }


//    private func performBackup() {
//        NotificationCenter.default.post(name: Notification.Name.backupDidStart, object: nil)
//        DispatchQueue.global(qos: .background).async {
//            // Ensure the backup script exists before executing
//            guard let scriptPath = Bundle.main.path(forResource: "sync_files", ofType: "sh") else {
//                DispatchQueue.main.async {
//                    print("Failed to locate sync_files.sh for backup")
//                    self.notifyUser(title: "Backup Error", informativeText: "Failed to locate backup script.")
//                }
//                return
//            }
//            
//            self.executeShellCommand("/bin/bash \(scriptPath)") { output in
//                DispatchQueue.main.async {
//                    print("Backup process completed: \(output.joined(separator: "\n"))")
//                    self.notifyUser(title: "Backup Complete", informativeText: "The backup process has completed successfully.")
//                    NotificationCenter.default.post(name: Notification.Name.backupDidFinish, object: nil)
//                }
//            }
//        }
//    }

//    private func performBackup() {
//        guard let scriptPath = Bundle.main.path(forResource: "sync_files", ofType: "sh") else {
//            DispatchQueue.main.async {
//                self.notifyUser(title: "Backup Error", informativeText: "Failed to locate backup script.")
//            }
//            return
//        }
//
//        NotificationCenter.default.post(name: Notification.Name("StartBackup"), object: nil, userInfo: ["scriptPath": scriptPath])
//    }
    
    private func performBackup() {
        guard !isBackupRunning else {
            print("Backup is already in progress.")
            return
        }
        // Ensure the backup script path can be located
        guard let scriptPath = Bundle.main.path(forResource: "sync_files", ofType: "sh") else {
            DispatchQueue.main.async {
                self.notifyUser(title: "Backup Error", informativeText: "Failed to locate backup script.")
            }
            return
        }
        // Check if the StatusMenuController indicates a backup is already running
        if StatusMenuController.shared.isRunning {
            print("Backup process attempted to start, but one is already in progress.")
            return
        }

        // Post a notification to start the backup only if no backup is in progress
        NotificationCenter.default.post(name: Notification.Name("StartBackup"), object: nil, userInfo: ["scriptPath": scriptPath])
    }



    // MARK: - Helper Methods
    private func executeShellCommand(_ command: String, completion: @escaping ([String]) -> Void) {
        let process = Process()
        let pipe = Pipe()

        process.launchPath = "/bin/bash"
        process.arguments = ["-c", command]
        process.standardOutput = pipe

        process.launch()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.components(separatedBy: "\n").filter { !$0.isEmpty } ?? []
        
        completion(output)
    }

    // MARK: - User Notification Center Delegate Methods
    // This method is called when a notification is about to be presented while the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Here, you can choose to present the notification with a banner, sound, badge, or a combination of these.
        // For example, to present the notification as a banner with a sound, you would call the completion handler like this:
        completionHandler([.banner, .sound])
        // This allows the notification to be visible to the user even if the app is open, ensuring they are aware of the backup status or any other important information.
    }

    // This method is called when the user interacts with a notification, for example, by tapping on it.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle the user's interaction with the notification here.
        // This could involve taking specific actions like opening a particular view in your app, or simply logging the user's response.
        // For now, we'll just print out the identifier of the notification and complete the handler.
        print("User interacted with notification: \(response.notification.request.identifier)")
        completionHandler()  // Always call this when finished handling the interaction to let the system know you're done.
    }

    // Add to your AppDelegate class
    func notifyUser(title: String, informativeText: String) {
        let notificationCenter = UNUserNotificationCenter.current()
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = title
        notificationContent.body = informativeText
        notificationContent.sound = UNNotificationSound.default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: notificationContent, trigger: nil)
        notificationCenter.add(request) { (error) in
            if let error = error {
                print("Error posting user notification: \(error.localizedDescription)")
            }
        }
    }
}
