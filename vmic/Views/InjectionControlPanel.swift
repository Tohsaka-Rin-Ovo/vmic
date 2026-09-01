import SwiftUI

struct InjectionControlPanel: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(VmicTheme.blue.opacity(0.10))
                        .frame(width: 44, height: 44)

                    Image(systemName: "phone.and.waveform")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(VmicTheme.blue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Call Route")
                        .font(.headline)
                        .foregroundStyle(VmicTheme.ink)

                    Text(injectionManager.permissionState.detail)
                        .font(.subheadline)
                        .foregroundStyle(VmicTheme.mutedInk)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Toggle("", isOn: Binding(
                    get: {
                        injectionManager.isInjectionEnabled
                    },
                    set: { newValue in
                        Task {
                            await injectionManager.setInjectionEnabled(newValue)
                        }
                    }
                ))
                .labelsHidden()
                .tint(VmicTheme.blue)
                .disabled(!injectionManager.permissionState.canEnableInjection)
            }

            HStack(spacing: 12) {
                StatusPill(
                    title: injectionManager.isInjectionAvailableInCurrentCall ? "Call Detected" : "No Supported Call",
                    systemImage: injectionManager.isInjectionAvailableInCurrentCall ? "phone.fill" : "phone",
                    tint: injectionManager.isInjectionAvailableInCurrentCall ? VmicTheme.mint : VmicTheme.mutedInk
                )

                StatusPill(
                    title: injectionManager.isInjectionEnabled ? "Injecting" : "Injection Off",
                    systemImage: injectionManager.isInjectionEnabled ? "waveform.badge.plus" : "waveform",
                    tint: injectionManager.isInjectionEnabled ? VmicTheme.blue : VmicTheme.mutedInk
                )
            }
        }
        .padding(16)
        .background(VmicTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        }
    }
}

private struct StatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
