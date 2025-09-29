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
        
        // Terminate the backup task
        statusMenuController?.backupTask?.terminate()
        
        // Brief wait for clean shutdown
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
        // Check if network drive is accessible for manual backups
        let expandedDest = dest.replacingOccurrences(of: "$(whoami)", with: NSUserName())
        
        if !FileManager.default.fileExists(atPath: expandedDest) {
            logFailure()
            notifyUser(title: "Backup Failed", informativeText: "Network drive is not accessible.")
            return
        }
        
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
        
        // Read file directly instead of using shell commands
        guard let scriptContent = try? String(contentsOfFile: scriptPath) else {
            print("Failed to read sync_files.sh")
            return
        }
        
        let lines = scriptContent.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip comments and empty lines
            if trimmed.hasPrefix("#") || trimmed.isEmpty || !trimmed.contains("=") {
                continue
            }
            
            let components = trimmed.split(separator: "=", maxSplits: 1).map { String($0) }
            if components.count == 2 {
                let key = components[0].trimmingCharacters(in: .whitespaces)
                let rawValue = components[1].trimmingCharacters(in: .whitespaces)
                
                switch key {
                case "scheduledBackupTime":
                    let value = expandShellVariables(rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
                    let timeComponents = value.split(separator: ":").map { String($0) }
                    if timeComponents.count == 2 {
                        self.backupHour = timeComponents[0]
                        self.backupMinute = timeComponents[1]
                    }
                case "rangeStart":
                    self.rangeStart = expandShellVariables(rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
                case "rangeEnd":
                    self.rangeEnd = expandShellVariables(rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
                case "frequencyCheck":
                    let value = expandShellVariables(rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
                    self.frequency = TimeInterval(value) ?? 3600
                case "maxDayAttemptNotification":
                    let value = expandShellVariables(rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
                    self.maxDayAttemptNotification = Int(value) ?? 6
                case "SOURCES":
                    self.sources = parseShellArray(rawValue)
                case "DEST":
                    self.dest = expandShellVariables(rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
                case "LOG_FILE":
                    self.logFilePath = expandShellVariables(rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
                default:
                    break
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
 
    // Helper function to expand shell variables
    private func expandShellVariables(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "$HOME", with: NSHomeDirectory())
            .replacingOccurrences(of: "$(whoami)", with: NSUserName())
    }
 
    // Helper function to properly parse bash arrays
    private func parseShellArray(_ rawValue: String) -> [String] {
        let trimmed = rawValue.trimmingCharacters(in: .whitespaces)
        
        // Handle array format: ("item1" "item2" "item3")
        if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") {
            let arrayContent = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            
            var sources: [String] = []
            var current = ""
            var inQuotes = false
            
            for char in arrayContent {
                switch char {
                case "\"":
                    inQuotes.toggle()
                case " " where !inQuotes:
                    if !current.isEmpty {
                        sources.append(expandShellVariables(current))
                        current = ""
                    }
                default:
                    current.append(char)
                }
            }
            
            // Don't forget the last item
            if !current.isEmpty {
                sources.append(expandShellVariables(current))
            }
            
            return sources
        }
        
        // Fallback for non-array format
        return [expandShellVariables(trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))]
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
