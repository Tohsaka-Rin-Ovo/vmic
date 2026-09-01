import SwiftUI

struct UnsupportedOSView: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager

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
                    Text(injectionManager.permissionState.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(VmicTheme.ink)
                        .multilineTextAlignment(.center)

                    Text(injectionManager.permissionState.detail)
                        .font(.body)
                        .foregroundStyle(VmicTheme.mutedInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                injectionManager.openSoftwareUpdateSettings()
            } label: {
                Label("Open Software Update", systemImage: "gear.badge")
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
