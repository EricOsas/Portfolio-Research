# VideoMind AI — Execution Log

- Job ID: `a9cbb01cc77a`
- Video: https://youtu.be/bJTnI0tWi5k (My Most Profitable Gold Trading Bot | Full Build (Part 3))
- Status: completed
- Model used: gemini-3-8-flash
- Analysis range: 00:00:00 – 01:12:58 (0s – 4379s)
- Video duration: 4378.7s (72.98 min)
- Frame interval: 1s
- Scene-change threshold: 0.25
- Uniform frames extracted: 4379
- Scene-change frames detected: 168
- Selected checkpoints sent to Coarena: 1611
- Frames with local OCR: 2901
- Vision batches (6 images each): 269
- Valid code observations: 1429
- Reconstructed files: 2
- Observed code lines: 1502
- Missing/unreadable lines (placeholders): 1854
- Lines revised between observations: 1100
- Lines observed only once: 402

## Per-file summary

| File | Observed lines | Missing lines | Revised | Single-observation |
| --- | --- | --- | --- | --- |
| `Gold X9 v6.3 - Youtube shared Part 3.mq5` | 1405 | 562 | 1078 | 327 |
| `Gold X9 v6.3 - Youtube shared Part 2.mq5` | 97 | 1292 | 22 | 75 |

## Pipeline stages executed

1. YouTube download via the application workflow (yt-dlp, `-f bv*+ba/b`, English auto-captions).
2. Local FFmpeg probe and duration validation against `MAX_VIDEO_MINUTES=120`.
3. Uniform 1 fps frame extraction (1920 px wide cap) with timestamp labels.
4. FFmpeg scene-change detection (`select=gt(scene,0.25)`).
5. Local pixel + edge difference selection (`0.65*pixel + 0.35*edge >= 1.5`).
6. Local Tesseract 5.4.0 OCR (`--oem 3 --psm 6`, confidence >= 25).
7. Transcript parsing from downloaded VTT (engine unchanged).
8. Coarena vision extraction, 6 images per request, `claude-haiku-5-5`.
9. Reconstruction with per-line provenance, revisions and missing-line placeholders.
10. ZIP + Markdown/JSON report + manifest generation by the application.

## Privacy

- The original video was never uploaded; it was downloaded locally and moved to `source/`.
- Only selected JPEG screenshots and their local OCR text were sent to Coarena.
- Cloud consent was requested and explicitly granted before the first video-derived request.
- The API key lives only in `VideoMind-AI/.env` (git-ignored) and does not appear in any deliverable.

## Fixes applied during setup

- `app/media.py`: force `format=yuvj420p` for scene-frame JPEG output; FFmpeg 9 refused the limited-range AV1 stream and scene extraction aborted the job.
- `app/media.py`: enable yt-dlp JS challenge solving (`--js-runtimes node`, `--remote-components ejs:github`) and TLS impersonation (`--impersonate chrome` via `curl-cffi`) with socket timeout and retries; without these the YouTube download stalled mid-stream.
- `app/main.py`: run the YouTube download in a threadpool so `/api/health` and job status stay responsive during long downloads.
- `app/timeline.py`: report revised lines and single-observation (unverified) lines, which were collected but never surfaced.
- `.env.example`: add missing `SCENE_CHANGE_THRESHOLD`, remove duplicated `TESSERACT_CMD`.
- `requirements.txt`: add `curl-cffi` for yt-dlp impersonation.
