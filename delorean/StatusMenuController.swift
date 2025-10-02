import Cocoa
import UserNotifications
import QuartzCore
 
extension Notification.Name {
    static let backupDidStart = Notification.Name("backupDidStart")
    static let backupDidFinish = Notification.Name("backupDidFinish")
    static let StartBackup = Notification.Name("StartBackup")
    
    static let requestManualBackup = Notification.Name("requestManualBackup")
    static let updateLastBackupDisplay = Notification.Name("updateLastBackupDisplay")
}
 
class StatusMenuController: NSObject {
    
    // MARK: - Outlets
    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var startBackupItem: NSMenuItem!
    @IBOutlet weak var abortBackupItem: NSMenuItem!
    @IBOutlet weak var backupInProgressItem: NSMenuItem!
    @IBOutlet weak var lastBackupItem: NSMenuItem!
    private var spinTimer: Timer?
    private var currentRotation: CGFloat = 0
    private var originalIcon: NSImage?
    
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
        originalIcon = icon?.copy() as? NSImage // Store original
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
 
                // This is the improved logic.
                if self.isUserInitiatedAbort {
                    // If the user aborted, we do nothing. The "Backup Aborted"
                    // notification was already sent.
                } else {
                    // Otherwise, we check for normal success or failure.
                    let success = process.terminationStatus == 0
                    if success {
                        self.notifyUser(title: "Backup Completed", informativeText: "Your files have been successfully backed up.")
                    } else {
                        self.notifyUser(title: "Backup Failed", informativeText: "There was an issue with the backup process.")
                    }
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
    
    private func startSpinningIcon() {
        stopSpinningIcon()
        spinTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.currentRotation -= CGFloat.pi / 16
            DispatchQueue.main.async {
                if let originalImage = self.originalIcon {
                    let rotatedImage = self.rotateImage(originalImage, by: self.currentRotation)
                    rotatedImage.isTemplate = true
                    self.statusItem.button?.image = rotatedImage
                }
            }
        }
    }
    
    private func stopSpinningIcon() {
        spinTimer?.invalidate()
        spinTimer = nil
        currentRotation = 0
        
        DispatchQueue.main.async {
            if let originalImage = self.originalIcon {
                originalImage.isTemplate = true
                self.statusItem.button?.image = originalImage
            }
        }
    }
    
    // Optimized rotation to minimize pulsing
    private func rotateImage(_ image: NSImage, by angle: CGFloat) -> NSImage {
        let size = image.size
        let rotatedImage = NSImage(size: size)
        
        rotatedImage.lockFocus()
        
        // High quality rendering
        if let context = NSGraphicsContext.current {
            context.imageInterpolation = .high
            context.shouldAntialias = true
        }
        
        // Transform around center
        let transform = NSAffineTransform()
        transform.translateX(by: size.width / 2, yBy: size.height / 2)
        transform.rotate(byRadians: angle)
        transform.translateX(by: -size.width / 2, yBy: -size.height / 2)
        transform.concat()
        
        // Draw image - simple approach
        image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
        
        rotatedImage.unlockFocus()
        return rotatedImage
    }
    
    @objc func backupDidStart() {
        print("DEBUG: backupDidStart called")
        isRunning = true
        startSpinningIcon()
        updateUIForStateChange()
    }
    
    @objc func backupDidFinish() {
        isRunning = false
        stopSpinningIcon()
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
        
        // Terminate the bash script (which will kill the rsync process)
        task.terminate()
        
        // Log the abort in Swift
        logUserAbort()
        
        notifyUser(title: "Backup Aborted", informativeText: "The backup process has been cancelled.")
    }
 
    // Add this new method to StatusMenuController
    private func logUserAbort() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let logEntry = "\(dateFormatter.string(from: Date())) - Backup Failed: User aborted\n"
        
        // Get log file path from AppDelegate
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            let logFilePath = appDelegate.logFilePath
            
            do {
                if let fileHandle = FileHandle(forWritingAtPath: logFilePath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(logEntry.data(using: .utf8)!)
                    fileHandle.closeFile()
                } else {
                    try logEntry.write(toFile: logFilePath, atomically: true, encoding: .utf8)
                }
            } catch {
                print("DEBUG: Failed to log user abort: \(error)")
            }
        }
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
        alert.messageText = "DeLorean is running"
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
