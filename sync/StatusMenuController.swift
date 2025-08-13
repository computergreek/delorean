import Cocoa
import UserNotifications

extension Notification.Name {
    static let backupDidStart = Notification.Name("backupDidStart")
    static let backupDidFinish = Notification.Name("backupDidFinish")
    static let StartBackup = Notification.Name("StartBackup")
    
    static let requestManualBackup = Notification.Name("requestManualBackup")
    static let userDidAbortBackup = Notification.Name("userDidAbortBackup")
    static let updateLastBackupDisplay = Notification.Name("updateLastBackupDisplay")
}

class StatusMenuController: NSObject {
    
    // MARK: - Outlets
    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var startBackupItem: NSMenuItem!
    @IBOutlet weak var abortBackupItem: NSMenuItem!
    @IBOutlet weak var backupInProgressItem: NSMenuItem!
    @IBOutlet weak var lastBackupItem: NSMenuItem!
    
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var isRunning: Bool = false
    var backupTask: Process?
    var isUserInitiatedAbort: Bool = false
    
    static let shared = StatusMenuController()
    
    // MARK: - Awake and Menu Setup
    override func awakeFromNib() {
        super.awakeFromNib()
        setupMenuIcon()
        updateUIForStateChange()
        
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidStart), name: .backupDidStart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidFinish), name: .backupDidFinish, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(startBackupFromNotification(_:)), name: .StartBackup, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleUpdateLastBackupDisplay(_:)), name: .updateLastBackupDisplay, object: nil)
    }
    
    func setupMenuIcon() {
        let icon = NSImage(named: NSImage.refreshFreestandingTemplateName)
        icon?.isTemplate = true
        statusItem.button?.image = icon
        statusItem.menu = statusMenu
    }
    
    func updateUIForStateChange() {
        DispatchQueue.main.async {
            self.startBackupItem.isHidden = self.isRunning
            self.abortBackupItem.isHidden = !self.isRunning
            self.backupInProgressItem.isHidden = !self.isRunning
            self.lastBackupItem.isHidden = self.isRunning
            
            self.backupInProgressItem.isEnabled = false
            self.lastBackupItem.isEnabled = false
        }
    }
    
    // MARK: - Notification Handlers
    @objc func startBackupFromNotification(_ notification: Notification) {
        guard !isRunning, let scriptPath = notification.userInfo?["scriptPath"] as? String else {
            return
        }
        
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
                self.isUserInitiatedAbort = false
                NotificationCenter.default.post(name: .backupDidFinish, object: nil)
            }
        }
        
        do {
            try backupTask?.run()
        } catch {
            notifyUser(title: "Error", informativeText: "Failed to start the backup process.")
            NotificationCenter.default.post(name: .backupDidFinish, object: nil)
        }
    }
    
    @objc func backupDidStart() {
        isRunning = true
        updateUIForStateChange()
    }
    
    @objc func backupDidFinish() {
        isRunning = false
        updateUIForStateChange()
    }
    
    @objc func handleUpdateLastBackupDisplay(_ notification: Notification) {
        if let title = notification.userInfo?["title"] as? String {
            lastBackupItem.title = title
        }
    }
    
    // MARK: - Actions
    @IBAction func startBackupClicked(_ sender: NSMenuItem) {
        guard !isRunning else {
            notifyUser(title: "Process is still running", informativeText: "A backup process is already in progress.")
            return
        }
        NotificationCenter.default.post(name: .requestManualBackup, object: nil)
    }
    
    @IBAction func abortBackupClicked(_ sender: NSMenuItem) {
        guard let task = backupTask, isRunning else {
            return
        }
        isUserInitiatedAbort = true
        task.terminate()
        notifyUser(title: "Backup Aborted", informativeText: "The backup process has been cancelled.")
    }
    
    @IBAction func quitClicked(sender: NSMenuItem) {
        if isRunning && !showQuitWarning() {
            return
        }
        NSApplication.shared.terminate(self)
    }
    
    // MARK: - Dialogs and User Notifications
    func showQuitWarning() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Sync is running"
        alert.informativeText = "A backup is currently in progress. Are you sure you want to quit?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Cancel")
        
        let result = alert.runModal()
        if result == .alertFirstButtonReturn {
            backupTask?.terminate()
            return true
        }
        return false
    }
    
    func notifyUser(title: String, informativeText: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = informativeText
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
