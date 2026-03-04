//
//  NotificationHelper.swift
//  Scarlet
//
//  Local notification utility for background events.
//

import Foundation
import UserNotifications

enum NotificationHelper {

    /// Request notification permission (call on app launch).
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Whether notifications are enabled in user preferences (defaults to true).
    static var isEnabled: Bool {
        get { !UserDefaults.standard.bool(forKey: "notifications_disabled") }
        set { UserDefaults.standard.set(!newValue, forKey: "notifications_disabled") }
    }

    /// Send a local notification (only if enabled in prefs).
    static func send(title: String, body: String) {
        guard isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
