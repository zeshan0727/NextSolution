# Top Home Screen Tweaks video

This package turns the published comparison at
`https://nextsolution.cc/top-home-screen-tweaks.html` into an original narrated
YouTube video. It produces:

- a 1920×1080 MP4 with burned-in captions;
- a 1280×720 thumbnail;
- an SRT caption file;
- a title, description, tags and chapter list; and
- a manifest recording the model, voice and disclosure.

The narration is an editorial comparison based on source listings. It does not
claim hands-on testing. The intro and YouTube description both disclose that the
voice is AI-generated.

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

Review the MP4, thumbnail, description and captions before publishing. Confirm
the destination channel, visibility and final metadata at the YouTube publish
step.
