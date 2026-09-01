import SwiftUI

struct SetupGateView: View {
    let systemImage: String
    let title: String
    let message: String
    let primaryTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(VmicTheme.paleBlue)
                        .frame(width: 86, height: 86)

                    Image(systemName: systemImage)
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(VmicTheme.blue)
                }

                VStack(spacing: 8) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(VmicTheme.ink)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.body)
                        .foregroundStyle(VmicTheme.mutedInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: action) {
                Label(primaryTitle, systemImage: "arrow.up.forward.app")
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
