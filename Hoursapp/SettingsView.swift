import SwiftUI

struct SettingsView: View {
    @AppStorage(PrefKey.launchAtLogin) private var launchAtLogin = false
    @AppStorage(PrefKey.idleDetectionEnabled) private var idleDetectionEnabled = true
    @AppStorage(PrefKey.idleThresholdMinutes) private var idleThresholdMinutes = 45

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
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 240)
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}

#Preview {
    SettingsView()
}
