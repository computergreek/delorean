import Cocoa
import UserNotifications
import ServiceManagement
 
@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusMenuController: StatusMenuController?
    var isBackupRunning = false
    var isManualBackup = false
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
    var lastOverdueNotificationDate: Date?
    private var todaysBackupStatus: BackupStatus = .notAttempted
    private var lastStatusCheckDate: String = ""
    private var lastNetworkCheckTime: Date = Date.distantPast
    private var lastNetworkCheckResult: Bool = false
    private var networkCacheInitialized: Bool = false
    private let networkCheckCacheInterval: TimeInterval = 30

    enum BackupStatus {
        case notAttempted
        case successful
        case networkUnavailable
    }

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private lazy var logDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private lazy var displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, h:mm a"
        return formatter
    }()

    private lazy var dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
 
    private let logQueue = DispatchQueue(label: "com.ufemit.delorean.logging", qos: .utility)

    private func writeToLog(_ message: String) {
        logQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Ensure log file exists with initial entry if needed
            if !FileManager.default.fileExists(atPath: self.logFilePath) {
                let initialEntry = "\(self.logDateFormatter.string(from: Date())) - Log file created\n"
                try? initialEntry.write(toFile: self.logFilePath, atomically: true, encoding: .utf8)
            }
            
            let logEntry = "\(self.logDateFormatter.string(from: Date())) - \(message)\n"
            do {
                if let fileHandle = FileHandle(forWritingAtPath: self.logFilePath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(logEntry.data(using: .utf8)!)
                    fileHandle.closeFile()
                } else {
                    try logEntry.write(toFile: self.logFilePath, atomically: true, encoding: .utf8)
                }
            } catch {
                print("DEBUG: Failed to write to log: \(error)")
            }
        }
    }
    
    // MARK: - App Lifecycle
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        registerAsLoginItem()  // ← THIS IS THE ONLY NEW LINE
        
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidStart), name: .backupDidStart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidFinish(notification:)), name: .backupDidFinish, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleManualBackupRequest), name: .requestManualBackup, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLogAbort), name: .logAbort, object: nil)
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in }
        loadConfig()
        
        // Simple solution: use the shared instance (XIB will set it up)
        statusMenuController = StatusMenuController.shared
    }
    
    private func registerAsLoginItem() {
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.register()
        }
    }
    
    @objc private func handleLogAbort() {
        writeToLog("Backup Failed: User aborted")
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
 
    // MARK: - Notification Handlers
    @objc func backupDidStart(notification: Notification) {
        isBackupRunning = true
    }
 
    @objc func backupDidFinish(notification: Notification) {
        isBackupRunning = false
        
        // Update today's status based on outcome
        if let userInfo = notification.userInfo,
           let success = userInfo["success"] as? Bool {
            if success {
                todaysBackupStatus = .successful
            }
            // On failure, don't change status - let retry logic work naturally
            // Network failures are handled separately in checkBackupSchedule()
        }
        
        updateLastBackupStatus()
    }
 
    @objc private func handleManualBackupRequest() {
        guard let scriptPath = Bundle.main.path(forResource: "sync_files", ofType: "sh") else {
            print("DEBUG: Failed to locate sync_files.sh")
            notifyUser(title: "Error", informativeText: "Could not locate backup script.")
            return
        }
        
        // Check if network drive is available for manual backup
        if !isNetworkDriveAvailable() {
            writeToLog("Backup Failed: Network drive not mounted (manual backup)")
            notifyUser(title: "Backup Failed", informativeText: "Network drive is not accessible.")
            return
        }
        
        isManualBackup = true
        writeToLog("Manual backup initiated")
        print("DEBUG: Starting backup with script: \(scriptPath)")
        NotificationCenter.default.post(name: .StartBackup, object: nil, userInfo: ["scriptPath": scriptPath])
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.backupTimer = Timer.scheduledTimer(withTimeInterval: self.frequency, repeats: true) { [weak self] _ in
                self?.performScheduledChecks()
            }
            self.performScheduledChecks()
        }
    }
 
    @objc private func performScheduledChecks() {
        checkBackupSchedule()
        checkProlongedFailures()
    }
    
    private func isNetworkDriveAvailable() -> Bool {
        let now = Date()
        
        // Always check on first call or if cache expired
        if !networkCacheInitialized || now.timeIntervalSince(lastNetworkCheckTime) > networkCheckCacheInterval {
            lastNetworkCheckResult = FileManager.default.fileExists(atPath: self.dest)
            lastNetworkCheckTime = now
            networkCacheInitialized = true
        }
        
        return lastNetworkCheckResult
    }
 
    @objc private func checkBackupSchedule() {
        guard !isBackupRunning else { return }
        
        let currentTimeString = timeFormatter.string(from: Date())
        let currentDateString = logDateFormatter.string(from: Date()).prefix(10)
        
        guard let currentTime = timeFormatter.date(from: currentTimeString),
              let rangeEndTime = timeFormatter.date(from: self.rangeEnd),
              let backupTime = timeFormatter.date(from: "\(self.backupHour):\(self.backupMinute)") else {
            return
        }
        
        if currentTime < backupTime || currentTime > rangeEndTime { return }
        
        // Reset status if it's a new day
        let todayString = String(currentDateString)
        if lastStatusCheckDate != todayString {
            todaysBackupStatus = .notAttempted
            lastStatusCheckDate = todayString
        }
        
        // If we already succeeded today, skip all further checks
        if todaysBackupStatus == .successful { return }
        
        // Check network drive availability
        if !isNetworkDriveAvailable() {
            // Only log once per day when drive is unavailable
            if todaysBackupStatus != .networkUnavailable {
                todaysBackupStatus = .networkUnavailable
                
                writeToLog("Backup Failed: Network drive not mounted (scheduled backup)")
            }
            return
        }
        
        // Network drive is available, start backup
        guard let scriptPath = Bundle.main.path(forResource: "sync_files", ofType: "sh") else {
            print("ERROR: Failed to locate sync_files.sh during scheduled backup")
            return
        }

        isManualBackup = false  // ← Mark this as scheduled
        writeToLog("Scheduled backup initiated")
        isBackupRunning = true
        NotificationCenter.default.post(name: .StartBackup, object: nil, userInfo: ["scriptPath": scriptPath])
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
                    if let date = logDateFormatter.date(from: dateStr) {
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
        // Only notify during work hours (same as backup window)
        let currentTimeString = timeFormatter.string(from: Date())
        guard let currentTime = timeFormatter.date(from: currentTimeString),
              let rangeStartTime = timeFormatter.date(from: self.rangeStart),
              let rangeEndTime = timeFormatter.date(from: self.rangeEnd) else {
            return
        }
        
        // Only notify during work hours
        if currentTime < rangeStartTime || currentTime > rangeEndTime { return }
        
        // Only notify once per day to avoid spam
        let now = Date()
        if let lastCheck = lastOverdueNotificationDate,
           Calendar.current.isDate(lastCheck, inSameDayAs: now) {
            return // Already notified today
        }
        
        // Check if it's been too many days since last successful backup
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -maxDayAttemptNotification, to: Date()) ?? Date()
        // Don't check for overdue backups if no log file exists (fresh install)
        guard FileManager.default.fileExists(atPath: logFilePath) else { return }
        do {
            let logContent = try String(contentsOfFile: logFilePath, encoding: .utf8)
            
            // Don't notify if log file is empty or only has "Log file created" entry
            let logEntries = logContent.components(separatedBy: .newlines).filter { !$0.isEmpty }
            let hasAnyBackupAttempts = logEntries.contains { line in
                line.contains("completed successfully") || line.contains("Backup Failed")
            }
            if !hasAnyBackupAttempts { return }
            let hasRecentSuccess = logContent.split(separator: "\n").contains { line in
                // Extract date part and compare properly
                if line.contains("Backup completed successfully") {
                    let lineString = String(line)
                    if let dateStr = lineString.components(separatedBy: " - ").first,
                       let backupDate = logDateFormatter.date(from: String(dateStr)) {
                        return backupDate >= cutoffDate
                    }
                }
                return false
            }
            
            if !hasRecentSuccess {
                // Calculate actual days since last successful backup
                var actualDaysSinceBackup = maxDayAttemptNotification
                
                // Find the most recent successful backup to get exact days
                if let lastSuccessLine = logContent.split(separator: "\n").last(where: { $0.contains("Backup completed successfully") }) {
                    let lineString = String(lastSuccessLine)
                    if let dateStr = lineString.components(separatedBy: " - ").first,
                       let lastBackupDate = logDateFormatter.date(from: String(dateStr)) {
                        actualDaysSinceBackup = max(1, Calendar.current.dateComponents([.day], from: lastBackupDate, to: now).day ?? maxDayAttemptNotification)
                    }
                } else {
                    // No successful backup found in history - don't notify yet
                    return
                }
                
                print("DEBUG: No recent success found, sending overdue notification")
                lastOverdueNotificationDate = now
                
                let dayText = actualDaysSinceBackup == 1 ? "day" : "days"
                notifyUser(
                    title: "Backup Overdue",
                    informativeText: "It's been \(actualDaysSinceBackup) \(dayText) since the files on your computer were last successfully backed up. Please make sure you're connected to the network drive and try again."
                )
            }
        } catch {
            return
        }
    }
 
    // MARK: - Helper Methods
 
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
