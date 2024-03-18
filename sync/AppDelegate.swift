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
        
        // Assuming your script outputs the configuration directly when called with 'config'
        let command = "bash \(scriptPath) config"
        print("Executing command: \(command)")
        executeShellCommand(command) { [weak self] output in
            guard let self = self else { return }

            // Combine the output into a single string and then split it by new lines.
            let combinedOutput = output.joined(separator: "\n")
            let configurations = combinedOutput.components(separatedBy: CharacterSet.newlines)

            // Now 'configurations' should correctly contain separate lines.
            if configurations.count < 4 {
                print("Configuration output was unexpected or incomplete: \(configurations)")
                return
            }

            self.parseSchedulerSettings(schedulerSettings: configurations)
            DispatchQueue.main.async {
                self.startBackupTimer()
            }
        }
    }

    
    private func parseSchedulerSettings(schedulerSettings: [String]) {
        schedulerSettings.forEach { setting in
            let components = setting.split(separator: "=").map { String($0) }
            guard components.count == 2 else { return }
            switch components[0] {
            case "scheduled_backup_time":
                let timeComponents = components[1].split(separator: ":").map { String($0) }
                if timeComponents.count == 2 {
                    self.backupHour = timeComponents[0]
                    self.backupMinute = timeComponents[1]
                }
            case "range_start":
                self.rangeStart = components[1]
            case "range_end":
                self.rangeEnd = components[1]
            case "frequency_check":
                if let frequency = TimeInterval(components[1]) {
                    self.frequency = frequency
                }
            default: break
            }
        }
        print("Configuration Loaded: Backup time: \(self.backupHour):\(self.backupMinute), Range: \(self.rangeStart)-\(self.rangeEnd), Frequency: \(self.frequency) seconds")
    }


//    private func startBackupTimer() {
//        backupTimer?.invalidate()  // Stop any existing timer.
//        backupTimer = Timer.scheduledTimer(timeInterval: frequency, target: self, selector: #selector(checkBackupSchedule), userInfo: nil, repeats: true)
//        checkBackupSchedule()  // Also perform an immediate check.
//    }
    private func startBackupTimer() {
        print("Setting up backup timer with frequency: \(frequency)")
        backupTimer?.invalidate()  // Stop any existing timer.
        backupTimer = Timer.scheduledTimer(timeInterval: frequency, target: self, selector: #selector(checkBackupSchedule), userInfo: nil, repeats: true)
        print("Backup timer set and first check initiated")
        checkBackupSchedule()  // Also perform an immediate check.
    }


    @objc private func checkBackupSchedule() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }

            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let currentDate = Date()
            let currentTimeString = formatter.string(from: currentDate)

            // Define the current date in string format
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .none
            let currentDateStr = dateFormatter.string(from: currentDate)

            print("Attempting to parse current time string: \(currentTimeString)")
            print("Configured times - Scheduled: \(self.backupHour):\(self.backupMinute), Start: \(self.rangeStart), End: \(self.rangeEnd)")


            guard let currentTime = formatter.date(from: currentTimeString),
                  let rangeStartTime = formatter.date(from: self.rangeStart),
                  let rangeEndTime = formatter.date(from: self.rangeEnd),
                  let scheduledTime = formatter.date(from: "\(self.backupHour):\(self.backupMinute)") else {
                DispatchQueue.main.async {
                    if formatter.date(from: currentTimeString) == nil {
                        print("Current time string could not be parsed correctly: \(currentTimeString)")
                    }
                    if formatter.date(from: self.rangeStart) == nil {
                        print("Start time string could not be parsed correctly: \(self.rangeStart)")
                    }
                    if formatter.date(from: self.rangeEnd) == nil {
                        print("End time string could not be parsed correctly: \(self.rangeEnd)")
                    }
                    if formatter.date(from: "\(self.backupHour):\(self.backupMinute)") == nil {
                        print("Scheduled time string could not be parsed correctly: \(self.backupHour):\(self.backupMinute)")
                    }
                }
                return
            }

            // Construct the log file path and check if a backup has already been performed today.
            let logFilePath = "/Volumes/SFA-All/User Data/\(NSUserName())/dBackup.log"
            var didRunBackupToday = false
            if let logContent = try? String(contentsOfFile: logFilePath, encoding: .utf8) {
                didRunBackupToday = logContent.contains(currentDateStr)
            }

            DispatchQueue.main.async {
                // Check if current time is within the backup window and no backup has been performed today.
                if currentTime >= rangeStartTime && currentTime <= rangeEndTime && !didRunBackupToday {
                    if currentTime >= scheduledTime {
                        print("Performing scheduled backup")
                        self.performBackup()
                    } else {
                        print("It's not yet time for scheduled backup. Scheduled time is \(self.backupHour):\(self.backupMinute), current time is \(currentTimeString).")
                    }
                } else {
                    if didRunBackupToday {
                        print("Backup already completed for today.")
                    } else {
                        print("Current time is outside the backup window or other condition not met.")
                    }
                }
            }
        }
    }




//    private func performBackup() {
//        guard let scriptPath = Bundle.main.path(forResource: "sync_files", ofType: "sh") else {
//            print("Failed to locate sync_files.sh for backup")
//            return
//        }
//        executeShellCommand("/bin/bash \(scriptPath)") { output in
//            print("Backup process completed: \(output.joined(separator: "\n"))")
//        }
//    }
//    private func performBackup() {
//        print("Attempting to perform backup")
//        guard let scriptPath = Bundle.main.path(forResource: "sync_files", ofType: "sh") else {
//            print("Failed to locate sync_files.sh for backup")
//            return
//        }
//        print("Script path: \(scriptPath)")
//        executeShellCommand("/bin/bash \(scriptPath)") { output in
//            print("Backup process initiated")
//            print("Backup process completed: \(output.joined(separator: "\n"))")
//        }
//        print("performBackup function end reached")
//    }
    
    private func performBackup() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            guard let scriptPath = Bundle.main.path(forResource: "sync_files", ofType: "sh") else {
                DispatchQueue.main.async {
                    print("Failed to locate sync_files.sh for backup")
                }
                return
            }
            DispatchQueue.main.async {
                print("Attempting to perform backup")
            }
            self.executeShellCommand("/bin/bash \(scriptPath)") { output in
                DispatchQueue.main.async {
                    print("Backup process initiated")
                    print("Backup process completed: \(output.joined(separator: "\n"))")
                }
            }
        }
    }



    // MARK: - Helper Methods
//    private func executeShellCommand(_ command: String, completion: @escaping ([String]) -> Void) {
//        let process = Process()
//        let pipe = Pipe()
//
//        process.launchPath = "/bin/bash"
//        process.arguments = ["-c", command]
//        process.standardOutput = pipe
//
//        process.launch()
//
//        let data = pipe.fileHandleForReading.readDataToEndOfFile()
//        let output = String(data: data, encoding: .utf8)?.components(separatedBy: "\n").filter { !$0.isEmpty } ?? []
//        
//        completion(output)
//    }
    private func executeShellCommand(_ command: String, completion: @escaping ([String]) -> Void) {
        DispatchQueue.global(qos: .background).async {
            let process = Process()
            let pipe = Pipe()
            
            process.launchPath = "/bin/bash"
            process.arguments = ["-c", command]
            process.standardOutput = pipe
            
            let outHandle = pipe.fileHandleForReading
            outHandle.waitForDataInBackgroundAndNotify()  // Listen for data in the background
            
            var output = [String]()
            let observer = NotificationCenter.default.addObserver(forName: .NSFileHandleDataAvailable,
                                                                  object: outHandle, queue: nil) { notification in
                let data = outHandle.availableData
                if let str = String(data: data, encoding: .utf8) {
                    output.append(str)
                }
                outHandle.waitForDataInBackgroundAndNotify()  // Continue listening for data
            }
            
            process.terminationHandler = { _ in
                NotificationCenter.default.removeObserver(observer)
                DispatchQueue.main.async {
                    completion(output)
                }
            }
            
            process.launch()
            process.waitUntilExit()
        }
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
