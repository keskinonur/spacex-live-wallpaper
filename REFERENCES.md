# References and media provenance

## Photographs

The project author supplied both photographs and identified this SpaceX post as their source:

- [SpaceX on X: supplied photograph source](https://x.com/SpaceX/status/2104654998034690329)

| Local file | Dimensions | Attribution |
| --- | --- | --- |
| `Media/spacex_20260929_1.jpeg` | 4096 × 2304 | SpaceX, based on the supplied source |
| `Media/spacex_20260929_2.jpeg` | 3732 × 2099 | SpaceX, based on the supplied source |

## Video: original source unconfirmed

`Media/spacex_20260929.mp4` is the locally supplied input clip: approximately 26.159 seconds, 1920 × 1080, H.264, approximately 59.94 fps, with no audio stream.

The project author does not know its exact original source and supplied these as possible references:

- [Rachelspeakout1 on X: possible related video post](https://x.com/Rachelspeakout1/status/2104737273069674908)
- [RiseOfNewMedia on X: possible related video post](https://x.com/RiseOfNewMedia/status/2104729961256853899)

Neither account is asserted to be the original creator or rights holder. The local clip has not been matched against either post, and these links do not establish ownership or permission to redistribute it.

All three X links returned HTTP 403 during automated access on September 29, 2026. They are recorded as supplied references; their post contents and publication dates were not independently verified. The date in the local filenames is a file label, not a verified event or publication date.

## Transformations

- The photographs receive artistic, localized plume motion and a subtle engine-light pulse. These effects are synthesized from still photographs, not recorded cloud motion or measured launch behavior.
- The rocket, tower, and ground are protected from local displacement; a small eased camera zoom is applied to the whole scene.
- The video contributes its first 20 seconds, resampled to 30 fps and scaled to 3840 × 2160.
- Two-second crossfades connect the scenes and the loop boundary.
- The result is `SpaceX-4K-Loop.mp4`: 50 seconds, 3840 × 2160, 30 fps, HEVC, without audio.
- Input files in `Media/` are unchanged copies of those supplied locally.

## Technical references

- [Apple: AVPlayerLooper](https://developer.apple.com/documentation/avfoundation/avplayerlooper), queue-based looping playback.
- [Apple: AVPlayerLayer](https://developer.apple.com/documentation/avfoundation/avplayerlayer), displaying decoded video in a layer.
- [Apple: Core Image](https://developer.apple.com/documentation/coreimage), image transforms and rendering.
- [Apple: AVAssetWriter](https://developer.apple.com/documentation/avfoundation/avassetwriter), writing photo sequences.
- [FFmpeg filter documentation](https://ffmpeg.org/ffmpeg-filters.html), frame-rate conversion, scaling, and crossfades.

## Native wallpaper integration

The native integration is based on inspection of the local macOS 27.2 Aerial catalog and wallpaper store. These are undocumented implementation details, not Apple-supported extension points. `AVAssetExportSession` remuxes the bundled video into MOV, and `AVAssetImageGenerator` produces its thumbnail. The native system controls lock-screen playback and timing; no frame synchronization is claimed.

## Rights

Photography is credited to SpaceX based on the supplied source. Video authorship and rights remain unverified. Media and trademarks belong to their respective rights holders; no ownership or redistribution license is claimed by this project. Source attribution should be retained when sharing the files.
