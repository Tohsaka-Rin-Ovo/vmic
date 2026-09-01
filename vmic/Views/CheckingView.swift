import SwiftUI

struct CheckingView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(VmicTheme.paleBlue)
                    .frame(width: 86, height: 86)

                ProgressView()
                    .tint(VmicTheme.blue)
                    .scaleEffect(1.25)
            }

            Text(settingsStore.text(.checking))
                .font(.title3.weight(.semibold))
                .foregroundStyle(VmicTheme.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
