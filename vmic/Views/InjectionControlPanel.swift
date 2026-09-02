import SwiftUI

struct InjectionControlPanel: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let openDebug: (DebugFocusTarget) -> Void

    private var diagnosticText: String {
        if injectionManager.isInjectionAvailableInCurrentCall && injectionManager.isInjectionEnabled {
            return settingsStore.text(.diagnosticReady)
        }

        if injectionManager.isInjectionAvailableInCurrentCall {
            return settingsStore.text(.diagnosticEnableSwitch)
        }

        if injectionManager.isInjectionEnabled {
            return settingsStore.text(.diagnosticNotCompatible)
        }

        return settingsStore.text(.diagnosticWaitingForCall)
    }

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
                    Text(settingsStore.text(.callRoute))
                        .font(.headline)
                        .foregroundStyle(VmicTheme.ink)

                    Text(injectionManager.permissionState.detail(using: settingsStore))
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
                .disabled(!injectionManager.permissionState.canEnableInjection || injectionManager.isChangingInjectionMode)
            }

            HStack(spacing: 12) {
                Button {
                    openDebug(.permission)
                } label: {
                    StatusPill(
                        title: settingsStore.text(.systemPermission),
                        value: injectionManager.permissionState.canEnableInjection ? settingsStore.text(.available) : settingsStore.text(.unavailable),
                        systemImage: injectionManager.permissionState.canEnableInjection ? "checkmark.circle.fill" : "exclamationmark.circle",
                        tint: injectionManager.permissionState.canEnableInjection ? VmicTheme.mint : VmicTheme.mutedInk
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(settingsStore.text(.systemPermission))

                Button {
                    openDebug(.channel)
                } label: {
                    StatusPill(
                        title: settingsStore.text(.injectionChannel),
                        value: injectionManager.isInjectionAvailableInCurrentCall ? settingsStore.text(.available) : settingsStore.text(.unavailable),
                        systemImage: injectionManager.isInjectionAvailableInCurrentCall ? "phone.fill" : "phone",
                        tint: injectionManager.isInjectionAvailableInCurrentCall ? VmicTheme.mint : VmicTheme.mutedInk
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(settingsStore.text(.injectionChannel))

                Button {
                    Task {
                        await injectionManager.setInjectionEnabled(!injectionManager.isInjectionEnabled)
                    }
                } label: {
                    StatusPill(
                        title: settingsStore.text(.injectionSwitch),
                        value: injectionManager.isInjectionEnabled ? settingsStore.text(.enabled) : settingsStore.text(.disabled),
                        systemImage: injectionManager.isInjectionEnabled ? "waveform.badge.plus" : "waveform",
                        tint: injectionManager.isInjectionEnabled ? VmicTheme.blue : VmicTheme.mutedInk
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .disabled(injectionManager.isChangingInjectionMode)
                .accessibilityLabel(settingsStore.text(.injectionSwitch))
            }

            InputVolumeControl()

            Text(diagnosticText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(VmicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)

            if let pendingMode = injectionManager.pendingInjectionMode {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)

                    Text(settingsStore.text(pendingMode ? .turningOnInjection : .turningOffInjection))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(VmicTheme.ink)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(VmicTheme.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if let result = injectionManager.lastModeChangeResult {
                InjectionModeResultBanner(result: result, timestamp: injectionManager.lastModeChangeResultAt)
            }

            Button {
                openDebug(.overview)
            } label: {
                Label(settingsStore.text(.debug), systemImage: "stethoscope")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(VmicTheme.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(VmicTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        }
    }
}

private struct InputVolumeControl: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(settingsStore.text(.inputVolume), systemImage: "speaker.wave.2")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(VmicTheme.ink)

                Spacer()

                Text(settingsStore.text(.volumePercent(Int((settingsStore.inputVolume * 100).rounded()))))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VmicTheme.mutedInk)
                    .monospacedDigit()
            }

            Slider(value: $settingsStore.inputVolume, in: 0...1)
                .tint(VmicTheme.blue)
        }
        .padding(12)
        .background(VmicTheme.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct StatusPill: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.medium))
                .foregroundStyle(tint)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(VmicTheme.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
