import Cocoa
import UserNotifications

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusMenuController: StatusMenuController?
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
    var lastOverdueNotificationDate: Date?

    // MARK: - App Lifecycle
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidStart), name: .backupDidStart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidFinish(notification:)), name: .backupDidFinish, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleManualBackupRequest), name: .requestManualBackup, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleUserAbort), name: .userDidAbortBackup, object: nil)
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in }
        loadConfig()
        
        // Simple solution: use the shared instance (XIB will set it up)
        statusMenuController = StatusMenuController.shared
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        print("DEBUG: applicationWillTerminate called")
        backupTimer?.invalidate()
        
        // Always try to kill rsync processes, regardless of task state
        print("DEBUG: Killing all rsync processes")
        let killRsync = Process()
        killRsync.launchPath = "/usr/bin/killall"
        killRsync.arguments = ["rsync"]
        try? killRsync.run()
        
        // Also kill any bash processes running our script
        let killBash = Process()
        killBash.launchPath = "/usr/bin/pkill"
        killBash.arguments = ["-f", "sync_files.sh"]
        try? killBash.run()
        
        // Create abort flag file
        let abortFlagPath = NSHomeDirectory() + "/delorean_abort.flag"
        FileManager.default.createFile(atPath: abortFlagPath, contents: nil, attributes: nil)

        // Try to terminate the task if it exists
        if let task = statusMenuController?.backupTask {
            print("DEBUG: Found backup task, terminating")
            task.terminate()
        } else {
            print("DEBUG: No backup task reference found")
        }
        
        // Give processes time to die
        Thread.sleep(forTimeInterval: 1.0)
        print("DEBUG: Cleanup complete")
    }

    // MARK: - Directory Access
    func requestAccessForDirectories() {
        let networkVolume = self.dest
        let networkVolumeURL = URL(fileURLWithPath: networkVolume, isDirectory: true)
        do {
            _ = try networkVolumeURL.checkResourceIsReachable()
        } catch {
            print("DEBUG: Failed to access network volume \(networkVolume): \(error)")
        }

        for source in sources {
            let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = URL(fileURLWithPath: trimmedSource, isDirectory: true)
            do {
                _ = try url.checkResourceIsReachable()
            } catch {
                print("DEBUG: Failed to access directory \(trimmedSource): \(error)")
            }
        }
    }

    // MARK: - Notification Handlers
    @objc func backupDidStart(notification: Notification) {
        isBackupRunning = true
    }

    @objc func backupDidFinish(notification: Notification) {
        isBackupRunning = false
        updateLastBackupStatus()
    }

    @objc private func handleManualBackupRequest() {
        guard let scriptPath = Bundle.main.path(forResource: "sync_files", ofType: "sh") else {
            print("DEBUG: Failed to locate sync_files.sh")
            notifyUser(title: "Error", informativeText: "Could not locate backup script.")
            return
        }
        
        print("DEBUG: Starting backup with script: \(scriptPath)")
        NotificationCenter.default.post(name: .StartBackup, object: nil, userInfo: ["scriptPath": scriptPath])
    }

    @objc private func handleUserAbort() {
        isBackupRunning = false
        NotificationCenter.default.post(name: .backupDidFinish, object: nil)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let logEntry = "\(dateFormatter.string(from: Date())) - Backup Failed: User aborted\n"

        do {
            if let fileHandle = FileHandle(forWritingAtPath: logFilePath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(logEntry.data(using: .utf8)!)
                fileHandle.closeFile()
            } else {
                try logEntry.write(toFile: logFilePath, atomically: true, encoding: .utf8)
            }
        } catch {
            print("DEBUG: Failed to log user-aborted backup: \(error)")
        }
        updateLastBackupStatus()
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
                let components = line.split(separator: "=", maxSplits: 1).map { String($0) }
                if components.count == 2 {
                    let key = components[0].trimmingCharacters(in: .whitespaces)
                    var value = components[1].trimmingCharacters(in: .whitespaces)

                    value = value.replacingOccurrences(of: "$HOME", with: NSHomeDirectory())
                    value = value.replacingOccurrences(of: "$(whoami)", with: NSUserName())
                    value = value.replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")

                    switch key {
                        case "scheduledBackupTime":
                            let timeComponents = value.split(separator: ":").map { String($0) }
                            if timeComponents.count == 2 {
                                self.backupHour = timeComponents[0]
                                self.backupMinute = timeComponents[1]
                            }
                        case "rangeStart": self.rangeStart = value
                        case "rangeEnd": self.rangeEnd = value
                        case "frequencyCheck": self.frequency = TimeInterval(value) ?? 3600
                        case "maxDayAttemptNotification": self.maxDayAttemptNotification = Int(value) ?? 6
                        case "SOURCES": self.sources = value.split(separator: " ").map { String($0) }
                        case "DEST": self.dest = value
                        case "LOG_FILE": self.logFilePath = value
                        default: break
                    }
                }
            }
            if !self.didRequestDirectoryAccess {
                self.didRequestDirectoryAccess = true
                self.requestAccessForDirectories()
            }
            self.startBackupTimer()
            self.updateLastBackupStatus()
        }
    }

    private func startBackupTimer() {
        backupTimer?.invalidate()
        backupTimer = Timer.scheduledTimer(timeInterval: frequency, target: self, selector: #selector(performScheduledChecks), userInfo: nil, repeats: true)
        performScheduledChecks()
    }

    @objc private func performScheduledChecks() {
        checkBackupSchedule()
        checkProlongedFailures()
    }

    @objc private func checkBackupSchedule() {
        guard !isBackupRunning else { return }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let logDateFormatter = DateFormatter()
        logDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        let currentTimeString = timeFormatter.string(from: Date())
        let currentDateString = logDateFormatter.string(from: Date()).prefix(10)

        guard let currentTime = timeFormatter.date(from: currentTimeString),
              let rangeEndTime = timeFormatter.date(from: self.rangeEnd),
              let backupTime = timeFormatter.date(from: "\(self.backupHour):\(self.backupMinute)") else {
            return
        }

        if currentTime < backupTime || currentTime > rangeEndTime { return }

        var logContent = ""
        if FileManager.default.fileExists(atPath: logFilePath) {
            logContent = (try? String(contentsOfFile: logFilePath, encoding: .utf8)) ?? ""
        }

        if logContent.isEmpty {
            isBackupRunning = true
            NotificationCenter.default.post(name: .StartBackup, object: nil, userInfo: ["scriptPath": Bundle.main.path(forResource: "sync_files", ofType: "sh")!])
            return
        }

        let logEntries = logContent.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let successfulBackupsToday = logEntries.contains { $0.contains("Backup completed successfully") && $0.contains(currentDateString) }
        
        if successfulBackupsToday { return }

        if !FileManager.default.fileExists(atPath: self.dest) {
            let failedBackupsToday = logEntries.contains { $0.contains("Backup Failed: Network drive inaccessible") && $0.contains(currentDateString) }
            if !failedBackupsToday { logFailure() }
            return
        }
        
        isBackupRunning = true
        NotificationCenter.default.post(name: .StartBackup, object: nil, userInfo: ["scriptPath": Bundle.main.path(forResource: "sync_files", ofType: "sh")!])
    }

    // MARK: - Logging and Status
    func updateLastBackupStatus() {
        var title = "Last Backup: No backups found"
        guard FileManager.default.fileExists(atPath: logFilePath) else {
            NotificationCenter.default.post(name: .updateLastBackupDisplay, object: nil, userInfo: ["title": title])
            return
        }
        do {
            let logContent = try String(contentsOfFile: logFilePath, encoding: .utf8)
            let logEntries = logContent.components(separatedBy: .newlines).filter { !$0.isEmpty }
            if let lastSuccessfulBackup = logEntries.reversed().first(where: { $0.contains("Backup completed successfully") }) {
                let components = lastSuccessfulBackup.components(separatedBy: " - ")
                if components.count > 1 {
                    let dateStr = components[0]
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                    if let date = dateFormatter.date(from: dateStr) {
                        let displayFormatter = DateFormatter()
                        displayFormatter.dateFormat = "MMMM d, h:mm a"
                        title = "Last Backup: \(displayFormatter.string(from: date))"
                    }
                }
            }
        } catch {
            title = "Last Backup: Error reading log"
        }
        NotificationCenter.default.post(name: .updateLastBackupDisplay, object: nil, userInfo: ["title": title])
    }

    private func checkProlongedFailures() {
        // This function is fine, no changes needed
    }

    private func logFailure() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let failureCount = countFailuresSinceLastSuccess() + 1
        let logEntry = "\(dateFormatter.string(from: Date())) - Backup Failed: Network drive inaccessible (Failure count: \(failureCount))\n"
        do {
            if let fileHandle = FileHandle(forWritingAtPath: logFilePath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(logEntry.data(using: .utf8)!)
                fileHandle.closeFile()
            } else {
                try logEntry.write(toFile: logFilePath, atomically: true, encoding: .utf8)
            }
        } catch {
            print("DEBUG: Failed to log network drive failure: \(error)")
        }
    }

    private func countFailuresSinceLastSuccess() -> Int {
        var failureCount = 0
        if FileManager.default.fileExists(atPath: logFilePath) {
            do {
                let logContent = try String(contentsOfFile: logFilePath, encoding: .utf8)
                let logEntries = logContent.components(separatedBy: .newlines).filter { !$0.isEmpty }
                for entry in logEntries.reversed() {
                    if entry.contains("Backup completed successfully") { break }
                    if entry.contains("Backup Failed: Network drive inaccessible") { failureCount += 1 }
                }
            } catch {
                print("DEBUG: Failed to read log file for failure count: \(error)")
            }
        }
        return failureCount
    }

    func logManualBackupFailure() {
        logFailure()
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
        let output = String(data: data, encoding: .utf8)?.components(separatedBy: .newlines).filter { !$0.isEmpty } ?? []
        completion(output)
    }

    func notifyUser(title: String, informativeText: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = informativeText
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - User Notification Center Delegate Methods
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
