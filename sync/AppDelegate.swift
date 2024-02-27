//  AppDelegate.swift
//  sync
//
//  Created by Jonas Drotleff on 02.01.19.
//  Updated to handle user notifications effectively.

import Cocoa
import UserNotifications

// Main class for handling application lifecycle events and notifications.
@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    // Called when the application has finished launching.
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Set this instance as the delegate for the user notification center.
        // This allows the app to respond to notifications and to request permissions.
        UNUserNotificationCenter.current().delegate = self
        
        // Request authorization from the user to show notifications.
        // This is necessary to send notifications for events like backup start or completion.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            // Log the result of the permission request.
            print("Notification permission granted: \(granted)")
            
            // If permission was granted, send a test notification.
            // This helps to verify that notifications are working correctly.
            if granted {
                DispatchQueue.main.async {
                    self.sendTestNotification() // Call the method to send a test notification.
                }
            }
        }
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
