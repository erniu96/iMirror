# H.264 test fixture

`blue-640x480.h264` is one self-generated blue frame in Annex-B H.264 format
(640×480, Constrained Baseline, YUV 4:2:0). It contains no device recording,
personal information, or third-party media. It makes the video smoke test
reproducible without FFmpeg being installed on the test machine.

Generated with FFmpeg 8.0.1 and libx264:

```sh
ffmpeg -hide_banner -loglevel error \
  -f lavfi -i color=c=blue:s=640x480:r=30 -frames:v 1 \
  -c:v libx264 -threads 1 -profile:v baseline -pix_fmt yuv420p -tune zerolatency \
  -x264-params keyint=1:scenecut=0 -bsf:v filter_units=remove_types=6 \
  -f h264 Tests/Fixtures/blue-640x480.h264
```

SEI metadata is removed. `./build.sh test` uses this fixture by default;
`IMIRROR_VIDEO_FIXTURE` can supply a different Annex-B stream. On a macOS VM
without hardware decoding, `IMIRROR_ALLOW_SOFTWARE_DECODER=1 ./build.sh test`
permits VideoToolbox's software decoder in the smoke test. The application
continues to require hardware decoding.
