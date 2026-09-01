import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SoundboardView: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var libraryStore: SoundLibraryStore
    @EnvironmentObject private var playbackManager: AudioPlaybackManager
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var editMode: EditMode = .inactive
    @State private var isImporterPresented = false
    @State private var clipBeingRenamed: SoundClip?
    @State private var renameText = ""
    @State private var showsSortingNotice = false

    private var activeClips: [SoundClip] {
        libraryStore.clips.filter {
            playbackManager.activeClipIDs.contains($0.id)
        }
    }

    var body: some View {
        ZStack {
            VmicTheme.appBackground

            List {
                Section {
                    PlayerHeader(activeClips: activeClips)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    InjectionControlPanel()
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    if let error = injectionManager.lastError ?? libraryStore.lastError ?? playbackManager.lastError {
                        ErrorBanner(message: error)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }

                if libraryStore.clips.isEmpty {
                    Section {
                        EmptySoundboardView(importAction: {
                            isImporterPresented = true
                        })
                        .listRowInsets(EdgeInsets(top: 18, leading: 16, bottom: 18, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(libraryStore.clips) { clip in
                            AudioListRow(
                                clip: clip,
                                artworkDirectory: libraryStore.artworkDirectory,
                                isActive: playbackManager.activeClipIDs.contains(clip.id),
                                play: {
                                    play(clip)
                                },
                                rename: {
                                    clipBeingRenamed = clip
                                    renameText = clip.title
                                },
                                remove: {
                                    libraryStore.delete(clip)
                                }
                            )
                            .onLongPressGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    editMode = .active
                                    showsSortingNotice = true
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 12))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .onMove(perform: libraryStore.move)
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .padding(.bottom, libraryStore.clips.isEmpty ? 0 : 78)

            if !libraryStore.clips.isEmpty {
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

            if showsSortingNotice {
                VStack {
                    Text(settingsStore.text(.sortingEnabled))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(VmicTheme.ink.opacity(0.88), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(.top, 8)

                    Spacer()
                }
                .transition(.opacity)
                .task {
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    showsSortingNotice = false
                }
            }
        }
        .navigationTitle("vmic")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if editMode.isEditing {
                    Button(settingsStore.text(.done)) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            editMode = .inactive
                        }
                    }
                }

                Button {
                    isImporterPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(QuietIconButtonStyle())
                .accessibilityLabel(settingsStore.text(.importAudio))
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
        .alert(settingsStore.text(.renameAudio), isPresented: Binding(
            get: {
                clipBeingRenamed != nil
            },
            set: { isPresented in
                if !isPresented {
                    clipBeingRenamed = nil
                    renameText = ""
                }
            }
        )) {
            TextField(settingsStore.text(.audioName), text: $renameText)

            Button(settingsStore.text(.cancel), role: .cancel) {
                clipBeingRenamed = nil
                renameText = ""
            }

            Button(settingsStore.text(.save)) {
                if let clip = clipBeingRenamed {
                    libraryStore.rename(clip, to: renameText)
                }
                clipBeingRenamed = nil
                renameText = ""
            }
        }
    }

    private func play(_ clip: SoundClip) {
        if settingsStore.singlePlayback {
            playbackManager.stopAll()
        }

        playbackManager.play(clip, from: libraryStore.soundsDirectory)
    }
}

private struct PlayerHeader: View {
    @EnvironmentObject private var injectionManager: MicrophoneInjectionManager
    @EnvironmentObject private var libraryStore: SoundLibraryStore
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let activeClips: [SoundClip]

    private var title: String {
        activeClips.first?.title ?? settingsStore.text(.readyToBridgeAudio)
    }

    private var subtitle: String {
        if activeClips.count > 1 {
            return settingsStore.text(.soundsPlaying(activeClips.count))
        }

        if injectionManager.isInjectionEnabled {
            return settingsStore.text(.injectionEnabled)
        }

        return settingsStore.text(.selectSoundToPlay)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 18) {
                CoverArtworkView(
                    artworkURL: activeClips.first?.artworkURL(in: libraryStore.artworkDirectory),
                    size: 104
                )

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
                    title: injectionManager.isInjectionAvailableInCurrentCall ? settingsStore.text(.call) : settingsStore.text(.standby),
                    systemImage: injectionManager.isInjectionAvailableInCurrentCall ? "phone.fill" : "phone",
                    tint: injectionManager.isInjectionAvailableInCurrentCall ? VmicTheme.mint : VmicTheme.mutedInk
                )

                MiniStatus(
                    title: injectionManager.isInjectionEnabled ? settingsStore.text(.live) : settingsStore.text(.local),
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

private struct AudioListRow: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let clip: SoundClip
    let artworkDirectory: URL
    let isActive: Bool
    let play: () -> Void
    let rename: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                CoverArtworkView(artworkURL: clip.artworkURL(in: artworkDirectory), size: 58)

                if isActive {
                    Circle()
                        .fill(VmicTheme.ink.opacity(0.72))
                        .frame(width: 30, height: 30)

                    Image(systemName: "play.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(clip.title)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(isActive ? Color(red: 0.96, green: 0.16, blue: 0.20) : VmicTheme.ink)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(settingsStore.text(.localAudio))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(red: 0.88, green: 0.53, blue: 0.10))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .overlay {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(Color(red: 0.88, green: 0.53, blue: 0.10), lineWidth: 1)
                        }

                    Text(clip.artist?.isEmpty == false ? clip.artist! : settingsStore.text(.unknownArtist))
                        .font(.subheadline)
                        .foregroundStyle(isActive ? Color(red: 0.96, green: 0.16, blue: 0.20) : VmicTheme.mutedInk)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if settingsStore.showDuration {
                Text(formatDuration(clip.durationSeconds))
                    .font(.subheadline)
                    .foregroundStyle(VmicTheme.mutedInk)
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
            }

            Menu {
                Button(action: rename) {
                    Label(settingsStore.text(.rename), systemImage: "pencil")
                }

                Button(role: .destructive, action: remove) {
                    Label(settingsStore.text(.removeFromLibrary), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.bold))
                    .foregroundStyle(VmicTheme.mutedInk)
                    .frame(width: 34, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: play)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(settingsStore.text(.playSound(clip.title)))
    }

    private func formatDuration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else {
            return "--:--"
        }

        let totalSeconds = Int(seconds.rounded())
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct CoverArtworkView: View {
    let artworkURL: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let artworkURL, let image = UIImage(contentsOfFile: artworkURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("PlaceholderCover")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let importAction: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            CoverArtworkView(artworkURL: nil, size: 112)

            VStack(spacing: 6) {
                Text(settingsStore.text(.noSounds))
                    .font(.headline)
                    .foregroundStyle(VmicTheme.ink)

                Text(settingsStore.text(.importHint))
                    .font(.subheadline)
                    .foregroundStyle(VmicTheme.mutedInk)
            }

            Button(action: importAction) {
                Label(settingsStore.text(.importAudio), systemImage: "plus")
                    .frame(maxWidth: 220)
            }
            .buttonStyle(BlueProminentButtonStyle())
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}

private struct BottomTransportBar: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

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
                Label(settingsStore.text(.importShort), systemImage: "plus")
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
