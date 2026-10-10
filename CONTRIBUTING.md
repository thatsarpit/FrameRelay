# Contributing

Build with `bash scripts/build.sh`, compile-check the extension with `bash scripts/check-extension.sh`, and run `bash scripts/test.sh` with FFmpeg/ffprobe installed. Keep changes small and include evidence for behavior changes.

For camera reports include exact model/region, firmware, protocol, codecs, resolution/frame rate and test duration. Label untested vendor compatibility as documented, not verified. Never attach private footage, addresses, keys, provisioning profiles or credentials. Synthetic reproduction clips are preferred.

The camera extension is pending signed runtime verification. Contributions to deployment and client compatibility should report actual signing/activation conditions without suggesting reduced OS security. FFmpeg is external; any future bundling needs a separate license/distribution review.
