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
    var allowBackupCheck: Bool = true
    var backupTask: Process?
    static let shared = StatusMenuController()
    
    // MARK: - Awake and Menu Setup
    override func awakeFromNib() {
        super.awakeFromNib()
        setupMenuIcon()
        setupInitialMenuState()
        
        NotificationCenter.default.removeObserver(self, name: .backupDidStart, object: nil)
        NotificationCenter.default.removeObserver(self, name: .backupDidFinish, object: nil)
        NotificationCenter.default.removeObserver(self, name: Notification.Name("StartBackup"), object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidStart), name: .backupDidStart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidFinish), name: .backupDidFinish, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(startBackupFromNotification(_:)), name: Notification.Name("StartBackup"), object: nil)
    }
    
    @objc func startBackupFromNotification(_ notification: Notification) {
        guard !isRunning else {
            notifyUser(title: "Process is still running", informativeText: "A backup process is already in progress.")
            return
        }
        
        if let task = backupTask, task.isRunning {
            notifyUser(title: "Backup in Progress", informativeText: "A backup is already in progress. Please wait for it to complete.")
            return
        }
        
        if let scriptPath = notification.userInfo?["scriptPath"] as? String {
            isRunning = true
            updateUIForBackupStart()
            backupTask = Process()
            backupTask?.launchPath = "/bin/bash"
            backupTask?.arguments = [scriptPath]
            
            backupTask?.terminationHandler = { [weak self] process in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    
                    let success = process.terminationStatus == 0
                    if success {
                        self.notifyUser(title: "Sync Completed", informativeText: "Your files have been successfully backed up.")
                    } else {
                        self.notifyUser(title: "Sync Failed", informativeText: "There was an issue with the backup process.")
                    }
                    
                    self.isRunning = false
                    self.updateUIForBackupEnd()  // Ensure UI is updated properly
                }
            }
            
            do {
                try backupTask?.run()
            } catch {
                notifyUser(title: "Error", informativeText: "Failed to start the backup process.")
                isRunning = false
                updateUIForBackupEnd()
            }
        }
    }
    
    @objc func backupDidStart() {
        updateUIForBackupStart()
    }
    
    @objc func backupDidFinish() {
        updateUIForBackupEnd()
    }

    func setupMenuIcon() {
        let icon = NSImage(named: NSImage.refreshFreestandingTemplateName)
        icon?.isTemplate = true
        statusItem.button?.image = icon
        statusItem.menu = statusMenu
    }
    
    func setupInitialMenuState() {
        startBackupItem.isHidden = false
        abortBackupItem.isHidden = true
        backupInProgressItem.isHidden = true
        backupInProgressItem.isEnabled = false
        updateLastBackupTime()
        lastBackupItem.isEnabled = false  // Make last backup item non-interactive
        lastBackupItem.isHidden = isRunning  // Hide last backup item if backup is in progress
    }
    
    // MARK: - Actions
    @IBAction func startBackupClicked(_ sender: NSMenuItem) {
        guard !isRunning else {
            notifyUser(title: "Process is still running", informativeText: "A backup process is already in progress.")
            return
        }
        
        isRunning = true
        startBackupItem.isHidden = true
        abortBackupItem.isHidden = false
        abortBackupItem.isEnabled = true
        backupInProgressItem.isHidden = false
        backupInProgressItem.isEnabled = false
        lastBackupItem.isHidden = true  // Hide last backup item during backup
        
        notifyUser(title: "Backup Starting", informativeText: "Your backup has started and will continue in the background.")
        
        backupTask = Process()
        backupTask?.launchPath = "/bin/bash"
        backupTask?.arguments = [Bundle.main.path(forResource: "sync_files", ofType: "sh")!]
        
        backupTask?.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let weakSelf = self else { return }
                weakSelf.isRunning = false
                weakSelf.updateUIForBackupEnd()
                
                let success = process.terminationStatus == 0
                weakSelf.updateBackupLog(success: success)
                weakSelf.notifyUser(title: success ? "Sync Completed" : "Sync Failed",
                                    informativeText: success ? "Your files have been successfully backed up." : "There was an issue with the backup process.")
            }
        }
        
        do {
            try backupTask?.run()
        } catch {
            notifyUser(title: "Error", informativeText: "Failed to start the backup process.")
            isRunning = false
            updateUIForBackupEnd()
        }
    }
    
    @IBAction func abortBackupClicked(_ sender: NSMenuItem) {
        guard let task = backupTask, isRunning else {
            notifyUser(title: "Abort Ignored", informativeText: "No backup is currently in progress.")
            return
        }
        
        task.terminate()
        
        isRunning = false
        updateUIForBackupEnd()
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
                print("Error posting notification: \(error.localizedDescription)")
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
            self.isRunning = true
            self.startBackupItem.isHidden = true
            self.abortBackupItem.isHidden = false
            self.abortBackupItem.isEnabled = true
            self.backupInProgressItem.isHidden = false
            self.lastBackupItem.isHidden = true  // Hide last backup item during backup
            NotificationCenter.default.post(name: .backupDidStart, object: nil)
        }
    }

    func updateUIForBackupEnd() {
        DispatchQueue.main.async {
            self.isRunning = false
            self.setupInitialMenuState()
            NotificationCenter.default.post(name: .backupDidFinish, object: nil)
        }
    }

    func updateBackupLog(success: Bool) {
        let logPath = "/Volumes/SFA-All/User Data/\(NSUserName())/backup_log.txt"
        let logEntry = "\(dateFormatter.string(from: Date()))\n"  // Removed status part
        
        do {
            if FileManager.default.fileExists(atPath: logPath) {
                let fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
                fileHandle.seekToEndOfFile()
                fileHandle.write(logEntry.data(using: .utf8)!)
                fileHandle.closeFile()
            } else {
                try logEntry.write(toFile: logPath, atomically: true, encoding: .utf8)
            }
        } catch {
            print("Failed to write to log file: \(error)")
        }
    }
    
    func updateLastBackupTime() {
        guard let lastBackupItem = lastBackupItem else {
            print("lastBackupItem is not connected")
            return
        }
        
        let logPath = "/Volumes/SFA-All/User Data/\(NSUserName())/backup_log.txt"
        
        do {
            let logContent = try String(contentsOfFile: logPath, encoding: .utf8)
            if let lastEntry = logContent.components(separatedBy: "\n").filter({ !$0.isEmpty }).last {
                lastBackupItem.title = "Last Backup: \(lastEntry)"
            } else {
                lastBackupItem.title = "Last Backup: N/A"
            }
        } catch {
            lastBackupItem.title = "Last Backup: N/A"
            print("Failed to read log file: \(error)")
        }
        lastBackupItem.isEnabled = false  // Make last backup item non-interactive
    }
}
