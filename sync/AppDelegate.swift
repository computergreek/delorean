//  AppDelegate.swift
//  sync
//
//  Created by Jonas Drotleff on 02.01.19.
//  Updated to handle user notifications effectively.

import Cocoa
import UserNotifications

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            print("Notification permission granted: \(granted)")
            if granted {
                DispatchQueue.main.async {
                    self.sendTestNotification()
                }
            }
        }
        setupBackupSchedule()
    }

    private func setupBackupSchedule() {
        let fileManager = FileManager.default
        let plistPath = "\(NSHomeDirectory())/Library/LaunchAgents/com.emit.delorean.plist"
        
        // Attempt to locate the backupCheck.sh script in the application's resources
        guard let scriptPath = Bundle.main.path(forResource: "backupCheck", ofType: "sh") else {
            print("Unable to find the backupCheck.sh script in the app bundle.")
            return
        }

        var needsUpdate = true

        if fileManager.fileExists(atPath: plistPath) {
            let existingPlistContent = try? String(contentsOfFile: plistPath, encoding: .utf8)
            let intendedPlistContent = self.intendedPlistContent(scriptPath: scriptPath)
            needsUpdate = (existingPlistContent != intendedPlistContent)
        }

        if needsUpdate {
            do {
                try self.intendedPlistContent(scriptPath: scriptPath).write(toFile: plistPath, atomically: true, encoding: .utf8)

                // Load the plist into launchd
                let task = Process()
                task.launchPath = "/bin/launchctl"
                task.arguments = ["load", plistPath]
                task.launch()
            } catch {
                print("Error setting up backup schedule: \(error)")
            }
        }
    }

    private func intendedPlistContent(scriptPath: String) -> String {
        // This function returns the XML content for the launch agent plist
        // It uses the provided scriptPath for the backup script
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.emit.delorean</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/bash</string>
                <string>\(scriptPath)</string>
                <string>automated</string>  <!-- This is new, indicating an automated backup -->
            </array>
            <key>StartCalendarInterval</key>
            <array>
                <dict>
                    <key>Hour</key>
                    <integer>9</integer>
                    <key>Minute</key>
                    <integer>0</integer>
                </dict>
            </array>
        </dict>
        </plist>
        """
    }

    // Called when the application is about to terminate.
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application if needed.
    }

    // Method to handle notification when the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Ensure notifications are displayed as banners even when the app is active.
        // This allows users to see important notifications anytime.
        completionHandler([.banner, .sound])
    }

    // Method to handle the user's response to the notification (e.g., clicking it).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle the user's interaction with the notification here.
        // For now, we just complete the handler as there are no specific actions defined.
        completionHandler()
    }
    
    // Private method to send a test notification.
    // This is used to verify that notification functionality is working correctly.
    private func sendTestNotification() {
        // Define the content of the notification.
        let content = UNMutableNotificationContent()
        content.title = "Test Notification"
        content.body = "This is a test notification from the app."
        content.sound = UNNotificationSound.default

        // Create the request for the notification.
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

        // Add the request to the notification center to schedule the notification.
        UNUserNotificationCenter.current().add(request) { error in
            // Log any errors that occurred when scheduling the notification.
            if let error = error {
                print("Error sending test notification: \(error.localizedDescription)")
            }
        }
    }
}
