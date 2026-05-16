# iOS Pipelines

Two reusable tools for iOS/Claude Code workflows:

1. **[App Store Asset Pipeline](#1-app-store-asset-pipeline)** — automate screenshot capture, framing, preview video recording, and App Store Connect upload
2. **[Claude Code Status Line](#2-claude-code-status-line)** — a rich single-line status bar for Claude Code showing git state, context usage, cost, and rate limits

---

## 1. App Store Asset Pipeline

See **`appstore-asset-pipeline-guide.md`** for the full step-by-step guide.

### Pipeline overview

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

### Requirements

- macOS with Xcode installed
- Ruby + Bundler (`gem install bundler`)
- Python 3 + pip
- ffmpeg (`brew install ffmpeg`) — only needed for preview video GIF conversion
- An App Store Connect API key (App Manager role)

### Prompt for your Claude agent

Give your agent `appstore-asset-pipeline-guide.md` and this prompt:

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

## 2. Claude Code Status Line

**`claude-statusline.sh`** is a shell script that renders a rich single-line status bar inside Claude Code. It's invoked automatically after every response.

### What it shows

```
📁 my-project | 💬 session-name | 🌿 main ✓2 !1 +3 +14-2 | [████████░░] 78% | 🤖 Sonnet 4.6 | 💰 23c | 📊 45% 2h30m | 🕐 14:32
```

| Segment | Description |
|---|---|
| `📁 project/subdir` | Current project + relative directory (bright blue) |
| `💬 session-name` | Session name if set (italic purple) |
| `🌿 branch` | Git branch (magenta) |
| `✓2 !1 +3` | Git state: staged files / unstaged files / untracked files |
| `+14-2` | Total lines added/deleted across staged + unstaged changes |
| `[████████░░] 78%` | Context window usage bar — green → yellow → red |
| `🤖 Model` | Active model name |
| `💰 23c` / `🔢 42K tok` | Session cost in cents (or token count before first API call) |
| `📊 45% 2h30m` | Rate limit usage + time until reset (5-hour / 7-day windows) |
| `🕐 14:32` | Current time |

### Installation

**1. Download the script**

```bash
curl -o ~/.claude/statusline.sh \
  https://raw.githubusercontent.com/TimoHolzherr/ios-pipelines/master/claude-statusline.sh
chmod +x ~/.claude/statusline.sh
```

Or clone and copy:

```bash
git clone https://github.com/TimoHolzherr/ios-pipelines.git
cp ios-pipelines/claude-statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

**2. Wire it into Claude Code**

Add the `statusLine` key to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/Users/YOUR_USERNAME/.claude/statusline.sh"
  }
}
```

Replace `YOUR_USERNAME` with your macOS username (`whoami`), or use `$HOME`:

```bash
# One-liner to add it (requires jq):
jq '. + {"statusLine": {"type": "command", "command": ($ENV.HOME + "/.claude/statusline.sh")}}' \
  ~/.claude/settings.json > /tmp/settings.tmp && mv /tmp/settings.tmp ~/.claude/settings.json
```

**3. Verify**

Restart Claude Code (or open a new session). The status bar should appear at the bottom of each response.

### Requirements

- `jq` — for parsing the JSON input (`brew install jq`)
- `git` — already on any dev machine
- `awk`, `date`, `basename` — standard POSIX tools, already present on macOS

### How it works

Claude Code invokes the script after each response, piping a JSON blob to stdin with fields like:

```json
{
  "workspace": { "project_dir": "/...", "current_dir": "/..." },
  "model": { "display_name": "Sonnet 4.6" },
  "cost": { "total_cost_usd": 0.23 },
  "context_window": { "used_percentage": 78, ... },
  "rate_limits": {
    "five_hour":  { "used_percentage": 45, "resets_at": 1234567890 },
    "seven_day":  { "used_percentage": 12, "resets_at": 1234567890 }
  },
  "session_name": "my-session"
}
```

The script parses this with `jq`, runs a few `git` commands against the project directory, and prints a single ANSI-coloured line via `printf "%b"`.

### Customisation

All the visual segments are assembled in the `LINE` variable near the bottom of the script — comment out any segment you don't want, or reorder them. Colours are defined as ANSI escape variables at the top (`BLUE`, `MAGENTA`, `GREEN`, etc.).
