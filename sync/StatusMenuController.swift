import Cocoa
import UserNotifications

extension Notification.Name {
    static let backupDidStart = Notification.Name("backupDidStart")
    static let backupDidFinish = Notification.Name("backupDidFinish")
}

class StatusMenuController: NSObject {
    // MARK: - Outlets
    // Connect these outlets to the corresponding UI elements in MainMenu.xib
    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var startBackupItem: NSMenuItem!
    @IBOutlet weak var abortBackupItem: NSMenuItem!
    @IBOutlet weak var backupInProgressItem: NSMenuItem!

    // This status item will appear in the menu bar and is the entry point for user interactions.
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    // A Boolean property to track whether a backup is currently in progress.
    var isRunning: Bool = false
    // The Process instance that will run the backup script.
    var backupTask: Process?

    // MARK: - Awake and Menu Setup
    // awakeFromNib is called after the object has been loaded from the xib file.
//    override func awakeFromNib() {
//        super.awakeFromNib()
//        setupMenuIcon()
//        setupInitialMenuState()
//        NotificationCenter.default.addObserver(self, selector: #selector(backupDidStart), name: .backupDidStart, object: nil)
//        NotificationCenter.default.addObserver(self, selector: #selector(backupDidFinish), name: .backupDidFinish, object: nil)
//    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setupMenuIcon()
        setupInitialMenuState()
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidStart), name: .backupDidStart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(backupDidFinish), name: .backupDidFinish, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(startBackupFromNotification(_:)), name: Notification.Name("StartBackup"), object: nil)
    }

    @objc func startBackupFromNotification(_ notification: Notification) {
        guard !isRunning else {
            notifyUser(title: "Process is still running", informativeText: "A backup process is already in progress.")
            return
        }
        
        if let scriptPath = notification.userInfo?["scriptPath"] as? String {
            isRunning = true
            updateUIForBackupStart()

            // Prepare the backup task
            backupTask = Process()
            backupTask?.launchPath = "/bin/bash"
            backupTask?.arguments = [scriptPath]
            
            backupTask?.terminationHandler = { [weak self] process in
                DispatchQueue.main.async {
                    guard let weakSelf = self else { return }
                    weakSelf.isRunning = false
                    weakSelf.updateUIForBackupEnd()
                    let success = process.terminationStatus == 0
                    weakSelf.notifyUser(title: success ? "Sync Completed" : "Sync Failed", informativeText: success ? "Your files have been successfully backed up." : "There was an issue with the backup process.")
                    NotificationCenter.default.post(name: Notification.Name.backupDidFinish, object: nil)
                }
            }

            // Start the backup process
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
    

    // Sets up the menu bar icon for the app.
    func setupMenuIcon() {
        // Use the system-provided refresh icon for the status item.
        let icon = NSImage(named: NSImage.refreshFreestandingTemplateName)
        icon?.isTemplate = true // Allows the icon to adapt to light and dark menu bars.
        statusItem.button?.image = icon
        statusItem.menu = statusMenu
    }

    // Sets the initial state of the menu items when the app launches.
    func setupInitialMenuState() {
        startBackupItem.isHidden = false
        abortBackupItem.isHidden = true
        backupInProgressItem.isHidden = true
        backupInProgressItem.isEnabled = false
    }

    // MARK: - Actions
    // Called when the 'Start Backup' menu item is clicked.
    @IBAction func startBackupClicked(_ sender: NSMenuItem) {
        // Prevent starting a backup if one is already running.
        guard !isRunning else {
            notifyUser(title: "Process is still running", informativeText: "A backup process is already in progress.")
            return
        }

        // Set the state to indicate that a backup is in progress.
        isRunning = true
        // Update menu items for backup in progress
        startBackupItem.isHidden = true
        abortBackupItem.isHidden = false
        abortBackupItem.isEnabled = true
        backupInProgressItem.isHidden = false
        backupInProgressItem.isEnabled = false
        
        // Send a notification that the backup is starting.
        notifyUser(title: "Backup Starting", informativeText: "Your backup has started and will continue in the background.")
        
        // Prepare the backup task.
        backupTask = Process()
        backupTask?.launchPath = "/bin/bash" // The path to the bash executable.
        backupTask?.arguments = [Bundle.main.path(forResource: "sync_files", ofType: "sh")!] // The path to the backup script.

        // Handle script completion.
        backupTask?.terminationHandler = { [weak self] process in
            // Dispatch to the main thread since UI updates must be on the main thread.
            DispatchQueue.main.async {
                guard let weakSelf = self else { return }
                weakSelf.isRunning = false // Update the state to reflect that the backup is no longer running.
                // Ensure that 'Start Backup' is visible and enabled once the backup completes.
                weakSelf.startBackupItem.isHidden = false
                weakSelf.startBackupItem.isEnabled = true
                // Ensure that 'Abort Backup' and 'Backup in progress...' are hidden and 'Abort Backup' is disabled.
                weakSelf.abortBackupItem.isHidden = true
                weakSelf.abortBackupItem.isEnabled = false  // This is crucial
                weakSelf.backupInProgressItem.isHidden = true

                // Notify the user of the result based on the termination status of the script.
                let success = process.terminationStatus == 0
                weakSelf.notifyUser(title: success ? "Sync Completed" : "Sync Failed",
                                    informativeText: success ? "Your files have been successfully backed up." : "There was an issue with the backup process.")
            }
        }

        // Start the backup process.
        do {
            try backupTask?.run()
        } catch {
            // Handle any errors that occur when attempting to start the backup process.
            notifyUser(title: "Error", informativeText: "Failed to start the backup process.")
            isRunning = false // Update the state to reflect that the backup is not running.
            startBackupItem.isEnabled = true // Re-enable the start backup item.
            abortBackupItem.isEnabled = false // Disable the abort backup item.
        }
    }

    // Called when the 'Abort Backup' menu item is clicked.
    @IBAction func abortBackupClicked(_ sender: NSMenuItem) {
        // Check if there is a backup process running
        guard let task = backupTask, isRunning else {
            // If no task is running or if isRunning is false, no action is needed
            notifyUser(title: "Abort Ignored", informativeText: "No backup is currently in progress.")
            return // If there is no task running, just return.
        }

        // Terminate the backup process.
        task.terminate()

        // Update the UI to reflect that the backup process has been aborted.
        isRunning = false
        updateUIForBackupEnd()
        // Reset menu items back to initial state
        startBackupItem.isHidden = false
        abortBackupItem.isHidden = true
        backupInProgressItem.isHidden = true
        backupInProgressItem.isEnabled = false // It remains disabled
        notifyUser(title: "Backup Aborted", informativeText: "The backup process has been cancelled.")
    }

    // Sends a notification to the user using the UserNotifications framework.
    func notifyUser(title: String, informativeText: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = informativeText
        content.sound = UNNotificationSound.default // Use the default notification sound.

        // Create a unique identifier for the notification request.
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        // Schedule the notification.
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                // If there is an error scheduling the notification, log the error.
                print("Error posting notification: \(error.localizedDescription)")
            }
        }
    }

    // Called when the user selects to quit the app from the menu.
    @IBAction func quitClicked(sender: NSMenuItem) {
        // If a backup is running and the user wants to quit, show a confirmation dialog.
        if isRunning && !closeDialog() {
            return // If the user chooses not to quit, return.
        }
        // Terminate the application.
        NSApplication.shared.terminate(self)
    }

    // Displays a dialog if a backup is running and the user tries to quit.
    func closeDialog() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Sync is running"
        alert.informativeText = "It appears a process is still running."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Close anyway")
        alert.addButton(withTitle: "Cancel")
        // Show the dialog and return true if the user confirms they want to close.
        return alert.runModal() == .alertFirstButtonReturn
    }
    
    func updateUIForBackupStart() {
        DispatchQueue.main.async {
            self.startBackupItem.isHidden = true
            self.abortBackupItem.isHidden = false
            self.abortBackupItem.isEnabled = true
            self.backupInProgressItem.isHidden = false
            // Additional UI updates for backup start
        }
    }

    func updateUIForBackupEnd() {
        DispatchQueue.main.async {
            self.startBackupItem.isHidden = false
            self.abortBackupItem.isHidden = true
            self.backupInProgressItem.isHidden = true
            // Additional UI updates for backup end
        }
    }
}
