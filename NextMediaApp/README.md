# Next Media 1.0.0

Next Media is an iOS 15+ SwiftUI audio/video player designed for unsigned TrollStore installation.

## Included

- Audio and video import from Files
- Local and remote playback using AVPlayer
- Background audio and lock-screen controls
- Picture in Picture, AirPlay, queue, shuffle, repeat, playback speed, seek controls, and sleep timer
- Direct HTTPS media downloads with progress and a Downloads library
- Native conversion presets for 4K/1080p/720p MP4, MOV, M4V, and M4A audio extraction
- Official YouTube Data API search with thumbnails and titles; results open in YouTube
- System, light, and dark appearance modes
- iPhone and iPad support, minimum iOS 15.0

## YouTube boundary

The app does not scrape YouTube streams, bypass platform protections, or extract MP3/MP4 files from YouTube. Direct downloads are intended only for media URLs the user owns or is authorized to download.

## Build

The `Build Next Media TIPA` GitHub Actions workflow restores the project, generates the Xcode project with XcodeGen, builds without code signing, and uploads:

- `NextMedia-1.0.0.tipa`
- `NextMedia-1.0.0.ipa`
- SHA-256 checksums
- Xcode build log

Bundle identifier: `uk.zeshanbarvi.nextmedia`

Author: Next Solution – Zeeshan 0727
