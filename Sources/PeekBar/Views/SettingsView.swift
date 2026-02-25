import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable var settings: PeekBarSettings
    @State private var startOnLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PeekBar Settings")
                .font(.headline)

            Toggle("Start on Login", isOn: $startOnLogin)
                .onChange(of: startOnLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        startOnLogin = !newValue
                    }
                }

            Divider()

            HStack {
                Text("Font Size")
                Spacer()
                TextField("", value: $settings.fontSize, format: .number)
                    .frame(width: 50)
                    .textFieldStyle(.roundedBorder)
                Stepper("", value: $settings.fontSize, in: 6...36, step: 1)
                    .labelsHidden()
                Text("pt")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Spacing")
                Spacer()
                TextField("", value: $settings.thumbnailSpacing, format: .number)
                    .frame(width: 50)
                    .textFieldStyle(.roundedBorder)
                Stepper("", value: $settings.thumbnailSpacing, in: 0...40, step: 1)
                    .labelsHidden()
                Text("px")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Thumb Width")
                Spacer()
                TextField("", value: $settings.thumbnailWidth, format: .number)
                    .frame(width: 50)
                    .textFieldStyle(.roundedBorder)
                Stepper("", value: $settings.thumbnailWidth, in: 80...400, step: 10)
                    .labelsHidden()
                Text("px")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Thumb Height")
                Spacer()
                TextField("", value: $settings.thumbnailHeight, format: .number)
                    .frame(width: 50)
                    .textFieldStyle(.roundedBorder)
                Stepper("", value: $settings.thumbnailHeight, in: 50...300, step: 10)
                    .labelsHidden()
                Text("px")
                    .foregroundColor(.secondary)
            }

            Divider()

            Button("Quit PeekBar") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}
