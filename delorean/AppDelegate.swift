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

    enum BackupStatus {
        case notAttempted
        case successful
        case networkUnavailable
    }
    
    private func readDestinationFromPlist() -> String? {
        let plistPath = "\(NSHomeDirectory())/Library/Preferences/com.ufemit.delorean.plist"
        
        if let plistDict = NSDictionary(contentsOfFile: plistPath),
           let destPath = plistDict["destinationPath"] as? String {
            // Expand environment variables
            let expandedPath = destPath
                .replacingOccurrences(of: "$(whoami)", with: NSUserName())
                .replacingOccurrences(of: "$HOME", with: NSHomeDirectory())
            return expandedPath
        }
        
        // No fallback - return nil if plist doesn't exist
        return nil
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
        
        // Try to read destination from plist
        if let destination = readDestinationFromPlist() {
            self.dest = destination
            
            // Check if network drive is available
            if !isNetworkDriveAvailable() {
                writeToLog("Backup Failed: Network drive not mounted (manual backup)")
                notifyUser(title: "Backup Failed", informativeText: "Network drive is not accessible.")
                return
            }
        }
        // If plist doesn't exist, let bash script handle it
        
        isManualBackup = true
        writeToLog("Manual backup initiated")
        print("DEBUG: Starting backup with script: \(scriptPath)")
        NotificationCenter.default.post(name: .StartBackup, object: nil, userInfo: ["scriptPath": scriptPath])
    }
 
    // MARK: - Backup Configuration and Schedule
    private func loadConfig() {
        let plistPath = "\(NSHomeDirectory())/Library/Preferences/com.ufemit.delorean.plist"
        
        // Check if plist exists
        guard let plistDict = NSDictionary(contentsOfFile: plistPath) as? [String: Any] else {
            print("WARNING: Plist doesn't exist yet. Will be created on first backup run.")
            // Set minimal defaults so the app doesn't crash
            self.backupHour = "08"
            self.backupMinute = "10"
            self.rangeStart = "07:00"
            self.rangeEnd = "21:00"
            self.frequency = 3600
            self.maxDayAttemptNotification = 6
            self.logFilePath = "\(NSHomeDirectory())/delorean.log"
            
            // Start timer with defaults
            self.startBackupTimer()
            self.updateLastBackupStatus()
            return
        }
        
        // Read scheduled backup time
        if let timeString = plistDict["scheduledBackupTime"] as? String {
            let timeComponents = timeString.split(separator: ":").map { String($0) }
            if timeComponents.count == 2 {
                self.backupHour = timeComponents[0]
                self.backupMinute = timeComponents[1]
            }
        }
        
        // Read range times
        if let start = plistDict["rangeStart"] as? String {
            self.rangeStart = start
        }
        if let end = plistDict["rangeEnd"] as? String {
            self.rangeEnd = end
        }
        
        // Read frequency
        if let freq = plistDict["frequencyCheck"] as? Int {
            self.frequency = TimeInterval(freq)
        }
        
        // Read max notification days
        if let maxDays = plistDict["maxDayAttemptNotification"] as? Int {
            self.maxDayAttemptNotification = maxDays
        }
        
        // Read and expand log file path
        if let logPath = plistDict["logFilePath"] as? String {
            self.logFilePath = logPath
                .replacingOccurrences(of: "$HOME", with: NSHomeDirectory())
                .replacingOccurrences(of: "$(whoami)", with: NSUserName())
        }
        
        // Read and expand destination
        if let destPath = plistDict["destinationPath"] as? String {
            self.dest = destPath
                .replacingOccurrences(of: "$HOME", with: NSHomeDirectory())
                .replacingOccurrences(of: "$(whoami)", with: NSUserName())
        }
        
        // Read sources array
        if let sourcesArray = plistDict["sources"] as? [String] {
            self.sources = sourcesArray.map { path in
                path.replacingOccurrences(of: "$HOME", with: NSHomeDirectory())
                    .replacingOccurrences(of: "$(whoami)", with: NSUserName())
            }
        }
        
        print("DEBUG: Loaded config from plist - Backup time: \(backupHour):\(backupMinute)")
        
        self.startBackupTimer()
        self.updateLastBackupStatus()
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
        let volumePath = extractVolumePath(from: self.dest)
        return FileManager.default.fileExists(atPath: volumePath)
    }

    private func extractVolumePath(from destPath: String) -> String {
        // Split path and find the volume component
        let components = destPath.split(separator: "/").map(String.init)
        
        // Find "Volumes" index
        guard let volumesIndex = components.firstIndex(of: "Volumes"),
              volumesIndex + 1 < components.count else {
            // Fallback: if not a /Volumes/ path, return the original path
            return destPath
        }
        
        // Return "/Volumes/VolumeName"
        let volumeName = components[volumesIndex + 1]
        return "/Volumes/\(volumeName)"
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
        
        // Try to read destination from plist
        guard let destination = readDestinationFromPlist() else {
            // Plist doesn't exist yet - bash script will create it on first run
            // Skip the drive check and let bash handle everything
            guard let scriptPath = Bundle.main.path(forResource: "sync_files", ofType: "sh") else {
                print("ERROR: Failed to locate sync_files.sh during scheduled backup")
                return
            }
            isManualBackup = false
            writeToLog("Scheduled backup initiated")
            isBackupRunning = true
            NotificationCenter.default.post(name: .StartBackup, object: nil, userInfo: ["scriptPath": scriptPath])
            return
        }
        
        // Plist exists, update dest and check if drive is mounted
        self.dest = destination
        
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

        isManualBackup = false
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
