# iOS Pipelines

Two reusable tools for iOS/Claude Code workflows.

---

## 1. App Store Asset Pipeline

See **[appstore-asset-pipeline-guide.md](appstore-asset-pipeline-guide.md)** for the full guide.

**Prompt for Claude:**

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

## 2. Claude Code Status Line

See **[claude-statusline.sh](claude-statusline.sh)** for the script.

**Prompt for Claude:**

> Please install the Claude Code status line from `claude-statusline.sh` in this folder. Copy it to `~/.claude/statusline.sh`, make it executable, then add the `statusLine` key to `~/.claude/settings.json` pointing to that path. Show me the final settings snippet when done.
