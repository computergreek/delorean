import Cocoa
import UserNotifications

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var backupTimer: Timer?
    var backupHour = "09"
    var backupMinute = "00"
    var rangeStart = "07"
    var rangeEnd = "19"
    var frequency: TimeInterval = 3600  // Default to checking every hour.

    // MARK: - App Lifecycle
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
        }
        loadConfig()
        startBackupTimer()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        backupTimer?.invalidate()
    }

    // MARK: - Backup Configuration and Schedule
//    private func loadConfig() {
//        // Assuming 'sync_files.sh' is within the app bundle
//        guard let scriptPath = Bundle.main.path(forResource: "sync_files", ofType: "sh") else {
//            print("Failed to locate sync_files.sh")
//            return
//        }
//
//        let command = "grep '^backup_' \(scriptPath) | grep -v '^#' | tr -d '\"' | tr -d ' '"
//        executeShellCommand(command) { output in
//            output.forEach { line in
//                let components = line.split(separator: "=").map { String($0) }
//                if components.count == 2 {
//                    switch components[0] {
//                    case "backup_hour": self.backupHour = components[1]
//                    case "backup_minute": self.backupMinute = components[1]
//                    case "range_start": self.rangeStart = components[1]
//                    case "range_end": self.rangeEnd = components[1]
//                    case "frequency_check": self.frequency = TimeInterval(components[1]) ?? 3600
//                    default: break
//                    }
//                }
//            }
//            // Once configuration is loaded, (re)start the timer
//            self.startBackupTimer()
//        }
//    }

    private func loadConfig() {
        guard let scriptPath = Bundle.main.path(forResource: "sync_files", ofType: "sh") else {
            print("Failed to locate sync_files.sh")
            return
        }

        let command = "source \(scriptPath); echo $scheduled_backup_time $range_start $range_end $frequency_check"
        executeShellCommand(command) { output in
            guard let line = output.first else { return }
            let components = line.split(separator: " ").map { String($0) }
            if components.count == 4 {
                let timeComponents = components[0].split(separator: ":").map { String($0) }
                if timeComponents.count == 2 {
                    self.backupHour = timeComponents[0]
                    self.backupMinute = timeComponents[1]
                }
                self.rangeStart = components[1]
                self.rangeEnd = components[2]
                if let frequency = TimeInterval(components[3]) {
                    self.frequency = frequency
                }
            }
            // Once configuration is loaded, (re)start the timer
            self.startBackupTimer()
        }
    }


    private func startBackupTimer() {
        backupTimer?.invalidate()  // Stop any existing timer.
        backupTimer = Timer.scheduledTimer(timeInterval: frequency, target: self, selector: #selector(checkBackupSchedule), userInfo: nil, repeats: true)
        checkBackupSchedule()  // Also perform an immediate check.
    }

    @objc private func checkBackupSchedule() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let currentTimeString = formatter.string(from: Date())
        let currentDate = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        
        guard let currentTime = formatter.date(from: currentTimeString),
              let rangeStart = formatter.date(from: self.rangeStart),
              let rangeEnd = formatter.date(from: self.rangeEnd),
              let backupTime = formatter.date(from: "\(self.backupHour):\(self.backupMinute)") else { return }

        let logFilePath = "/Volumes/SFA-All/User Data/\(NSUserName())/dBackup.log"
        var didRunBackupToday = false
        if let logContent = try? String(contentsOfFile: logFilePath, encoding: .utf8) {
            didRunBackupToday = logContent.contains(currentDate)
        }

        if !didRunBackupToday && currentTime >= rangeStart && currentTime <= rangeEnd {
            if currentTime >= backupTime {  // Check if past the scheduled backup time.
                performBackup()
            } else {
                print("Not yet time for scheduled backup.")
            }
        } else if didRunBackupToday {
            print("Backup already completed for today.")
        } else {
            print("Current time is outside the backup window.")
        }
    }

    private func performBackup() {
        guard let scriptPath = Bundle.main.path(forResource: "sync_files", ofType: "sh") else {
            print("Failed to locate sync_files.sh for backup")
            return
        }
        executeShellCommand("/bin/bash \(scriptPath)") { output in
            print("Backup process completed: \(output.joined(separator: "\n"))")
        }
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
    // This method is called when a notification is about to be presented while the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Here, you can choose to present the notification with a banner, sound, badge, or a combination of these.
        // For example, to present the notification as a banner with a sound, you would call the completion handler like this:
        completionHandler([.banner, .sound])
        // This allows the notification to be visible to the user even if the app is open, ensuring they are aware of the backup status or any other important information.
    }

    // This method is called when the user interacts with a notification, for example, by tapping on it.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle the user's interaction with the notification here.
        // This could involve taking specific actions like opening a particular view in your app, or simply logging the user's response.
        // For now, we'll just print out the identifier of the notification and complete the handler.
        print("User interacted with notification: \(response.notification.request.identifier)")
        completionHandler()  // Always call this when finished handling the interaction to let the system know you're done.
    }
}
