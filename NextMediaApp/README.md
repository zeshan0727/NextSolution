# Next Media 1.1.0

Next Media is an iOS 15+ SwiftUI audio/video player and authorized media downloader designed for unsigned TrollStore installation.

## Included

- Audio and video import from Files
- Local and remote playback using AVPlayer
- Background audio and lock-screen controls
- Picture in Picture, AirPlay, queue, shuffle, repeat, playback speed, seek controls and sleep timer
- In-app WKWebView browser with website/YouTube search
- Playback-aware detection of directly exposed MP4, MOV, M4V, WebM, MP3, M4A and other media URLs
- Download popup while a compatible media file is playing
- Browser cookies, user agent, referrer and origin forwarded for authorized downloads
- Dedicated detected-media list and Downloads library
- Native conversion presets for 4K/1080p/720p MP4, MOV, M4V and M4A audio extraction
- Optional official YouTube Data API thumbnail search
- System, light and dark appearance modes
- iPhone and iPad support, minimum iOS 15.0

## Compatibility boundary

The browser detector saves complete HTTP/HTTPS media files directly exposed by a page. It may identify streaming playlists or short adaptive segments, but it does not treat them as complete videos. It does not decrypt DRM, decode protected signatures, or bypass access controls. Use media you own or are authorized to save.

## Build

The `Build Next Media 1.1.0` GitHub Actions workflow restores the version 1.0 project, overlays the version 1.1 browser patch, generates the Xcode project with XcodeGen, builds without code signing and uploads:

- `NextMedia-1.1.0.tipa`
- `NextMedia-1.1.0.ipa`
- SHA-256 checksums
- Xcode build log

Bundle identifier: `uk.zeshanbarvi.nextmedia`

Author: Next Solution – Zeeshan 0727
