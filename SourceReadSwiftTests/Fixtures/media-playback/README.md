# Deterministic playback fixture

`episode.mp4` is an original FFmpeg test pattern and quiet synthesized tone (24 seconds, H.264 + AAC).
It contains no third-party footage. Native tests use a real AVPlayerItem to exercise duration discovery,
resume, pause, replacement and obsolete completion notifications without external network access.

```sh
ffmpeg -f lavfi -i 'testsrc2=size=160x96:rate=12:duration=24' \
  -f lavfi -i 'sine=frequency=440:sample_rate=22050:duration=24' \
  -vf format=yuv420p -af volume=0.02 -c:v libx264 -crf 40 -c:a aac -b:a 24k \
  -movflags +faststart episode.mp4
```
