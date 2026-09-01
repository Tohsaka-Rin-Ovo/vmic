import SwiftUI
import UniformTypeIdentifiers

struct SoundboardView: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var libraryStore: SoundLibraryStore
    @EnvironmentObject private var playbackManager: AudioPlaybackManager

    @State private var isImporterPresented = false

    private let columns = [
        GridItem(.adaptive(minimum: 154, maximum: 230), spacing: 12)
    ]

    private var activeClips: [SoundClip] {
        libraryStore.clips.filter {
            playbackManager.activeClipIDs.contains($0.id)
        }
    }

    var body: some View {
        ZStack {
            VmicTheme.appBackground

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PlayerHeader(activeClips: activeClips)
                    InjectionControlPanel()

                    if let error = injectionManager.lastError ?? libraryStore.lastError ?? playbackManager.lastError {
                        ErrorBanner(message: error)
                    }

                    if libraryStore.clips.isEmpty {
                        EmptySoundboardView(importAction: {
                            isImporterPresented = true
                        })
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                            ForEach(libraryStore.clips) { clip in
                                SoundClipButton(
                                    clip: clip,
                                    isActive: playbackManager.activeClipIDs.contains(clip.id),
                                    play: {
                                        playbackManager.play(clip, from: libraryStore.soundsDirectory)
                                    },
                                    delete: {
                                        libraryStore.delete(clip)
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 92)
            }

            VStack {
                Spacer()
                BottomTransportBar(
                    hasActivePlayback: !playbackManager.activeClipIDs.isEmpty,
                    stopAction: {
                        playbackManager.stopAll()
                    },
                    importAction: {
                        isImporterPresented = true
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
        .navigationTitle("vmic")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isImporterPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(QuietIconButtonStyle())
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    await libraryStore.importFiles(from: urls)
                }
            case .failure(let error):
                libraryStore.lastError = error.localizedDescription
            }
        }
    }
}

private struct PlayerHeader: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager

    let activeClips: [SoundClip]

    private var title: String {
        activeClips.first?.title ?? "Ready to bridge audio"
    }

    private var subtitle: String {
        if activeClips.count > 1 {
            return "\(activeClips.count) sounds playing"
        }

        if injectionManager.isInjectionEnabled {
            return "Injection enabled"
        }

        return "Select a sound to play"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [VmicTheme.blue, VmicTheme.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 104, height: 104)

                    WaveformMark(isActive: !activeClips.isEmpty)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(VmicTheme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(VmicTheme.mutedInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                MiniStatus(
                    title: injectionManager.isInjectionAvailableInCurrentCall ? "Call" : "Standby",
                    systemImage: injectionManager.isInjectionAvailableInCurrentCall ? "phone.fill" : "phone",
                    tint: injectionManager.isInjectionAvailableInCurrentCall ? VmicTheme.mint : VmicTheme.mutedInk
                )

                MiniStatus(
                    title: injectionManager.isInjectionEnabled ? "Live" : "Local",
                    systemImage: injectionManager.isInjectionEnabled ? "dot.radiowaves.left.and.right" : "speaker.wave.2",
                    tint: injectionManager.isInjectionEnabled ? VmicTheme.blue : VmicTheme.mutedInk
                )
            }
        }
        .padding(18)
        .background(VmicTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        }
    }
}

private struct WaveformMark: View {
    let isActive: Bool

    private let heights: [CGFloat] = [24, 42, 32, 58, 38, 50, 28]

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white.opacity(index.isMultiple(of: 2) ? 0.94 : 0.72))
                    .frame(width: 6, height: isActive ? height : max(16, height * 0.48))
                    .animation(.easeInOut(duration: 0.2), value: isActive)
            }
        }
    }
}

private struct MiniStatus: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct EmptySoundboardView: View {
    let importAction: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            WaveformMark(isActive: false)
                .frame(width: 112, height: 72)
                .background(
                    LinearGradient(
                        colors: [VmicTheme.blue.opacity(0.92), VmicTheme.cyan.opacity(0.92)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            VStack(spacing: 6) {
                Text("No Sounds")
                    .font(.headline)
                    .foregroundStyle(VmicTheme.ink)

                Text("Import audio files to create pads.")
                    .font(.subheadline)
                    .foregroundStyle(VmicTheme.mutedInk)
            }

            Button(action: importAction) {
                Label("Import Audio", systemImage: "plus")
                    .frame(maxWidth: 220)
            }
            .buttonStyle(BlueProminentButtonStyle())
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}

private struct BottomTransportBar: View {
    let hasActivePlayback: Bool
    let stopAction: () -> Void
    let importAction: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: stopAction) {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(TransportIconButtonStyle(isActive: hasActivePlayback))
            .disabled(!hasActivePlayback)

            Button(action: importAction) {
                Label("Import", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BlueProminentButtonStyle())
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.64), lineWidth: 1)
        }
    }
}

private struct TransportIconButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(isActive ? Color.white : VmicTheme.mutedInk)
            .frame(width: 48, height: 48)
            .background(
                isActive ? VmicTheme.ink.opacity(configuration.isPressed ? 0.84 : 1) : Color.white.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(red: 0.82, green: 0.20, blue: 0.18))

            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(VmicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
