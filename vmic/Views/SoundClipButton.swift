import SwiftUI

struct SoundClipButton: View {
    let clip: SoundClip
    let isActive: Bool
    let play: () -> Void
    let delete: () -> Void

    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isActive ? VmicTheme.blue.opacity(0.14) : Color.white.opacity(0.70))
                            .frame(width: 46, height: 46)

                        Image(systemName: isActive ? "speaker.wave.3.fill" : "waveform")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(isActive ? VmicTheme.blue : VmicTheme.ink)
                    }

                    Spacer()

                    Menu {
                        Button(role: .destructive, action: delete) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.bold))
                            .foregroundStyle(VmicTheme.mutedInk)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }

                Text(clip.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VmicTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(minHeight: 126, alignment: .topLeading)
            .background(
                isActive ? VmicTheme.paleBlue : VmicTheme.surface,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isActive ? VmicTheme.blue : Color.white.opacity(0.72), lineWidth: isActive ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play \(clip.title)")
    }
}
