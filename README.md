# iOS App Store Asset Pipeline

A complete, reusable pipeline for automating App Store screenshot capture, framing with marketing copy, preview video recording, and uploading to App Store Connect — for any Xcode-based iOS project.

## What's in this repo

- **`appstore-asset-pipeline-guide.md`** — the full step-by-step guide covering every part of the pipeline
- **`README.md`** — this file, plus the prompt to give your Claude agent to implement it

## Prompt for your Claude agent

Give your agent the guide file and this prompt:

---

> I want to set up an automated App Store asset pipeline for my Xcode iOS project. I'm attaching a guide that documents a complete working pipeline. Please read through it and help me implement it for my project. Here's what I need you to do:
>
> 1. **Check my project structure** — find my `.xcodeproj`, scheme name, bundle ID, and UI test targets.
> 2. **Find simulator UDIDs** — run `xcrun simctl list devices available` and identify the best iPhone Pro Max and iPad Pro simulators to use.
> 3. **Set up Fastlane** — create `ios/Gemfile`, `ios/fastlane/Appfile`, and `ios/fastlane/Fastfile` with the `screenshots` and `deliver_metadata` lanes, substituting my actual scheme name, project name, bundle ID, and simulator UDIDs.
> 4. **Add SnapshotHelper** — run `cd ios && bundle exec fastlane snapshot init` then add the generated file to my UI test target in Xcode.
> 5. **Create the screenshot UI test** — write `testCaptureScreenshots()` that navigates through my app's key screens. Ask me which screens to capture and in what order before writing the test.
> 6. **Create the asset generator config** — create `graphics/app-store/config.yaml` with my brand colours, font sizes, and one frame per screenshot. Ask me for the headline text for each frame.
> 7. **Copy `generate.py` and `requirements.txt`** exactly from the guide into `scripts/`.
> 8. **Create `scripts/pipeline.sh`** from the guide.
> 9. **Set up the `deliver_metadata` lane** — ask me for my App Store Connect Key ID, Issuer ID, and `.p8` file path before writing the lane.
> 10. **Test each step** in order: first run `bundle exec fastlane screenshots` and verify PNGs appear, then run `generate.py` and verify framed images appear, then do a dry-run of `deliver_metadata`.
>
> Start by exploring the repo structure, then ask me any clarifying questions before making changes.

---

## Pipeline overview

```
UI Test (XCTest + SnapshotHelper)
      │  calls snapshot()
      ▼
Fastfile :screenshots lane
      │  captures PNGs via xcodebuild test-without-building
      ▼
graphics/screenshots/captured/en-US/{iphone,ipad}/*.png
      │
generate.py --config graphics/app-store/config.yaml
      │  composites gradient + headline + framed screenshot
      ▼
graphics/app-store/output/en-US/{appstore_iphone,appstore_ipad}/*.png
      │
Fastfile :deliver_metadata lane  (upload_to_app_store)
      │
App Store Connect
```

## Requirements

- macOS with Xcode installed
- Ruby + Bundler (`gem install bundler`)
- Python 3 + pip
- ffmpeg (`brew install ffmpeg`) — only needed for preview video GIF conversion
- An App Store Connect API key (App Manager role)
