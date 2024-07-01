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
    var sources: [String] = []
    var dest: String = ""
    
    var didRequestDirectoryAccess = false

    // MARK: - App Lifecycle
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidStart), name: .backupDidStart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidFinish), name: .backupDidFinish, object: nil)

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in }
        
        loadConfig()  // This should be the only place where the timer starts
    }
    
    func requestAccessForDirectories() {
        // Ensure network volume access prompt is shown first
        let networkVolume = self.dest
        print("DEBUG: Attempting to access network volume: \(networkVolume)")
        let networkVolumeURL = URL(fileURLWithPath: networkVolume, isDirectory: true)
        do {
            let networkVolumeContents = try FileManager.default.contentsOfDirectory(at: networkVolumeURL, includingPropertiesForKeys: nil)
            // Access the first file in the network volume to trigger the permission prompt
            if let firstNetworkFile = networkVolumeContents.first(where: { !$0.hasDirectoryPath }) {
                print("DEBUG: Accessing file: \(firstNetworkFile.path)")
                let _ = try Data(contentsOf: firstNetworkFile)
            } else {
                print("DEBUG: No files found in network volume: \(networkVolume)")
            }
        } catch {
            print("DEBUG: Failed to access network volume \(networkVolume): \(error)")
        }

        // Proceed to access other directories
        for source in sources {
            let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
            print("DEBUG: Attempting to access directory: \(trimmedSource)")
            let url = URL(fileURLWithPath: trimmedSource, isDirectory: true)
            do {
                // Check if the directory exists before trying to access its contents
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: trimmedSource, isDirectory: &isDir), isDir.boolValue {
                    print("DEBUG: Directory exists: \(trimmedSource)")
                    let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                    // Access the first file in the directory to trigger the permission prompt
                    if let firstFile = contents.first(where: { !$0.hasDirectoryPath }) {
                        print("DEBUG: Accessing file: \(firstFile.path)")
                        let _ = try Data(contentsOf: firstFile)
                    } else {
                        print("DEBUG: No files found in directory: \(trimmedSource)")
                    }
                } else {
                    print("DEBUG: Directory does not exist or is not a directory: \(trimmedSource)")
                }
            } catch {
                print("DEBUG: Failed to access directory \(trimmedSource): \(error)")
            }
            // Add a short delay to allow macOS to handle the prompts properly
            Thread.sleep(forTimeInterval: 1)
        }
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

        let command = "grep '=' \(scriptPath) | grep -v '^#' | tr -d '\"'"
        executeShellCommand(command) { output in
            output.forEach { line in
                let components = line.split(separator: "=").map { String($0) }
                if components.count == 2 {
                    let key = components[0]
                    var value = components[1]

                    // Replace placeholders
                    value = value.replacingOccurrences(of: "$HOME", with: NSHomeDirectory())
                    value = value.replacingOccurrences(of: "$(whoami)", with: NSUserName())
                    
                    // Remove stray parentheses
                    value = value.replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")

                    switch key {
                        case "scheduledBackupTime":
                            let timeComponents = value.split(separator: ":").map { String($0) }
                            if timeComponents.count == 2 {
                                self.backupHour = timeComponents[0]
                                self.backupMinute = timeComponents[1]
                            }
                        case "rangeStart":
                            self.rangeStart = value
                        case "rangeEnd":
                            self.rangeEnd = value
                        case "frequencyCheck":
                            self.frequency = TimeInterval(value) ?? 3600
                        case "maxDayAttemptNotification":
                            self.maxDayAttemptNotification = Int(value) ?? 6
                        case "SOURCES":
                            self.sources = value.split(separator: " ").map { String($0) }
                        case "DEST":
                            self.dest = value
                        case "LOG_FILE":
                            self.logFilePath = value
                            print("DEBUG: logFilePath set to \(self.logFilePath)")
                        default:
                            print("DEBUG: Ignoring unknown config variable \(key) with value \(value)")
                    }
                    print("DEBUG: Loaded \(key) with value \(value)")
                }
            }
            print("DEBUG: loadConfig completed.")
            // Request access to directories before starting the backup timer
            if !self.didRequestDirectoryAccess {
                self.didRequestDirectoryAccess = true
                self.requestAccessForDirectories()
            }
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
        let failedBackupsToday = logEntries.filter { $0.contains("Backup Failed: Network drive inaccessible") && $0.contains(currentDateString) }
        didRunBackupToday = !successfulBackupsToday.isEmpty

        print("DEBUG: Backup log found. Did run backup today? \(didRunBackupToday)")

        // Check if there are any successful backups recorded at all
        let allSuccessfulBackups = logEntries.filter { $0.contains("Backup completed successfully") }
        let hasSuccessfulBackups = !allSuccessfulBackups.isEmpty

        // Ensure the network drive is accessible before scheduling a backup
        let fileManager = FileManager.default

        print("DEBUG: Checking if network drive is accessible.")
        if !fileManager.fileExists(atPath: self.dest) {
            print("DEBUG: Network drive is not accessible.")
            if !didRunBackupToday && failedBackupsToday.isEmpty {
                logFailure()  // Log failure only once per day if not accessible during scheduled time
            } else if currentTime > backupTime && currentTime <= rangeEnd && failedBackupsToday.isEmpty {
                logFailure()  // Log failure if this is the first interval check past the scheduled time
            }
            return
        }

        // Attempt backup if no successful backups are recorded at all
        if !hasSuccessfulBackups {
            print("DEBUG: No successful backups recorded, initiating backup.")
            isBackupRunning = true
            NotificationCenter.default.post(name: Notification.Name("StartBackup"), object: nil, userInfo: ["scriptPath": Bundle.main.path(forResource: "sync_files", ofType: "sh")!])
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

                // Ensure the network drive is accessible before sending overdue notification
                let fileManager = FileManager.default

                if !fileManager.fileExists(atPath: self.dest) {
                    print("DEBUG: Network drive is not accessible. Sending overdue notification.")
                    
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
                } else {
                    print("DEBUG: Network drive is accessible. No overdue notification needed.")
                }
            }
        }
    }

    private func logFailure() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let failureCount = countFailuresSinceLastSuccess() + 1
        let logEntry = "\(dateFormatter.string(from: Date())) - Backup Failed: Network drive inaccessible (Failure count: \(failureCount))\n"

        do {
            var logContent = try String(contentsOfFile: logFilePath, encoding: .utf8)
            logContent += logEntry
            try logContent.write(toFile: logFilePath, atomically: true, encoding: .utf8)
        } catch {
            print("DEBUG: Failed to log network drive failure: \(error)")
        }
    }

    private func countFailuresSinceLastSuccess() -> Int {
        var failureCount = 0
        if FileManager.default.fileExists(atPath: logFilePath) {
            do {
                let logContent = try String(contentsOfFile: logFilePath, encoding: .utf8)
                let logEntries = logContent.components(separatedBy: "\n").filter { !$0.isEmpty }
                for entry in logEntries.reversed() {
                    if entry.contains("Backup completed successfully") {
                        break
                    }
                    if entry.contains("Backup Failed: Network drive inaccessible") {
                        failureCount += 1
                    }
                }
            } catch {
                print("DEBUG: Failed to read log file for failure count: \(error)")
            }
        }
        return failureCount
    }

    func logManualBackupFailure() {
        logFailure()  // Reuse the same log failure function
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
