# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

ImageTagger is a SwiftUI macOS app that predicts keyword tags for photos with a Core ML model and can save them into the
files' metadata. It's a port of the Java/Kotlin app at https://github.com/dnutiu/ImageTagger.

## Commands

```shell
# Build
xcodebuild -project ImageTagger.xcodeproj -scheme ImageTagger -destination 'platform=macOS' build

# Unit tests (Swift Testing)
xcodebuild -project ImageTagger.xcodeproj -scheme ImageTagger -destination 'platform=macOS' -only-testing:ImageTaggerTests test

# One suite, or one test
xcodebuild ... -only-testing:ImageTaggerTests/XMPSidecarTests test
xcodebuild ... -only-testing:'ImageTaggerTests/TagFormatTests/comma()' test

# Failure messages from a run (pass -resultBundlePath to xcodebuild to choose the path)
xcrun xcresulttool get test-results summary --path <path>.xcresult

# The imagetagger command, built with the app (pass -derivedDataPath to xcodebuild to choose where)
<DerivedData>/Build/Products/Debug/ImageTagger.app/Contents/Helpers/imagetagger --help

# Notarized DMG in build/release, and optionally a GitHub release (see README.md)
Scripts/release.sh [--publish <notes.md>] [--app <notarized ImageTagger.app>]
```

- **CI** (`.github/workflows/ci.yml`, `macos-26` runner with Xcode 26.6) runs the unit tests signed ad hoc
  (`CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=`), because the runner has no certificates. The
  `download-model` action caches the Git LFS weights to save LFS bandwidth.
- **Releases:** `Scripts/release.sh` archives ad hoc and lets the Developer ID export re-sign the app (cloud-managed
  certificate), then waits for notarization. Locally it uses the Xcode account. The Release workflow
  (`.github/workflows/release.yml`, on `v*` tags) passes an App Store Connect API key through the
  `APP_STORE_CONNECT_KEY_PATH`, `APP_STORE_CONNECT_KEY_ID` and `APP_STORE_CONNECT_ISSUER_ID` environment variables.

- **The Core ML model's weights are in Git LFS.** `TagPrediction.mlpackage/Data/com.apple.CoreML/weights/weight.bin`
  (116 MB) is too large for regular git. If it's a small text pointer file instead, run `git lfs pull`. Without the
  real weights the app builds, but tagging fails. `Scripts/convert_model.py` regenerates the model from the original
  project's ONNX model (see README.md).
- **UI tests** (`ImageTaggerUITests`) need macOS automation authorization. In a non-interactive shell they fail with
  "Timed out while enabling automation mode", so run unit tests with `-only-testing:ImageTaggerTests`.
- **Tests only build in Debug.** `@testable import` needs `ENABLE_TESTABILITY`.
- There's no linter or formatter configured.
- **Logs:** use `/usr/bin/log`, not `log` (a zsh builtin). App errors are logged with subsystem
  `nuculabs.dev.ImageTagger`, for example
  `/usr/bin/log show --last 5m --predicate 'subsystem == "nuculabs.dev.ImageTagger"'`.

## Project setup

- **File-system synchronized groups:** files added to `ImageTagger/`, `ImageTaggerTests/` or `ImageTaggerUITests/`
  join their target automatically, so the pbxproj doesn't need editing. Images, `.dng` and `.xmp` files in those
  folders become bundle resources.
- **Info.plist:** `ImageTagger-Info.plist` is at the repo root, outside the synchronized folder, so it isn't copied as a
  resource. It's merged with the generated Info.plist and declares the image and folder document types the app opens
  from Finder, plus `.xmp` as a related item type. `ITSAppUsesNonExemptEncryption = NO` answers App Store Connect's
  export compliance question for every upload, because the app doesn't use encryption. Change it if it ever does.
- **Core ML code generation is off** (`COREML_CODEGEN_LANGUAGE = None`). The model is loaded by URL as
  `TagPrediction.mlmodelc`.
- **Swift 6 with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency.** Everything is main-actor
  isolated unless marked otherwise. Types used off the main actor are declared `nonisolated`, and functions that do
  heavy work (image decoding, inference, file writes) are `@concurrent`. Without `@concurrent`, a `nonisolated async`
  function runs on the caller's actor, which is usually the main actor.
- **App Sandbox:** read-write access to user-selected files only (`ENABLE_USER_SELECTED_FILES = readwrite`).
- **Privacy manifest:** `ImageTagger/PrivacyInfo.xcprivacy` declares no tracking and no collected data, and the
  `UserDefaults` required reason API (`CA92.1`, the app's own defaults). Apps that use a required reason API without
  declaring it aren't accepted by App Store Connect. If the app starts using another one (such as file timestamps,
  disk space or system boot time) or sending data off the Mac, update the manifest, the App Store privacy answers and
  `docs/privacy/index.html` together.
- **Command line tool:** the `ImageTaggerCLI` target (folder `ImageTaggerCLI/`) builds `imagetagger`, which the app
  embeds at `Contents/Helpers/imagetagger` with code signing on copy.
  - **Shared files:** it compiles the `ImageTagger/Model` files through a membership exception set on the `ImageTagger`
    folder, so a new Model file the command needs must be added to it (Target Membership in Xcode).
  - **Not sandboxed:** it has the hardened runtime, and `SKIP_INSTALL = YES` keeps archives app archives.
  - **Mac App Store:** every executable in a Mac App Store app has to be sandboxed, so Release builds leave the command
    out: `EMBEDS_COMMAND_LINE_TOOL` is `YES` in Debug and `NO` in Release, and when it's `NO`,
    `EXCLUDED_SOURCE_FILE_NAMES` skips `imagetagger` in the Embed Command Line Tool phase. An archive made in Xcode
    can be uploaded to App Store Connect as is. `Scripts/release.sh` passes `EMBEDS_COMMAND_LINE_TOOL=YES` for the
    DMG, and the menu item is only shown when `CommandLineTool.isEmbedded`.
  - **Names:** it isn't in `Contents/MacOS`, and its module is `ImageTaggerCLI`, because `imagetagger` and
    `ImageTagger` are the same name on case-insensitive file systems.
  - **Entitlements:** the Developer ID export adds `com.apple.application-identifier` to it. It runs without a
    provisioning profile.
  - **Coverage:** the auto-generated scheme enables code coverage, so the Debug build writes `default.profraw` into the
    current folder. Release builds aren't instrumented.

## Architecture

**Model pipeline (`ImageTagger/Model`).** `Scripts/convert_model.py` wraps the ONNX ResNet with ImageNet normalization
and a sigmoid, embeds the 1708 labels as a Core ML classifier, and stores FP16 weights. INT8 weights changed the
predictions, so they aren't used. `TagPredictor` runs it through Vision's `CoreMLRequest` with `.centerCrop`. Tags are
the labels above `confidenceThreshold` (0.3775, which is sigmoid(-0.5), the original logit threshold), sorted
alphabetically. `TagPredictor.shared` loads the model once. `ImageAnalyzer` downsamples with ImageIO (orientation
applied), predicts, and reads `ImageMetadata`.

The Java original fed the red channel to all three color channels. This port uses real RGB, so its predictions
intentionally differ from the original's tests.

**Session (`ImageTagger/Session`).** `TaggingSession` is the single `@Observable` app state. `AppDelegate` owns it, so
files opened from Finder or dropped on the Dock icon (`application(_:open:)`) reach it. The app has one `Window` scene
and quits when it closes.

- **Adding:** `add(_:)` expands folders recursively, skips duplicates, and starts security-scoped access.
- **Analysis:** `ImageItem`s go into a queue. One `analysisTask` runs a task group with bounded parallelism and restarts
  itself if images arrive while a cancelled run is still winding down.
- **Cancelling:** removes the images that aren't finished.
- **Views:** they read the session from the environment. Menu commands in `ImageTaggerCommands` get it passed in.
- **Settings:** stored in `UserDefaults` under `TagFormat.storageKey` and `TaggingSession.savesTagsAutomaticallyKey`.

**Saving tags** merges the predicted tags into the keywords already in the file, case-insensitively. Nothing is ever
removed.

- **`ImageKeywords`, embedded keywords:** for JPEG, HEIC and TIFF it writes XMP `dc:subject` with
  `CGImageDestinationCopyImageSource`, which doesn't re-encode the image. ImageIO also updates an IPTC IIM block if one
  exists, but doesn't create one. PNG reports success while dropping the keywords, which is why every write is read
  back before the original is replaced.
- **`XMPSidecar`, RAW images:** for any `UTType.rawImage` it writes `IMG_1234.xmp` next to `IMG_1234.CR2`, and the RAW
  file is never modified. Existing sidecars are edited through `CGImageMetadata`, which keeps the other metadata
  semantically intact (develop settings and history), and their `xmp:MetadataDate` is updated. New sidecars start with
  the RAW's embedded keywords. A sidecar that can't be read or parsed must never be treated as missing, or it would be
  overwritten.
- **Sandbox access to sidecars:** when only the RAW file was opened, the sidecar is reached through an `NSFilePresenter`
  with `primaryPresentedItemURL` plus `NSFileCoordinator` (`RelatedFileCoordinator`). The `.xmp` related item type in
  `ImageTagger-Info.plist` uses `CFBundleTypeExtensions`. The `LSItemContentTypes` form wasn't granted access in testing.
- **Writing files:** an atomic `replaceItemAt` from the item replacement directory when the folder is accessible.
  Otherwise the file is rewritten in place, and the original bytes are restored if the write fails.

**Command line tool (`ImageTaggerCLI`).** `imagetagger [--dry-run] [--format <format>] [<path> ...]` tags the current
folder by default. It parses its options by hand, without dependencies, and finds images with `ImageFinder` (also used
by the session). It analyzes them in parallel, saves tags with `ImageKeywords.add` and prints `<path>: <tags>` in the
order of the files. Errors and the summary go to the standard error.

- **Model:** it loads the app's compiled model by resolving its own symbolic links up to `ImageTagger.app`.
- **Exit status:** formats that can't store keywords, like PNG, don't fail the run. Other errors exit with 1, and
  invalid options with 64.
- **Sidecars:** `XMPSidecar` only uses its file presenter when sandboxed (`APP_SANDBOX_CONTAINER_ID`). Outside the
  sandbox, Foundation logs an error to the standard error when a presenter's related file doesn't exist.
- **Installing:** the sandboxed app can't write `/usr/local/bin`, so **Install Command Line Tool…** in the app menu
  (`CommandLineTool`) shows and copies the `ln -s` command instead.

## Tests

- **Hosted tests share the app's environment.** Unit tests run inside the sandboxed app (`TEST_HOST`), so `Bundle.main`
  holds the model and the tests share the app's container and `UserDefaults`. Create sessions with `makeSession()`
  (`TestResources.swift`), which uses an isolated defaults suite, so the user's settings, such as auto-save, can't
  affect tests.
- **Never write to bundled fixtures.** Copy them into a `withTemporaryDirectory` directory first with
  `copy(_:to:)`. Fixtures are the three `TestImage` JPEGs, `timisoara-water-tower.dng` (a generated Bayer DNG) and
  `lightroom-sidecar.xmp` (a Lightroom Classic style sidecar).
- **Predictor tests check stable subsets of tags.** Tags near the threshold, like "river" on the night photo, flip with
  the resampling method.
- **`CommandLineToolTests` run the embedded command** with `Process`, which inherits the test host's sandbox. They pass
  an allowlisted environment, because the runner's variables would:
  - load XCTest into the command, which then ends the test run;
  - mirror `os_log` to the standard error (`OS_ACTIVITY_DT_MODE`);
  - make the command use the sandboxed file presenter.

  `CFFIXED_USER_HOME` is kept, so Core ML caches the compiled model in the container. The suite is serialized: when
  several commands create that cache at once, Core ML prints errors to the standard output.
- **Compiler crash workaround:** Swift 6.3 crashed (`SendNonSendable` pass) on test closures passed to
  `withTemporaryDirectory` that captured a `UserDefaults`. Create such objects outside the closure.
- **Sandboxed file access isn't covered by unit tests,** because the container has full access. Verify it end to end by
  opening files from outside the container with `open -a <built app> <files>`, with auto-save enabled in
  `~/Library/Containers/nuculabs.dev.ImageTagger/Data/Library/Preferences/nuculabs.dev.ImageTagger.plist`. Then check
  the files on disk, and reset the preference afterwards.
