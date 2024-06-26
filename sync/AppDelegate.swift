import Cocoa
import UserNotifications

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var isBackupRunning = false
    var backupTimer: Timer?
    var backupHour = ""
    var backupMinute = ""
    var rangeStart = ""
    var rangeEnd = ""
    var frequency: TimeInterval = 30
    var maxDayAttemptNotification = 0 // Default value, will be overwritten by loadConfig()
    var logFilePath = "\(NSHomeDirectory())/delorean.log" // Default value, will be overwritten by loadConfig()


    // MARK: - App Lifecycle
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidStart), name: .backupDidStart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidFinish), name: .backupDidFinish, object: nil)

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in }
        loadConfig()  // This should be the only place where the timer starts
        // Removed checkProlongedFailures from here to avoid immediate notification
    }

    @objc func backupDidStart(notification: Notification) {
        isBackupRunning = true
    }

    @objc func backupDidFinish(notification: Notification) {
        isBackupRunning = false
//        checkProlongedFailures()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        backupTimer?.invalidate()

        if let task = StatusMenuController.shared.backupTask {
            task.terminate()
        }
    }

    // MARK: - Backup Configuration and Schedule
    private func loadConfig() {
        guard let scriptPath = Bundle.main.path(forResource: "sync_files", ofType: "sh") else {
            print("Failed to locate sync_files.sh")
            return
        }

        let command = "grep '=' \(scriptPath) | grep -v '^#' | tr -d '\"' | tr -d ' '"
        executeShellCommand(command) { output in
            output.forEach { line in
                let components = line.split(separator: "=").map { String($0) }
                if components.count == 2 {
                    switch components[0] {
                        case "scheduledBackupTime":
                            let timeComponents = components[1].split(separator: ":").map { String($0) }
                            if timeComponents.count == 2 {
                                self.backupHour = timeComponents[0]
                                self.backupMinute = timeComponents[1]
                            }
                        case "rangeStart":
                            self.rangeStart = components[1]
                        case "rangeEnd":
                            self.rangeEnd = components[1]
                        case "frequencyCheck":
                            self.frequency = TimeInterval(components[1]) ?? 3600
                        case "maxDayAttemptNotification":
                            self.maxDayAttemptNotification = Int(components[1]) ?? 6
                        case "LOG_FILE":
                            self.logFilePath = components[1].replacingOccurrences(of: "$HOME", with: NSHomeDirectory())
                            print("DEBUG: logFilePath set to \(self.logFilePath)")
                        default: break
                    }
                }
            }
            print("DEBUG: loadConfig completed. Starting backup timer.")
            self.startBackupTimer() // Ensure this is only called once
        }
    }

    private func startBackupTimer() {
        backupTimer?.invalidate()
        print("DEBUG: Setting up the backup timer.")
        backupTimer = Timer.scheduledTimer(timeInterval: frequency, target: self, selector: #selector(performScheduledChecks), userInfo: nil, repeats: true)
        performScheduledChecks() // Perform an immediate check
    }

    @objc private func performScheduledChecks() {
        print("DEBUG: performScheduledChecks called.")
        checkBackupSchedule()
        checkProlongedFailures()
    }

    
    
    
    
    
    
    
    
    
    
    @objc private func checkBackupSchedule() {
        print("DEBUG: checkBackupSchedule called.")
        guard !isBackupRunning else {
            print("DEBUG: Backup is already in progress.")
            return
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        timeFormatter.timeZone = TimeZone.current

        let logDateFormatter = DateFormatter()
        logDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        logDateFormatter.timeZone = TimeZone.current

        let currentTimeString = timeFormatter.string(from: Date())
        let currentDateString = logDateFormatter.string(from: Date()).prefix(10) // Get the current date in yyyy-MM-dd format

        guard let currentTime = timeFormatter.date(from: currentTimeString),
              let rangeEnd = timeFormatter.date(from: self.rangeEnd),
              let backupTime = timeFormatter.date(from: "\(self.backupHour):\(self.backupMinute)") else {
            print("DEBUG: There was an error parsing the date or time.")
            return
        }

        // If current time is not within the scheduled backup window, exit
        if currentTime < backupTime || currentTime > rangeEnd {
            print("DEBUG: Current time is outside the backup window.")
            return
        }

        var didRunBackupToday = false
        var logContent = ""

        if FileManager.default.fileExists(atPath: logFilePath) {
            do {
                logContent = try String(contentsOfFile: logFilePath, encoding: .utf8)
                print("DEBUG: Successfully read log file.")
            } catch {
                print("DEBUG: Failed to read log file: \(error)")
                logContent = ""  // Ensure logContent is initialized even if reading fails
            }
        } else {
            print("DEBUG: Log file does not exist yet.")
        }

        if logContent.isEmpty {
            print("DEBUG: Backup log is empty, initiating backup.")
            isBackupRunning = true
            NotificationCenter.default.post(name: Notification.Name("StartBackup"), object: nil, userInfo: ["scriptPath": Bundle.main.path(forResource: "sync_files", ofType: "sh")!])
            return
        }

        let logEntries = logContent.components(separatedBy: "\n").filter { !$0.isEmpty }
        let successfulBackupsToday = logEntries.filter { $0.contains("Backup completed successfully") && $0.contains(currentDateString) }
        didRunBackupToday = !successfulBackupsToday.isEmpty
        print("DEBUG: Backup log found. Did run backup today? \(didRunBackupToday)")

        // Ensure the network drive is accessible before scheduling a backup
        let destPath = "/Volumes/SFA-All/User Data/\(NSUserName())"
        let fileManager = FileManager.default

        print("DEBUG: Checking if network drive is accessible.")
        if !fileManager.fileExists(atPath: destPath) {
            print("DEBUG: Network drive is not accessible.")
            // Call the sync_files.sh script to log the failure
            let scriptPath = Bundle.main.path(forResource: "sync_files", ofType: "sh")!
            let process = Process()
            process.launchPath = "/bin/bash"
            process.arguments = [scriptPath]
            process.launch()
            process.waitUntilExit()
            return
        }

        if !didRunBackupToday && currentTime >= backupTime && currentTime <= rangeEnd {
            print("DEBUG: Conditions met for starting backup.")
            isBackupRunning = true
            NotificationCenter.default.post(name: Notification.Name("StartBackup"), object: nil, userInfo: ["scriptPath": Bundle.main.path(forResource: "sync_files", ofType: "sh")!])
        } else if didRunBackupToday {
            print("DEBUG: Backup already completed for today.")
        } else {
            print("DEBUG: Current time is outside the backup window.")
        }
    }

    
    
    
    
    
    
    
    
    
    
    private func checkProlongedFailures() {
        let logDateFormatter = DateFormatter()
        logDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        logDateFormatter.timeZone = TimeZone.current

        var lastSuccessfulBackupDate: Date?

        if FileManager.default.fileExists(atPath: logFilePath) {
            do {
                let logContent = try String(contentsOfFile: logFilePath, encoding: .utf8)
                let logEntries = logContent.components(separatedBy: "\n").filter { !$0.isEmpty }
                for entry in logEntries.reversed() { // Iterate in reverse to find the most recent success
                    if entry.contains("Backup completed successfully") {
                        let dateString = entry.prefix(19) // Extract the date and time portion
                        lastSuccessfulBackupDate = logDateFormatter.date(from: String(dateString))
                        break
                    }
                }
            } catch {
                print("DEBUG: Failed to read log file: \(error)")
            }
        } else {
            print("DEBUG: Log file does not exist yet.")
        }

        guard let lastBackupDate = lastSuccessfulBackupDate else {
            print("DEBUG: No valid last successful backup date found.")
            return
        }

        let currentDate = Date()
        let calendar = Calendar.current
        if let daysBetween = calendar.dateComponents([.day], from: lastBackupDate, to: currentDate).day {
            if daysBetween >= maxDayAttemptNotification {
                // Check if we have already sent an overdue notification today
                if let lastNotificationDate = lastOverdueNotificationDate, calendar.isDateInToday(lastNotificationDate) {
                    return
                }

                // Check if the current time is within the scheduled backup window
                let timeFormatter = DateFormatter()
                timeFormatter.dateFormat = "HH:mm"
                timeFormatter.timeZone = TimeZone.current

                let currentTimeString = timeFormatter.string(from: currentDate)
                let backupTimeString = "\(self.backupHour):\(self.backupMinute)"
                let rangeEndString = self.rangeEnd

                guard let currentTime = timeFormatter.date(from: currentTimeString),
                      let backupTime = timeFormatter.date(from: backupTimeString),
                      let rangeEnd = timeFormatter.date(from: rangeEndString) else {
                    print("DEBUG: There was an error parsing the date or time.")
                    return
                }

                if currentTime >= backupTime && currentTime <= rangeEnd {
                    // Send overdue notification
                    notifyUser(title: "Backup Overdue", informativeText: "It's been \(daysBetween) days since the files on your computer were last backed up.")
                    lastOverdueNotificationDate = currentDate
                } else {
                    print("DEBUG: Current time is outside the backup window.")
                }
            }
        }
    }
    
    
    
    
    
    
    
    
    
    
    
    

    @objc private func performBackup() {
        guard !isBackupRunning else {
            print("Backup is already in progress.")
            return
        }
        guard let scriptPath = Bundle.main.path(forResource: "sync_files", ofType: "sh") else {
            DispatchQueue.main.async {
                self.notifyUser(title: "Backup Error", informativeText: "Failed to locate backup script.")
            }
            return
        }
        if StatusMenuController.shared.isRunning {
            print("Backup process attempted to start, but one is already in progress.")
            return
        }

        isBackupRunning = true
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
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        print("User interacted with notification: \(response.notification.request.identifier)")
        completionHandler()
    }

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
    
    var lastOverdueNotificationDate: Date?

    private func daysSinceLastBackup() -> Int? {
        let logDateFormatter = DateFormatter()
        logDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        logDateFormatter.timeZone = TimeZone.current

        var lastSuccessfulBackupDate: Date?

        if FileManager.default.fileExists(atPath: logFilePath) {
            do {
                let logContent = try String(contentsOfFile: logFilePath, encoding: .utf8)
                let logEntries = logContent.components(separatedBy: "\n").filter { !$0.isEmpty }
                for entry in logEntries.reversed() { // Iterate in reverse to find the most recent success
                    if entry.contains("Backup completed successfully") {
                        let dateString = entry.prefix(19) // Extract the date and time portion
                        lastSuccessfulBackupDate = logDateFormatter.date(from: String(dateString))
                        break
                    }
                }
            } catch {
                print("DEBUG: Failed to read log file: \(error)")
            }
        } else {
            print("DEBUG: Log file does not exist yet.")
        }

        guard let lastBackupDate = lastSuccessfulBackupDate else {
            print("DEBUG: No valid last successful backup date found.")
            return nil
        }

        let currentDate = Date()
        let calendar = Calendar.current
        if let daysBetween = calendar.dateComponents([.day], from: lastBackupDate, to: currentDate).day {
            return daysBetween
        } else {
            return nil
        }
    }
}
