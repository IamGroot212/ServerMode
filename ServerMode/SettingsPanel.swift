import SwiftUI
import AppKit

struct ShortcutRecorderPanel: View {
    let hotkeyManager: HotkeyManager

    @State private var isRecording = false
    @State private var currentKeyCode: UInt16
    @State private var currentModifiers: NSEvent.ModifierFlags
    @State private var localMonitor: Any?

    init(hotkeyManager: HotkeyManager) {
        self.hotkeyManager = hotkeyManager
        _currentKeyCode = State(initialValue: hotkeyManager.keyCode)
        _currentModifiers = State(initialValue: hotkeyManager.modifierFlags)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Global Keyboard Shortcut")
                .font(.headline)

            Text("This shortcut toggles Server Mode from anywhere.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Text("Shortcut:")

                Button(action: { startRecording() }) {
                    Text(isRecording ? "Press a key combo..." : shortcutString(keyCode: currentKeyCode, modifierFlags: currentModifiers))
                        .frame(minWidth: 120)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)

                if isRecording {
                    Button("Cancel") {
                        stopRecording()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }

            if !hotkeyManager.isAccessibilityGranted {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Accessibility permission required for global shortcut")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                Button("Grant Accessibility Access") {
                    hotkeyManager.promptAccessibility()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider()

            HStack {
                Spacer()
                Button("Save") {
                    hotkeyManager.updateShortcut(keyCode: currentKeyCode, modifierFlags: currentModifiers)
                    closePanel()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Require at least one modifier
            let hasModifier = flags.contains(.command) || flags.contains(.control)
                || flags.contains(.option) || (flags.contains(.shift) && (flags.contains(.command) || flags.contains(.control) || flags.contains(.option)))

            guard hasModifier else { return event }

            // Ignore bare modifier keys
            if event.keyCode == 55 || event.keyCode == 56 || event.keyCode == 58
                || event.keyCode == 59 || event.keyCode == 54 || event.keyCode == 60
                || event.keyCode == 61 || event.keyCode == 62
            {
                return event
            }

            Task { @MainActor in
                currentKeyCode = event.keyCode
                currentModifiers = flags
                stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
    }

    private func closePanel() {
        NSApp.keyWindow?.close()
    }
}
