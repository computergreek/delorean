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
    
    // MARK: - App Lifecycle
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidStart), name: .backupDidStart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidFinish), name: .backupDidFinish, object: nil)
        
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in }
        loadConfig()
    }
    
    @objc func backupDidStart(notification: Notification) {
        isBackupRunning = true
    }
    
    @objc func backupDidFinish(notification: Notification) {
        isBackupRunning = false
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
                    default: break
                    }
                }
            }
            self.startBackupTimer()
        }
    }
    
    private func startBackupTimer() {
        backupTimer?.invalidate()
        backupTimer = Timer.scheduledTimer(timeInterval: frequency, target: self, selector: #selector(checkBackupSchedule), userInfo: nil, repeats: true)
        checkBackupSchedule()
    }
    
    func readMaxDayAttemptNotification() -> Int {
        let scriptPath = Bundle.main.path(forResource: "sync_files", ofType: "sh") ?? ""
        do {
            let scriptContent = try String(contentsOfFile: scriptPath)
            let regex = try NSRegularExpression(pattern: "maxDayAttemptNotification=(\\d+)", options: [])
            if let match = regex.firstMatch(in: scriptContent, options: [], range: NSRange(location: 0, length: scriptContent.utf16.count)) {
                if let range = Range(match.range(at: 1), in: scriptContent) {
                    let value = scriptContent[range]
                    return Int(value) ?? 6 // Default to 6 if conversion fails
                }
            }
        } catch {
            print("DEBUG: Failed to read sync_files.sh: \(error)")
        }
        return 6 // Default value
    }

    @objc private func checkBackupSchedule() {
        let maxDayAttemptNotification = readMaxDayAttemptNotification()
        guard !isBackupRunning else {
            print("DEBUG: Backup is already in progress.")
            return
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        timeFormatter.timeZone = TimeZone.current

        let logDateFormatter = DateFormatter()
        logDateFormatter.dateFormat = "yyyy-MM-dd"
        logDateFormatter.timeZone = TimeZone.current

        let currentTimeString = timeFormatter.string(from: Date())
        let currentDate = logDateFormatter.string(from: Date())

        guard let currentTime = timeFormatter.date(from: currentTimeString),
              let rangeStart = timeFormatter.date(from: self.rangeStart),
              let rangeEnd = timeFormatter.date(from: self.rangeEnd),
              let backupTime = timeFormatter.date(from: "\(self.backupHour):\(self.backupMinute)") else {
            print("DEBUG: There was an error parsing the date or time.")
            return
        }

        let logFilePath = "\(NSHomeDirectory())/delorean.log"
        var didRunBackupToday = false
        var logContent = ""

        if !FileManager.default.fileExists(atPath: logFilePath) {
            // Create the log file if it doesn't exist
            FileManager.default.createFile(atPath: logFilePath, contents: nil, attributes: nil)
        }

        do {
            logContent = try String(contentsOfFile: logFilePath, encoding: .utf8)
        } catch {
            print("DEBUG: Failed to read log file: \(error)")
        }

        if !logContent.isEmpty {
            let logEntries = logContent.components(separatedBy: "\n").filter { !$0.isEmpty }
            let lastLogEntry = logEntries.last ?? ""
            let successfulBackupsToday = logEntries.filter { $0.contains("Backup completed successfully") && $0.contains(currentDate) }
            didRunBackupToday = !successfulBackupsToday.isEmpty
            print("DEBUG: Backup log found. Did run backup today? \(didRunBackupToday)")

            // Ensure the network drive is accessible before scheduling a backup
            let destPath = "/Volumes/SFA-All/User Data/\(NSUserName())"
            let fileManager = FileManager.default

            print("DEBUG: Checking if network drive is accessible.")
            if fileManager.fileExists(atPath: destPath) {
                print("DEBUG: Network drive is accessible.")
                if !didRunBackupToday && currentTime >= rangeStart && currentTime <= rangeEnd {
                    if currentTime >= backupTime {
                        print("DEBUG: Conditions met for starting backup.")
                        isBackupRunning = true
                        NotificationCenter.default.post(name: Notification.Name("StartBackup"), object: nil, userInfo: ["scriptPath": Bundle.main.path(forResource: "sync_files", ofType: "sh")!])
                    } else {
                        print("DEBUG: Not yet time for scheduled backup.")
                    }
                } else if didRunBackupToday {
                    print("DEBUG: Backup already completed for today.")
                } else {
                    print("DEBUG: Current time is outside the backup window.")
                }
            } else {
                print("DEBUG: Network drive is not accessible.")
                let recentFailures = logEntries.filter { $0.contains("Backup Failed: Network drive inaccessible") }
                let failureCount = recentFailures.count
                print("DEBUG: Failure count: \(failureCount)")
                if !didRunBackupToday && lastLogEntry.contains("Backup Failed: Network drive inaccessible") && failureCount >= maxDayAttemptNotification {
                    print("DEBUG: Failure count threshold met, sending notification.")
                    DispatchQueue.main.async {
                        self.notifyUser(title: "Backup Error", informativeText: "The network drive is not accessible. Ensure you are connected to the network and try again.")
                    }
                }
            }
        } else {
            print("DEBUG: Backup log file not found or inaccessible.")
            return
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
}
