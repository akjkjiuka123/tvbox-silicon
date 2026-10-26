# FFmpeg

Upstream: https://github.com/FFmpeg/FFmpeg, tag n8.1.3 (commit `1041abdc962f4cc4f394aa8de9dc5236c0c3b9e7`),
LGPL-2.1-or-later as built here (`LICENSE`). No GPL or nonfree parts are enabled.

Nothing of FFmpeg is committed. `Scripts/build-apple-ffmpeg.sh` clones that tag, checks the commit, and builds
unmodified sources into one static library per platform (macOS arm64 + x86_64, iOS, tvOS and their simulators):
the demuxers, MP4 muxer, parsers and decoders listed in the script, AudioToolbox's AAC encoder and
VideoToolbox's H.264/HEVC encoders and hardware decoders, zlib from the SDK, and nothing else (no network, programs, filters or
devices). `FFmpeg.xcframework` here is a link to the build in `build/FFmpeg/`.

`Sources/TVMedia` is this project's code on top of it: it repackages files AVPlayer can't open as fragmented MP4
for HLS (`Docs/mkv-playback-plan.md`).
