import Cocoa
import UserNotifications

extension Notification.Name {
    static let backupDidStart = Notification.Name("backupDidStart")
    static let backupDidFinish = Notification.Name("backupDidFinish")
}

class StatusMenuController: NSObject {
    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()
    
    // MARK: - Outlets
    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var startBackupItem: NSMenuItem!
    @IBOutlet weak var abortBackupItem: NSMenuItem!
    @IBOutlet weak var backupInProgressItem: NSMenuItem!
    @IBOutlet weak var lastBackupItem: NSMenuItem!
    
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var isRunning: Bool = false
    var backupTask: Process?
    static let shared = StatusMenuController()
    
    // MARK: - Awake and Menu Setup
    override func awakeFromNib() {
        super.awakeFromNib()
        setupMenuIcon()
        setupInitialMenuState()
        updateLastBackupItem()  // Ensure this is the correct method call
        
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidStart), name: .backupDidStart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidFinish), name: .backupDidFinish, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(startBackupFromNotification(_:)), name: Notification.Name("StartBackup"), object: nil)
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
    
    @objc func startBackupFromNotification(_ notification: Notification) {
        guard !isRunning else {
            print("DEBUG: Backup is already in progress.")
            notifyUser(title: "Process is still running", informativeText: "A backup process is already in progress.")
            return
        }

        if let scriptPath = notification.userInfo?["scriptPath"] as? String {
            isRunning = true
            NotificationCenter.default.post(name: .backupDidStart, object: nil)
            backupTask = Process()
            backupTask?.launchPath = "/bin/bash"
            backupTask?.arguments = [scriptPath]

            backupTask?.terminationHandler = { [weak self] process in
                DispatchQueue.main.async {
                    guard let self = self else { return }

                    let success = process.terminationStatus == 0
                    if success {
                        self.notifyUser(title: "Sync Completed", informativeText: "Your files have been successfully backed up.")
                    } else if !self.isUserInitiatedAbort {
                        self.notifyUser(title: "Sync Failed", informativeText: "There was an issue with the backup process.")
                    }

                    self.isRunning = false
                    self.updateLastBackupItem()
                    NotificationCenter.default.post(name: .backupDidFinish, object: nil)
                    self.isUserInitiatedAbort = false  // Reset the flag
                }
            }

            do {
                try backupTask?.run()
            } catch {
                print("DEBUG: Failed to start the backup task.")
                notifyUser(title: "Error", informativeText: "Failed to start the backup process.")
                self.isRunning = false
                NotificationCenter.default.post(name: .backupDidFinish, object: nil)
            }
        }
    }
    
    @objc func backupDidStart() {
        print("DEBUG: Backup did start.")
        updateUIForBackupStart()
    }
    
    @objc func backupDidFinish() {
        print("DEBUG: Backup did finish.")
        updateUIForBackupEnd()
        updateLastBackupItem()  // Ensure the last backup time is updated
    }

    func setupMenuIcon() {
        let icon = NSImage(named: NSImage.refreshFreestandingTemplateName)
        icon?.isTemplate = true
        statusItem.button?.image = icon
        statusItem.menu = statusMenu
    }
    
    func setupInitialMenuState() {
        startBackupItem.isHidden = isRunning
        abortBackupItem.isHidden = !isRunning
        backupInProgressItem.isHidden = !isRunning
        backupInProgressItem.isEnabled = !isRunning  // Disable when visible (during backup)
        lastBackupItem.isEnabled = false  // Make last backup item non-interactive
        lastBackupItem.isHidden = isRunning  // Hide last backup item if backup is in progress
        updateLastBackupItem()
    }
    
    func logFailure() {
        let logFilePath = "\(NSHomeDirectory())/delorean.log"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let logEntry = "\(dateFormatter.string(from: Date())) - Backup Failed: Network drive inaccessible\n"

        do {
            var logContent = try String(contentsOfFile: logFilePath, encoding: .utf8)
            logContent += logEntry
            try logContent.write(toFile: logFilePath, atomically: true, encoding: .utf8)
        } catch {
            print("DEBUG: Failed to log network drive failure: \(error)")
        }
    }
    
    // MARK: - Actions
    @IBAction func startBackupClicked(_ sender: NSMenuItem) {
        guard !isRunning else {
            print("DEBUG: Start backup clicked but process is still running.")
            notifyUser(title: "Process is still running", informativeText: "A backup process is already in progress.")
            return
        }

        let destPath = "/Volumes/SFA-All/User Data/\(NSUserName())"
        if !FileManager.default.fileExists(atPath: destPath) {
            if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                appDelegate.logManualBackupFailure()
            }
            notifyUser(title: "Backup Failed", informativeText: "Network drive is not accessible.")
            return
        }

        NotificationCenter.default.post(name: Notification.Name("StartBackup"), object: nil, userInfo: ["scriptPath": Bundle.main.path(forResource: "sync_files", ofType: "sh")!])
    }

    var isUserInitiatedAbort: Bool = false
    @IBAction func abortBackupClicked(_ sender: NSMenuItem) {
        guard let task = backupTask, isRunning else {
            print("DEBUG: Abort backup clicked but no backup is currently in progress.")
            notifyUser(title: "Abort Ignored", informativeText: "No backup is currently in progress.")
            return
        }
        
        isUserInitiatedAbort = true
        task.terminate()
        isRunning = false
        NotificationCenter.default.post(name: .backupDidFinish, object: nil)  // Notify that backup finished

        // Log the user-aborted backup with correct date format
        let logFilePath = "\(NSHomeDirectory())/delorean.log"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let logEntry = "\(dateFormatter.string(from: Date())) - Backup Failed: User aborted\n"

        do {
            var logContent = try String(contentsOfFile: logFilePath, encoding: .utf8)
            logContent += logEntry
            try logContent.write(toFile: logFilePath, atomically: true, encoding: .utf8)
        } catch {
            print("DEBUG: Failed to log user-aborted backup: \(error)")
        }

        notifyUser(title: "Backup Aborted", informativeText: "The backup process has been cancelled.")
    }
    
    func notifyUser(title: String, informativeText: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = informativeText
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("DEBUG: Error posting notification: \(error.localizedDescription)")
            }
        }
    }
    
    @IBAction func quitClicked(sender: NSMenuItem) {
        if isRunning && !closeDialog() {
            return
        }
        NSApplication.shared.terminate(self)
    }
    
    func closeDialog() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Sync is running"
        alert.informativeText = "It appears a process is still running."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Close anyway")
        alert.addButton(withTitle: "Cancel")
        
        let result = alert.runModal()
        if result == .alertFirstButtonReturn {
            if let task = backupTask {
                task.terminate()
            }
            return true
        }
        return false
    }

    func updateUIForBackupStart() {
        DispatchQueue.main.async {
            print("DEBUG: Updating UI for backup start.")
            self.isRunning = true
            self.setupInitialMenuState()
        }
    }

    func updateUIForBackupEnd() {
        DispatchQueue.main.async {
            print("DEBUG: Updating UI for backup end.")
            self.isRunning = false
            self.setupInitialMenuState()
            self.updateLastBackupItem()
        }
    }
    
    func updateLastBackupItem() {
        let logFilePath = "\(NSHomeDirectory())/delorean.log"
        
        guard FileManager.default.fileExists(atPath: logFilePath) else {
            lastBackupItem.title = "Last Backup: No backups found"
            return
        }
        
        do {
            let logContent = try String(contentsOfFile: logFilePath, encoding: .utf8)
            let logEntries = logContent.components(separatedBy: "\n").filter { !$0.isEmpty }
            
            if let lastSuccessfulBackup = logEntries.reversed().first(where: { $0.contains("Backup completed successfully") }) {
                // Extract the date string from the log entry
                let components = lastSuccessfulBackup.components(separatedBy: " - ")
                if components.count > 1 {
                    let dateStr = components[0].trimmingCharacters(in: .whitespaces)
                    let displayDate = formatDate(dateStr: dateStr)
                    lastBackupItem.title = "Last Backup: \(displayDate)"
                } else {
                    lastBackupItem.title = "Last Backup: No successful backups found"
                }
            } else {
                lastBackupItem.title = "Last Backup: No successful backups found"
            }
        } catch {
            lastBackupItem.title = "Last Backup: Error reading log"
            print("DEBUG: Failed to read log file: \(error)")
        }
    }

    func formatDate(dateStr: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.timeZone = TimeZone.current
        
        if let date = dateFormatter.date(from: dateStr) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "MMMM d, h:mm a"
            displayFormatter.timeZone = TimeZone.current
            return displayFormatter.string(from: date)
        } else {
            return dateStr
        }
    }
}
