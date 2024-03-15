# mk3d-fs-to-spatial

Script that will take a frame-sequential `mk3d` 3D video and convert it to Apple Spatial Video.
The `mk3d` file can be created with [MakeMKV][makemkv] or similar.

### Prerequisites

You will need an Apple Silicon-based Mac running macOS Sonoma (see [caveats](#caveats)).

You must also have the following installed and configured on your system:

- [`ffmpeg`][ffmpeg], most easily [installed with homebrew][ffmpeg-homebrew]
- `ldecod` (part of the [JM H.264/AVC reference software][jm-reference]), Mac binaries available [on GitHub][ldecod]
- [`spatial-media-kit-tool`][spatial]
- [`mp4box`][mp4box], part of the [GPAC framework][gpac]

You will also need sufficient disk space to store the intermediate files and the final Spatial video.

### CLI Options

| **Option**                          | **Example use**             | **Description**                                                                                                                                                                                                                                    |
| ----------------------------------- | --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-x`<br>`--software`                | `--software`                | Use [`libx265`][libx265] software encoder (slower, higher quality). This is the default encoder.<br>Since the `libx265` conversion is lossless, there is no quality to specify.                                                                    |
| `-t`<br>`--hardware`                | `--hardware`                | Use [`hevc_videotoolbox`][videotoolbox] hardware encoder (faster, lower quality).<br>Specify quality with `--hevc-quality`.                                                                                                                        |
| `-q`<br>`--hevc-quality`            | `--hevc-quality 50`         | Quality to use with `hevc_videotoolbox` (1 to 100, 100 is highest quality/bitrate; default 50)<br>Larger target quality (especially above 50) will use _lots_ of disk space.                                                                       |
| `-s`<br>`--spatial-quality`         | `--spatial-quality 50`      | Quality to use with spatial-media-kit-tool (1 to 100, 100 is highest quality/bitrate; default 50)<br>This will have the largest impact on the bitrate/size of the final spatial video.                                                             |
| `-a`<br>`--audio-bitrate`           | `--audio-bitrate 512k`      | Compress audio with AAC at this bitrate using [`aac_at`][aac_at] to save space.<br>If omitted, lossless LPCM audio will be used instead.                                                                                                           |
| `-k`<br>`--keep-intermediate-files` | `--keep-intermediate-files` | Instead of removing intermediate files when they are no longer needed, leave them on disk.<br>Good to use when you are testing so you can run a later step without redoing all previous steps.<br>Makes the process require more total disk space. |
| `-v`<br>`--verbose`                 | `--verbose`                 | Enable verbose output. Not too noisy, good to enable to see what's going on.                                                                                                                                                                       |

#### Caveats

This script has been tested on these configurations:

- Apple Silicon M2 Mac running macOS 14.3.1

It might on Intel-based Macs, as well as other versions of macOS Sonoma, but your mileage may vary. If you get it working on your machine, please submit a PR to update this list!

This will _not_ work on Linux or any other non-Apple OS, as the Spatial video encoding relies on APIs only available in macOS.

#### Acknowledgements

Big thanks to:

- [sturmen][sturmen] on the Doom9 forums, for a [an encoding guide][sturmen-guide] using `FRIM Decoder` as well as creating the [spatial-media-kit-tool][spatial]
- [Vargol][vargol] on GitHub, for making the [JM reference software][jm-reference] [build properly on macOS][vargol-tools] as well as an [example script][vargol-guide] that was a useful reference

[makemkv]: https://www.makemkv.com/
[ffmpeg]: https://ffmpeg.org/
[ffmpeg-homebrew]: (https://formulae.brew.sh/formula/ffmpeg)
[jm-reference]: https://iphome.hhi.de/suehring/
[ldecod]: https://github.com/steverice/h264-tools
[spatial]: https://github.com/sturmen/SpatialMediaKit
[mp4box]: https://github.com/gpac/gpac/wiki/MP4Box
[gpac]: https://gpac.io/
[libx265]: https://trac.ffmpeg.org/wiki/Encode/H.265
[videotoolbox]: https://trac.ffmpeg.org/wiki/HWAccelIntro#VideoToolbox
[aac_at]: https://trac.ffmpeg.org/wiki/Encode/AAC#aac_at
[sturmen]: https://forum.doom9.org/member.php?u=224594
[sturmen-guide]: https://forum.doom9.org/showthread.php?p=1996846#post1996846
[vargol]: https://github.com/Vargol
[vargol-tools]: https://github.com/Vargol/h264-tools
[vargol-guide]: https://github.com/Vargol/h264-tools/wiki/Conversion-script-for-MVC-3D-blu-ray-extracted-by--MakeMKV
