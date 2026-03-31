import Foundation
import IOKit.pwr_mgt
import UserNotifications
import Combine

@MainActor
final class ServerModeManager: ObservableObject {
    @Published var isActive: Bool = false
    @Published var countdownRemaining: Int? = nil

    weak var hotkeyManager: HotkeyManager?

    private var assertionID: IOPMAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
    private var countdownTimer: Timer?

    var displaySleepDelay: Int {
        let val = UserDefaults.standard.integer(forKey: "displaySleepDelay")
        return val > 0 ? val : 30
    }

    func toggle() {
        if isActive {
            deactivate()
        } else {
            activate()
        }
    }

    func activate() {
        guard !isActive else { return }

        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "ServerMode — Preventing system sleep" as CFString,
            &assertionID
        )

        guard result == kIOReturnSuccess else {
            postErrorNotification("Failed to create sleep prevention assertion (error \(result))")
            return
        }

        isActive = true

        let delay = displaySleepDelay
        if delay == 0 {
            sleepDisplays()
        } else {
            startCountdown(seconds: delay)
        }
    }

    func deactivate() {
        cancelCountdown()

        if assertionID != IOPMAssertionID(kIOPMNullAssertionID) {
            IOPMAssertionRelease(assertionID)
            assertionID = IOPMAssertionID(kIOPMNullAssertionID)
        }

        wakeDisplays()
        isActive = false
        countdownRemaining = nil
    }

    // MARK: - Display Control

    private func sleepDisplays() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        do {
            try process.run()
        } catch {
            postErrorNotification("Failed to sleep displays: \(error.localizedDescription)")
        }
    }

    private func wakeDisplays() {
        var activityAssertionID: IOPMAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
        let result = IOPMAssertionDeclareUserActivity(
            "ServerMode — Waking displays" as CFString,
            kIOPMUserActiveLocal,
            &activityAssertionID
        )
        if result != kIOReturnSuccess {
            postErrorNotification("Failed to wake displays (error \(result))")
        }
    }

    // MARK: - Countdown

    private func startCountdown(seconds: Int) {
        countdownRemaining = seconds

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.tickCountdown()
            }
        }
    }

    private func tickCountdown() {
        guard var remaining = countdownRemaining else {
            countdownTimer?.invalidate()
            countdownTimer = nil
            return
        }

        remaining -= 1

        if remaining <= 3 && remaining > 0 {
            postCountdownNotification(seconds: remaining)
        }

        if remaining <= 0 {
            countdownTimer?.invalidate()
            countdownTimer = nil
            countdownRemaining = nil
            sleepDisplays()
        } else {
            countdownRemaining = remaining
        }
    }

    private func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownRemaining = nil
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["servermode-countdown"])
    }

    // MARK: - Notifications

    private func postCountdownNotification(seconds: Int) {
        let content = UNMutableNotificationContent()
        content.title = "ServerMode"
        content.body = "Displays turning off in \(seconds)..."
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "servermode-countdown",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func postErrorNotification(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "ServerMode Error"
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "servermode-error-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
