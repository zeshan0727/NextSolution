#!/bin/bash
set -euo pipefail

git fetch --depth=1 origin d316a61b05b8256ad4e972407c507a0030162633
git show FETCH_HEAD:NextMediaApp/build145.sh > /tmp/NextMedia-build146-core.sh

python3 - <<'PY'
from pathlib import Path

path = Path('/tmp/NextMedia-build146-core.sh')
source = path.read_text()

needle = "tar -xzf /tmp/NextMedia-v145-patch.tar.gz\n"
addition = r'''

python3 - <<'PY146'
from pathlib import Path
import plistlib

root = Path('projects/NextMedia')

def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f'Could not locate {label} in {path}')
    path.write_text(text.replace(old, new, 1))

player_manager = root / 'NextMedia/Services/PlayerManager.swift'
replace_once(
    player_manager,
    '    private let positionPrefix = "nextMedia.resume."\n',
    '    private let positionPrefix = "nextMedia.resume."\n'
    '    private let playbackStartModeKey = "playbackStartMode"\n\n'
    '    private var shouldResumeSavedPosition: Bool {\n'
    '        UserDefaults.standard.string(forKey: playbackStartModeKey) != "start"\n'
    '    }\n',
    'playback start mode storage'
)
replace_once(
    player_manager,
    '        loadCurrentAndPlay(restoringPosition: true)\n',
    '        loadCurrentAndPlay(restoringPosition: shouldResumeSavedPosition)\n',
    'initial play resume decision'
)
replace_once(
    player_manager,
    '        loadCurrentAndPlay(restoringPosition: true)\n    }\n\n    func playPrevious()',
    '        loadCurrentAndPlay(restoringPosition: shouldResumeSavedPosition)\n    }\n\n    func playPrevious()',
    'next-track resume decision'
)
replace_once(
    player_manager,
    '        loadCurrentAndPlay(restoringPosition: true)\n    }\n\n    func seek(to seconds:',
    '        loadCurrentAndPlay(restoringPosition: shouldResumeSavedPosition)\n    }\n\n    func seek(to seconds:',
    'previous-track resume decision'
)
replace_once(
    player_manager,
    '    func stopIfPlaying(_ item: MediaItem) {\n',
    '    func stopPlayback() {\n'
    '        stopAndClear()\n'
    '    }\n\n'
    '    func stopIfPlaying(_ item: MediaItem) {\n',
    'expanded player stop action'
)

settings = root / 'NextMedia/Views/SettingsView.swift'
replace_once(
    settings,
    '    @AppStorage("preferYouTube1080p") private var preferYouTube1080p = true\n',
    '    @AppStorage("preferYouTube1080p") private var preferYouTube1080p = true\n'
    '    @AppStorage("playbackStartMode") private var playbackStartMode = "resume"\n',
    'playback start setting'
)
replace_once(
    settings,
    """                Section("Playback") {
                    Label("Background audio and lock-screen controls", systemImage: "lock.iphone")
                    Label("Picture in Picture for supported video", systemImage: "pip")
                    Label("AirPlay through the system player", systemImage: "airplayvideo")
                    Label("Cross button completely stops and closes playback", systemImage: "xmark.circle.fill")
                }
""",
    """                Section("Playback") {
                    Picker("When opening media", selection: $playbackStartMode) {
                        Text("Resume from Last Position").tag("resume")
                        Text("Always Start from Beginning").tag("start")
                    }
                    .pickerStyle(.menu)

                    Text(playbackStartMode == "resume"
                         ? "Each song or video continues from its last saved position."
                         : "Every song or video starts at 00:00 when opened.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    Label("Background audio and lock-screen controls", systemImage: "lock.iphone")
                    Label("Picture in Picture for supported video", systemImage: "pip")
                    Label("AirPlay through the system player", systemImage: "airplayvideo")
                    Label("Cross button completely stops and closes playback", systemImage: "xmark.circle.fill")
                }
""",
    'Playback settings section'
)
replace_once(settings, 'Text("1.4.5")', 'Text("1.4.6")', 'About version')

now_playing = root / 'NextMedia/Views/NowPlayingView.swift'
replace_once(
    now_playing,
    '                    mainControls\n                    playbackOptions\n',
    '                    mainControls\n                    stopPlaybackControl\n                    playbackOptions\n',
    'expanded stop control placement'
)
replace_once(
    now_playing,
    '        .gesture(\n            DragGesture(minimumDistance: 24)\n',
    '        .simultaneousGesture(\n            DragGesture(minimumDistance: 24)\n',
    'non-blocking expanded swipe gesture'
)
replace_once(
    now_playing,
    """    private var mainControls: some View {
        HStack(spacing: 22) {
            Button(action: player.playPrevious) {
                Image(systemName: "backward.end.fill").font(.title2)
            }
            Button { player.skip(by: -10) } label: {
                Image(systemName: "gobackward.10").font(.title)
            }
            Button(action: player.togglePlayback) {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
            }
            Button { player.skip(by: 10) } label: {
                Image(systemName: "goforward.10").font(.title)
            }
            Button(action: player.playNext) {
                Image(systemName: "forward.end.fill").font(.title2)
            }
        }
        .buttonStyle(.plain)
    }
""",
    """    private var mainControls: some View {
        HStack(spacing: 12) {
            expandedControlButton("backward.end.fill", label: "Previous", font: .title2) {
                player.playPrevious()
            }
            expandedControlButton("gobackward.10", label: "Back 10 Seconds", font: .title) {
                player.skip(by: -10)
            }
            Button {
                player.togglePlayback()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .frame(width: 72, height: 72)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            expandedControlButton("goforward.10", label: "Forward 10 Seconds", font: .title) {
                player.skip(by: 10)
            }
            expandedControlButton("forward.end.fill", label: "Next", font: .title2) {
                player.playNext()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var stopPlaybackControl: some View {
        Button(role: .destructive) {
            player.stopPlayback()
        } label: {
            Label("Stop Playback", systemImage: "stop.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .accessibilityLabel("Stop and close playback")
    }

    private func expandedControlButton(
        _ systemName: String,
        label: String,
        font: Font,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(font)
                .frame(width: 46, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
""",
    'expanded transport controls'
)
replace_once(
    now_playing,
    """            HStack {
                Text(time(player.currentTime))
                Spacer()
                Button { player.skip(by: -10) } label: { Image(systemName: "gobackward.10") }
                Button(action: player.togglePlayback) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                Button { player.skip(by: 10) } label: { Image(systemName: "goforward.10") }
                Spacer()
                Text("−\\(time(max(player.duration - player.currentTime, 0)))")
            }
            .font(.subheadline.monospacedDigit())
""",
    """            HStack(spacing: 9) {
                Text(time(player.currentTime))
                    .frame(minWidth: 48, alignment: .leading)
                Spacer(minLength: 2)
                Button(action: player.playPrevious) { Image(systemName: "backward.end.fill") }
                    .accessibilityLabel("Previous")
                Button { player.skip(by: -10) } label: { Image(systemName: "gobackward.10") }
                    .accessibilityLabel("Back 10 Seconds")
                Button(action: player.togglePlayback) {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Button { player.skip(by: 10) } label: { Image(systemName: "goforward.10") }
                    .accessibilityLabel("Forward 10 Seconds")
                Button(action: player.playNext) { Image(systemName: "forward.end.fill") }
                    .accessibilityLabel("Next")
                Button(role: .destructive, action: player.stopPlayback) {
                    Image(systemName: "stop.fill")
                }
                .accessibilityLabel("Stop Playback")
                Spacer(minLength: 2)
                Text("−\\(time(max(player.duration - player.currentTime, 0)))")
                    .frame(minWidth: 48, alignment: .trailing)
            }
            .font(.subheadline.monospacedDigit())
            .buttonStyle(.plain)
""",
    'fullscreen transport controls'
)

info_path = root / 'NextMedia/Info.plist'
with info_path.open('rb') as handle:
    info = plistlib.load(handle)
info['CFBundleShortVersionString'] = '1.4.6'
info['CFBundleVersion'] = '12'
with info_path.open('wb') as handle:
    plistlib.dump(info, handle, sort_keys=False)

project = root / 'project.yml'
project_text = project.read_text()
project_text = project_text.replace('MARKETING_VERSION: "1.4.5"', 'MARKETING_VERSION: "1.4.6"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "11"', 'CURRENT_PROJECT_VERSION: "12"')
project.write_text(project_text)
PY146

grep -q 'stopPlaybackControl' projects/NextMedia/NextMedia/Views/NowPlayingView.swift
grep -q 'expandedControlButton' projects/NextMedia/NextMedia/Views/NowPlayingView.swift
grep -q 'simultaneousGesture' projects/NextMedia/NextMedia/Views/NowPlayingView.swift
grep -q 'Button(role: .destructive, action: player.stopPlayback)' projects/NextMedia/NextMedia/Views/NowPlayingView.swift
grep -q 'func stopPlayback()' projects/NextMedia/NextMedia/Services/PlayerManager.swift
grep -q 'shouldResumeSavedPosition' projects/NextMedia/NextMedia/Services/PlayerManager.swift
grep -q 'playbackStartModeKey' projects/NextMedia/NextMedia/Services/PlayerManager.swift
grep -q '@AppStorage("playbackStartMode")' projects/NextMedia/NextMedia/Views/SettingsView.swift
grep -Fq 'Resume from Last Position' projects/NextMedia/NextMedia/Views/SettingsView.swift
grep -Fq 'Always Start from Beginning' projects/NextMedia/NextMedia/Views/SettingsView.swift
grep -q '<string>1.4.6</string>' projects/NextMedia/NextMedia/Info.plist
grep -q '<string>12</string>' projects/NextMedia/NextMedia/Info.plist
grep -q 'MARKETING_VERSION: "1.4.6"' projects/NextMedia/project.yml
grep -q 'CURRENT_PROJECT_VERSION: "12"' projects/NextMedia/project.yml
'''
if needle not in source:
    raise SystemExit('Could not locate v1.4.5 patch extraction point')
source = source.replace(needle, needle + addition, 1)

source = source.replace("1.4.5", "1.4.6")
source = source.replace("== '11'", "== '12'")
source = source.replace("grep -qx '11'", "grep -qx '12'")

path.write_text(source)
PY

exec bash /tmp/NextMedia-build146-core.sh
