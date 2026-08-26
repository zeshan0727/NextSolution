# Top Home Screen Tweaks video

This package turns the published comparison at
`https://nextjailbreak.com/top-home-screen-tweaks.html` into an original narrated
YouTube video. It produces:

- a 1920×1080 MP4 with burned-in captions;
- a 1280×720 thumbnail;
- eight 1080×1920 Shorts, one self-contained segment per tweak;
- eight vertical Short covers and individual SRT caption files;
- an SRT caption file;
- long-video and Shorts titles, descriptions, tags and source credits; and
- a manifest recording the model, voice and disclosure.

The narration is an editorial comparison based on source listings. It does not
claim hands-on testing. The intro and YouTube description both disclose that the
voice is AI-generated. The feature imagery uses resized screenshots published by
the package marketplace or developer and composes them inside a consistent frame.
See `VISUAL_SOURCES.md` for the exact source record.

## Local design preview

```bash
python3 -m pip install Pillow
python3 video-production/top-home-screen-tweaks/build_video.py \
  --output video-output/top-home-screen-preview
```

## Full render

The GitHub workflow supplies the repository's encrypted `OPENAI_API_KEY` and
uses the current `gpt-4o-mini-tts` Speech API with the `cedar` voice. The key is
never written to an artifact or log.

```bash
OPENAI_API_KEY=... python3 video-production/top-home-screen-tweaks/build_video.py \
  --render \
  --output video-output/top-home-screen-tweaks
```

Review the long MP4, all eight Shorts, covers, descriptions and captions before
publishing. Confirm the destination channel, visibility and final metadata at
the YouTube publish step.
