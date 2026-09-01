import SwiftUI

struct SettingsDrawer: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(settingsStore.text(.settings))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(VmicTheme.ink)

                Spacer()

                Button(action: close) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(QuietIconButtonStyle())
            }

            VStack(alignment: .leading, spacing: 10) {
                Label(settingsStore.text(.language), systemImage: "globe")
                    .font(.headline)
                    .foregroundStyle(VmicTheme.ink)

                Picker(settingsStore.text(.language), selection: $settingsStore.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName)
                            .tag(language)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 14) {
                Label(settingsStore.text(.playback), systemImage: "play.circle")
                    .font(.headline)
                    .foregroundStyle(VmicTheme.ink)

                SettingsToggleRow(
                    title: settingsStore.text(.singlePlayback),
                    detail: settingsStore.text(.singlePlaybackDetail),
                    isOn: $settingsStore.singlePlayback
                )
            }

            VStack(alignment: .leading, spacing: 14) {
                Label(settingsStore.text(.list), systemImage: "list.bullet")
                    .font(.headline)
                    .foregroundStyle(VmicTheme.ink)

                SettingsToggleRow(
                    title: settingsStore.text(.showDuration),
                    detail: settingsStore.text(.showDurationDetail),
                    isOn: $settingsStore.showDuration
                )
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VmicTheme.surface)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String

    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VmicTheme.ink)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(VmicTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(VmicTheme.blue)
    }
}
