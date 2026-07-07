import Foundation
import UserNotifications

enum Notifier {
    static func post(_ message: String, title: String = "GitHub Touch") {
        DispatchQueue.global().async {
            if postBundleNotification(message, title: title) { return }
            let escaped = message
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "display notification \"\(escaped)\" with title \"\(title)\""]
            try? process.run()
        }
    }

    private static func postBundleNotification(_ message: String, title: String) -> Bool {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return false }
        let center = UNUserNotificationCenter.current()
        var granted = false
        let authWait = DispatchSemaphore(value: 0)
        center.requestAuthorization(options: [.alert]) { ok, _ in
            granted = ok
            authWait.signal()
        }
        _ = authWait.wait(timeout: .now() + 30)
        guard granted else { return false }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        return true
    }
}
