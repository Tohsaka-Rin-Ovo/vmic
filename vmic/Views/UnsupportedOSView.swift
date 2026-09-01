import SwiftUI

struct UnsupportedOSView: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var settingsStore: AppSettingsStore

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(VmicTheme.paleBlue)
                        .frame(width: 86, height: 86)

                    Image(systemName: "iphone")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(VmicTheme.blue)
                }

                VStack(spacing: 8) {
                    Text(injectionManager.permissionState.title(using: settingsStore))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(VmicTheme.ink)
                        .multilineTextAlignment(.center)

                    Text(injectionManager.permissionState.detail(using: settingsStore))
                        .font(.body)
                        .foregroundStyle(VmicTheme.mutedInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                injectionManager.openSoftwareUpdateSettings()
            } label: {
                Label(settingsStore.text(.openSoftwareUpdate), systemImage: "gear.badge")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BlueProminentButtonStyle())
            .controlSize(.large)
        }
        .padding(28)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
