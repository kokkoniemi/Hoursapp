import SwiftUI

struct SettingsView: View {
    @AppStorage(PrefKey.launchAtLogin) private var launchAtLogin = false
    @AppStorage(PrefKey.idleDetectionEnabled) private var idleDetectionEnabled = true
    @AppStorage(PrefKey.idleThresholdMinutes) private var idleThresholdMinutes = 45
    @AppStorage(PrefKey.pauseOnSleep) private var pauseOnSleep = true
    @AppStorage(PrefKey.longRunWarningEnabled) private var longRunWarningEnabled = true
    @AppStorage(PrefKey.longRunWarningHours) private var longRunWarningHours = 8

    var body: some View {
        Form {
            Section {
                Toggle("Launch Hoursapp at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LaunchAtLogin.set(newValue)
                    }
            }

            Section("Idle detection") {
                Toggle("Prompt when idle while a timer is running", isOn: $idleDetectionEnabled)

                HStack {
                    Text("Idle threshold")
                    Spacer()
                    Text("\(idleThresholdMinutes) min")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Stepper("", value: $idleThresholdMinutes, in: 5...240, step: 5)
                        .labelsHidden()
                }
                .disabled(!idleDetectionEnabled)
            }

            Section("Sleep / wake") {
                Toggle("Prompt on wake to subtract sleep time from a running timer", isOn: $pauseOnSleep)
                Text("Uses the idle threshold above. Below it, the sleep is ignored.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Long-running timer") {
                Toggle("Warn when a timer runs for too long", isOn: $longRunWarningEnabled)

                HStack {
                    Text("Warning threshold")
                    Spacer()
                    Text("\(longRunWarningHours) hours")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Stepper("", value: $longRunWarningHours, in: 1...24, step: 1)
                        .labelsHidden()
                }
                .disabled(!longRunWarningEnabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 440)
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}

#Preview {
    SettingsView()
}
