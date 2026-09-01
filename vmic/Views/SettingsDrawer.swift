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

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VmicTheme.surface)
    }
}
