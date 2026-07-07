import Foundation
import UserNotifications

enum Notifier {
    private static let runningFromBundle = Bundle.main.bundlePath.hasSuffix(".app")

    /// Ask for notification permission once, at launch. Requesting lazily in
    /// the first post() raced the permission prompt: authorization came back
    /// false while the prompt was still on screen, and the old osascript
    /// fallback then posted a banner misattributed to Script Editor.
    static func bootstrap() {
        guard runningFromBundle else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    static func post(_ message: String, title: String = "GitHub Touch") {
        if runningFromBundle {
            // Never route through osascript here — its banners carry the
            // Script Editor icon. If permission was declined, stay silent;
            // the menu state still shows everything.
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = message
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        } else {
            // Bare-binary dev runs have no bundle identity for UserNotifications.
            DispatchQueue.global().async {
                let escaped = message
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", "display notification \"\(escaped)\" with title \"\(title)\""]
                try? process.run()
            }
        }
    }

    /// --test-notify support: request permission synchronously, post a banner,
    /// and report the authorization status (mirrors ssh-touch-add).
    static func testNotify() -> Never {
        guard runningFromBundle else {
            print("running as bare CLI; only the osascript fallback is available")
            post("osascript fallback banner (no app icon possible)")
            Thread.sleep(forTimeInterval: 1)
            exit(0)
        }
        let center = UNUserNotificationCenter.current()
        let wait = DispatchSemaphore(value: 0)
        var granted = false
        center.requestAuthorization(options: [.alert]) { ok, _ in
            granted = ok
            wait.signal()
        }
        _ = wait.wait(timeout: .now() + 30)
        post("If this banner shows the GitHub Touch icon, attribution works.")
        var status = "unknown"
        let statusWait = DispatchSemaphore(value: 0)
        center.getNotificationSettings { settings in
            status = ["notDetermined", "denied", "authorized", "provisional", "ephemeral"][settings.authorizationStatus.rawValue]
            statusWait.signal()
        }
        _ = statusWait.wait(timeout: .now() + 5)
        Thread.sleep(forTimeInterval: 1)  // let delivery land before exiting
        print("authorization granted: \(granted), status: \(status)")
        exit(0)
    }
}
