# App Store Asset Pipeline — Complete Guide

A step-by-step guide for setting up an automated pipeline that:
1. Captures App Store screenshots from the iOS Simulator
2. Frames them with marketing copy (gradient backgrounds, styled headlines)
3. Records App Store preview videos
4. Uploads everything to App Store Connect

This guide is framework-agnostic — adapt the app names, bundle IDs, simulator UDIDs, and screenshot counts to your project.

---

## Overview

```
UI Test (XCTest)
      │  calls snapshot()
      ▼
SnapshotHelper → saves PNGs to ~/Library/Caches/tools.fastlane/screenshots/
      │
Fastfile :screenshots lane
      │  copies + renames PNGs
      ▼
graphics/screenshots/captured/en-US/iphone/*.png
graphics/screenshots/captured/en-US/ipad/*.png
      │
generate.py --config graphics/app-store/config.yaml
      │  draws gradient + headline + framed screenshot
      ▼
graphics/app-store/output/en-US/appstore_iphone/*.png
graphics/app-store/output/en-US/appstore_ipad/*.png
      │
Fastfile :deliver_metadata lane
      │  upload_to_app_store (deliver)
      ▼
App Store Connect
```

---

## Prerequisites

### System tools

```bash
# Xcode + command-line tools
xcode-select --install

# Ruby (Fastlane runs on Ruby)
brew install rbenv
rbenv install 3.2.2
rbenv global 3.2.2

# Bundler
gem install bundler

# Python 3 (for the asset generator)
brew install python3

# ffmpeg (for preview video GIF conversion)
brew install ffmpeg
```

### Fastlane

Create `ios/Gemfile`:

```ruby
source "https://rubygems.org"

gem "fastlane"
```

Then:

```bash
cd ios/
bundle install
```

Verify:

```bash
bundle exec fastlane --version
```

### Python dependencies

Create `scripts/requirements.txt`:

```
Pillow>=10.0.0
PyYAML>=6.0
fonttools>=4.0.0
```

Install:

```bash
pip3 install -r scripts/requirements.txt
```

---

## Part 1: Screenshot Capture

### 1.1 — Find your simulator UDIDs

```bash
xcrun simctl list devices available | grep -E "iPhone|iPad"
```

Note the UDIDs for the devices you want to capture (typically latest iPhone Pro Max + latest iPad Pro).

App Store Connect requires specific device sizes:
- **6.9" Display** — iPhone 16 Pro Max (1320×2868)
- **13" Display** — iPad Pro 13-inch M4 (2048×2732)

### 1.2 — Add SnapshotHelper to your UI test target

Fastlane's `snapshot` tool uses a helper file that must be compiled into your UI test bundle.

```bash
cd ios/
bundle exec fastlane snapshot init
```

This creates `fastlane/SnapshotHelper.swift`. Copy or symlink it into your UI test target folder (e.g. `YourAppUITests/SnapshotHelper.swift`) and add it to the Xcode project.

### 1.3 — Write a UI test that navigates and calls `snapshot()`

Create `YourAppUITests/ScreenshotTests.swift`:

```swift
import XCTest

@MainActor
final class ScreenshotTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        setupSnapshot(app)
        // Optional: pass a launch argument so your app loads canned data
        app.launchArguments = ["--screenshot-mode"]
        app.launch()
    }

    func testCaptureScreenshots() async throws {
        // Dismiss system permission alerts automatically
        addUIInterruptionMonitor(withDescription: "System Alert") { alert in
            alert.buttons.firstMatch.tap()
            return true
        }

        // Navigate to each screen and call snapshot()
        snapshot("01-home")

        app.buttons["Settings"].tap()
        try await Task.sleep(for: .seconds(0.5))
        snapshot("02-settings")

        // … add more screens …
    }
}
```

**Tips for reliable screenshot tests:**
- Add `--screenshot-mode` as a launch argument so the app can load deterministic seed data instead of real user data.
- Use `.accessibilityIdentifier` on key elements and target them with `app.buttons.matching(identifier: "my-id").firstMatch` — this is more stable than label matching.
- Use `addUIInterruptionMonitor` to auto-dismiss push notification prompts and other system dialogs that would break the flow.
- Always `waitForExistence(timeout:)` before tapping navigational elements.

### 1.4 — Prepare seed data for screenshot mode

The cleanest approach is to bundle a seed data file with the UI test target and load it at launch. Add a `.json` or custom format file to the test bundle, then read it in the app when `--screenshot-mode` is in `CommandLine.arguments`.

```swift
// In your app's startup code:
if CommandLine.arguments.contains("--screenshot-mode"),
   let path = ProcessInfo.processInfo.environment["SCREENSHOT_DATA_PATH"] {
    loadSeedData(from: URL(fileURLWithPath: path))
}
```

In the test setup:

```swift
if let dataURL = Bundle(for: type(of: self)).url(forResource: "screenshotdata", withExtension: "json") {
    app.launchEnvironment["SCREENSHOT_DATA_PATH"] = dataURL.path
}
```

### 1.5 — Write the Fastlane screenshots lane

Create `ios/fastlane/Fastfile`:

```ruby
default_platform(:ios)

platform :ios do

  desc "Capture App Store screenshots for iPhone and iPad"
  lane :screenshots do |options|
    verbose = options[:verbose] || ENV["VERBOSE"] == "1"
    q = ->(cmd, log_file: nil) {
      target = log_file ? "> '#{log_file}' 2>&1" : ">/dev/null 2>&1"
      verbose ? sh(cmd) : system("#{cmd} #{target}")
    }

    ios_root      = File.expand_path("..", __dir__)
    repo_root     = File.expand_path("..", ios_root)
    project_root  = ios_root
    cache_dir     = "#{ENV['HOME']}/Library/Caches/tools.fastlane"
    snap_src      = "#{cache_dir}/screenshots"
    derived_data  = "/tmp/yourapp-screenshots-derived"
    screenshots_root = "#{repo_root}/graphics/screenshots/captured"

    # ── Device list: key = output subfolder name ──────────────────────────────
    capture_devices = {
      "iphone" => {
        udid:        "REPLACE-WITH-IPHONE-UDID",   # xcrun simctl list devices
        device_name: "iPhone 16 Pro Max"
      },
      "ipad" => {
        udid:        "REPLACE-WITH-IPAD-UDID",
        device_name: "iPad Pro 13-inch (M4)"
      }
    }

    # Write fastlane cache files (SnapshotHelper reads these)
    q.call("mkdir -p '#{snap_src}'")
    q.call("printf 'en-US' > '#{cache_dir}/language.txt'")
    q.call("printf 'en_US' > '#{cache_dir}/locale.txt'")
    q.call("touch '#{cache_dir}/snapshot-launch_arguments.txt'")

    # ── 1. Boot simulators + set clean status bars ────────────────────────────
    capture_devices.each do |folder, device|
      udid     = device[:udid]
      snap_dst = "#{screenshots_root}/en-US/#{folder}"

      q.call("xcrun simctl boot #{udid} 2>/dev/null || true")
      q.call(
        "xcrun simctl status_bar #{udid} override " \
        "--time '9:41' " \
        "--batteryState charged --batteryLevel 100 " \
        "--wifiBars 3 --cellularMode active --cellularBars 4"
      )
      q.call("rm -rf '#{snap_dst}' && mkdir -p '#{snap_dst}'")
    end
    q.call("rm -f '#{snap_src}'/*.png 2>/dev/null || true")

    # ── 2. Build once (both simulators share arm64, so one build covers both) ──
    first_udid = capture_devices.values.first[:udid]
    UI.header("Building for testing...")
    q.call(
      "set -o pipefail && xcodebuild build-for-testing " \
      "-scheme YourAppScheme " \
      "-project '#{project_root}/YourApp.xcodeproj' " \
      "-destination 'platform=iOS Simulator,id=#{first_udid}' " \
      "-derivedDataPath '#{derived_data}'",
      log_file: "/tmp/snapshot-build.log"
    )

    # ── 3. Run UI tests in parallel on all devices ────────────────────────────
    threads = capture_devices.map do |folder, device|
      log_file = "/tmp/snapshot-#{folder}-xcodebuild.log"
      Thread.new do
        system(
          "xcodebuild test-without-building " \
          "-scheme YourAppScheme " \
          "-project '#{project_root}/YourApp.xcodeproj' " \
          "-destination 'platform=iOS Simulator,id=#{device[:udid]}' " \
          "-derivedDataPath '#{derived_data}' " \
          "-only-testing:YourAppUITests/ScreenshotTests/testCaptureScreenshots " \
          "> '#{log_file}' 2>&1"
        )
      end
    end
    threads.each(&:join)

    # ── 4. Copy screenshots, stripping device-name prefix ─────────────────────
    # SnapshotHelper saves files as "{DEVICE_NAME}-{snapshot_name}.png"
    capture_devices.each do |folder, device|
      snap_dst    = "#{screenshots_root}/en-US/#{folder}"
      device_name = device[:device_name]

      Dir.glob("#{snap_src}/*.png").each do |src_path|
        bare = File.basename(src_path).sub(/\A#{Regexp.escape(device_name)}-/, "")
        next if bare == File.basename(src_path)   # belongs to different device
        FileUtils.cp(src_path, "#{snap_dst}/#{bare}")
      end

      UI.success("#{folder.capitalize} → #{snap_dst}")
    end

    # ── 5. Restore status bars ─────────────────────────────────────────────────
    capture_devices.each do |_, device|
      q.call("xcrun simctl status_bar #{device[:udid]} clear")
    end
  end

end
```

Run it:

```bash
cd ios/
bundle exec fastlane screenshots
# Verbose mode (shows xcodebuild output):
VERBOSE=1 bundle exec fastlane screenshots
```

---

## Part 2: Asset Generation (Framed Screenshots)

### 2.1 — Folder structure

```
graphics/
  screenshots/
    captured/
      en-US/
        iphone/       ← raw PNGs from Fastlane
        ipad/
  app-store/
    config.yaml       ← describes output sizes and frames
    output/           ← generated framed images (git-ignored)
  source-images/
    download-on-the-app-store.png   ← Apple badge (download from Apple)
scripts/
  generate.py
  requirements.txt
```

### 2.2 — The config YAML

Create `graphics/app-store/config.yaml`:

```yaml
# Run: python3 scripts/generate.py --config graphics/app-store/config.yaml

screenshot_source: "../screenshots/captured"
output_dir: "output"

theme:
  gradient_top:          "#1A1A2E"   # dark top colour
  gradient_bottom:       "#16213E"   # lighter bottom colour
  screenshot_bleed:      0.12        # fraction of canvas height the screenshot extends below
  text:                  "#FFFFFF"
  highlight:             "#00D4AA"   # accent colour for *highlighted* words
  headline_font_size:    116
  subheadline_font_size: 72

languages:
  - en-US

output_sizes:
  appstore_iphone:
    width: 1320
    height: 2868
    screenshot_device: iphone
    label: "6.9\" Display (iPhone 16 Pro Max)"

  appstore_ipad:
    width: 2048
    height: 2732
    screenshot_device: ipad
    label: "13\" Display (iPad Pro M4)"

# Each frame: id matches output filename, screenshot matches raw PNG filename.
# Wrap *words* in asterisks for highlight colour.
frames:

  - id: "01-home"
    screenshot: "01-home.png"
    headline:
      en-US: "Your *Headline* Here"
    subheadline:
      en-US: "Supporting message in smaller text"

  - id: "02-settings"
    screenshot: "02-settings.png"
    headline:
      en-US: "Another *Great* Feature"

  # Testimonial frame: no screenshot, just text on gradient
  - id: "03-testimonial"
    headline:
      en-US: "\"A quote from a real user who loves your app.\""
```

### 2.3 — The generator script

Save the following as `scripts/generate.py`. It reads the config YAML, composites each frame, and saves PNGs ready for App Store Connect.

```python
#!/usr/bin/env python3
"""
App Store asset generator.
Renders framed screenshots from a YAML config.

Usage:
  python3 scripts/generate.py --config graphics/app-store/config.yaml
  python3 scripts/generate.py --config graphics/app-store/config.yaml --lang en-US --size appstore_iphone
  python3 scripts/generate.py --config graphics/app-store/config.yaml --frame 01-home
"""

import argparse
import os
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("Missing: pip3 install pyyaml")
    sys.exit(1)

try:
    from PIL import Image, ImageDraw, ImageFont, ImageFilter
except ImportError:
    print("Missing: pip3 install pillow")
    sys.exit(1)


# ── Font loading ──────────────────────────────────────────────────────────────

_FONT_CACHE_DIR = Path(__file__).parent / ".font_cache"
_mem_cache: dict = {}

def _sf_rounded_path(weight: int) -> str:
    """Instantiate SFNSRounded at a static weight. Cached to disk (~8s first run)."""
    _FONT_CACHE_DIR.mkdir(exist_ok=True)
    cached = _FONT_CACHE_DIR / f"SFNSRounded-w{weight}.ttf"
    if cached.exists():
        return str(cached)
    print(f"  [font] Instantiating SFNSRounded w{weight} (one-time, ~8s)…")
    from fontTools.ttLib import TTFont
    from fontTools.varLib.instancer import instantiateVariableFont
    tt = TTFont("/System/Library/Fonts/SFNSRounded.ttf")
    instantiateVariableFont(tt, {"wght": weight}).save(str(cached))
    return str(cached)

def load_font(size: int, weight: int = 400) -> ImageFont.FreeTypeFont:
    """Load SFNSRounded at a given weight/size, fall back to Arial."""
    key = (weight, size)
    if key in _mem_cache:
        return _mem_cache[key]
    try:
        font = ImageFont.FreeTypeFont(_sf_rounded_path(weight), size)
    except Exception as e:
        print(f"  [warn] SF Rounded unavailable ({e}), using Arial")
        path = ("/System/Library/Fonts/Supplemental/Arial Bold.ttf" if weight >= 600
                else "/System/Library/Fonts/Supplemental/Arial.ttf")
        font = (ImageFont.truetype(path, size) if Path(path).exists()
                else ImageFont.load_default())
    _mem_cache[key] = font
    return font


# ── Colour helpers ────────────────────────────────────────────────────────────

def hex_to_rgb(h: str) -> tuple:
    h = h.lstrip("#")
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))


# ── Gradient ──────────────────────────────────────────────────────────────────

def draw_gradient(canvas: Image.Image, top: tuple, bottom: tuple):
    draw = ImageDraw.Draw(canvas)
    W, H = canvas.size
    for y in range(H):
        t = y / max(H - 1, 1)
        color = tuple(int(top[c] * (1 - t) + bottom[c] * t) for c in range(3))
        draw.line([(0, y), (W, y)], fill=color)


# ── Styled text (*highlighted* spans) ────────────────────────────────────────

def parse_styled_words(text: str) -> list:
    parts = re.split(r'\*([^*]+)\*', text)
    result = []
    for i, part in enumerate(parts):
        highlighted = i % 2 == 1
        for word in part.split():
            result.append((word, highlighted))
    return result

def _word_w(draw, word, font):
    bbox = draw.textbbox((0, 0), word, font=font)
    return bbox[2] - bbox[0]

_PUNCT_START = set('.,!?;:)\'"…')

def _gap(word: str, space_w: int) -> int:
    return 0 if (word and word[0] in _PUNCT_START) else space_w

def wrap_styled(draw, words, font_normal, font_hl, max_w) -> list:
    space_w = _word_w(draw, " ", font_normal)
    lines, line, line_w = [], [], 0
    for word, hl in words:
        ww  = _word_w(draw, word, font_hl if hl else font_normal)
        gap = _gap(word, space_w) if line else 0
        if line and line_w + gap + ww > max_w:
            lines.append(line)
            line, line_w = [(word, hl)], ww
        else:
            line.append((word, hl))
            line_w += gap + ww
    if line:
        lines.append(line)
    return lines

def draw_styled_lines(draw, lines, font_normal, font_hl, color_normal, color_hl,
                      canvas_w, y, line_gap=14) -> int:
    space_w = _word_w(draw, " ", font_normal)
    line_h  = max(font_normal.size, font_hl.size)
    for line in lines:
        total_w = sum(_word_w(draw, w, font_hl if hl else font_normal) for w, hl in line)
        total_w += sum(_gap(w, space_w) for w, _ in line[1:])
        x = (canvas_w - total_w) // 2
        for i, (word, hl) in enumerate(line):
            font  = font_hl  if hl else font_normal
            color = color_hl if hl else color_normal
            if i > 0:
                x += _gap(word, space_w)
            draw.text((x, y), word, font=font, fill=color)
            x += _word_w(draw, word, font)
        y += line_h + line_gap
    return y


# ── Frame renderer ────────────────────────────────────────────────────────────

def render_frame(cfg, frame, size_cfg, lang, screenshot_path, output_path):
    W = size_cfg["width"]
    H = size_cfg["height"]
    theme = cfg["theme"]

    grad_top    = hex_to_rgb(theme.get("gradient_top",    "#1A1A2E"))
    grad_bottom = hex_to_rgb(theme.get("gradient_bottom", "#16213E"))
    color_text  = hex_to_rgb(theme.get("text",            "#FFFFFF"))
    color_hl    = hex_to_rgb(theme.get("highlight",       "#00D4AA"))

    hl_size  = size_cfg.get("headline_font_size",    theme.get("headline_font_size",    90))
    sub_size = size_cfg.get("subheadline_font_size", theme.get("subheadline_font_size", 52))

    font_hl  = load_font(hl_size,  weight=700)
    font_sub = load_font(sub_size, weight=700)

    headline_text    = frame.get("headline",    {}).get(lang, "")
    subheadline_text = frame.get("subheadline", {}).get(lang, "")

    padding  = int(W * 0.07)
    text_w   = W - padding * 2
    text_top = int(H * 0.055)
    gap      = int(H * 0.018)

    bleed    = int(H * theme.get("screenshot_bleed", 0.0))
    shot_top = int(H * 0.25)
    shot_h   = H - shot_top + bleed
    shot_w   = W - padding * 2

    canvas = Image.new("RGB", (W, H))
    draw_gradient(canvas, grad_top, grad_bottom)

    if screenshot_path and Path(screenshot_path).exists():
        shot_img = Image.open(screenshot_path).convert("RGB")
        aspect = shot_img.width / shot_img.height
        new_h  = shot_h
        new_w  = int(new_h * aspect)
        if new_w > shot_w:
            new_w = shot_w
            new_h = int(new_w / aspect)
        shot_img  = shot_img.resize((new_w, new_h), Image.LANCZOS)
        sx        = (W - new_w) // 2
        sy        = shot_top + (shot_h - new_h) // 2
        corner_r  = int(new_w * 0.055)

        shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).rounded_rectangle(
            [sx + 10, sy + 14, sx + new_w + 10, sy + new_h + 14],
            radius=corner_r, fill=(0, 0, 0, 110)
        )
        shadow = shadow.filter(ImageFilter.GaussianBlur(20))
        canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow).convert("RGB")

        mask = Image.new("L", (new_w, new_h), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, new_w, new_h], radius=corner_r, fill=255)
        canvas.paste(shot_img, (sx, sy), mask=mask)

    dummy = ImageDraw.Draw(Image.new("RGB", (W, H)))
    hl_lines  = wrap_styled(dummy, parse_styled_words(headline_text),    font_hl,  font_hl,  text_w) if headline_text    else []
    sub_lines = wrap_styled(dummy, parse_styled_words(subheadline_text), font_sub, font_sub, text_w) if subheadline_text else []

    draw = ImageDraw.Draw(canvas)
    cy   = text_top
    if hl_lines:
        cy = draw_styled_lines(draw, hl_lines, font_hl, font_hl, color_text, color_hl, W, cy, line_gap=14)
    if hl_lines and sub_lines:
        cy += gap
    if sub_lines:
        draw_styled_lines(draw, sub_lines, font_sub, font_sub, color_text, color_hl, W, cy, line_gap=12)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output_path, "PNG")
    try:
        display = output_path.relative_to(Path.cwd())
    except ValueError:
        display = output_path
    print(f"  ✓ {display}")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--lang",   default=None)
    parser.add_argument("--size",   default=None)
    parser.add_argument("--frame",  default=None)
    args = parser.parse_args()

    config_path = Path(args.config).resolve()
    if not config_path.exists():
        print(f"Config not found: {config_path}")
        sys.exit(1)

    with open(config_path) as f:
        cfg = yaml.safe_load(f)

    config_dir   = config_path.parent
    output_base  = config_dir / cfg.get("output_dir", "output")
    shot_root    = (config_dir / cfg["screenshot_source"]).resolve()
    languages    = cfg.get("languages", ["en-US"])
    output_sizes = cfg.get("output_sizes", {})
    frames       = cfg.get("frames", [])

    if args.lang:  languages    = [l for l in languages if l == args.lang]
    if args.size:  output_sizes = {k: v for k, v in output_sizes.items() if k == args.size}
    if args.frame: frames       = [f for f in frames if f["id"] == args.frame]

    total = 0
    for lang in languages:
        for size_name, size_cfg in output_sizes.items():
            device   = size_cfg.get("screenshot_device", "iphone")
            shot_dir = shot_root / "en-US" / device
            print(f"\n[{lang} / {size_name}]  {size_cfg['width']}×{size_cfg['height']}")
            for frame in frames:
                shot_name = frame.get("screenshot", "")
                shot_path = str(shot_dir / shot_name) if shot_name else None
                out_file  = output_base / lang / size_name / f"{frame['id']}.png"
                render_frame(cfg, frame, size_cfg, lang, shot_path, out_file)
                total += 1

    print(f"\nGenerated {total} asset(s) → {output_base}")

if __name__ == "__main__":
    main()
```

Run it:

```bash
python3 scripts/generate.py --config graphics/app-store/config.yaml

# Only regenerate one frame:
python3 scripts/generate.py --config graphics/app-store/config.yaml --frame 01-home

# Only iPhone:
python3 scripts/generate.py --config graphics/app-store/config.yaml --size appstore_iphone
```

**Notes on the font:**
- The script uses `SFNSRounded.ttf` (available on every Mac at `/System/Library/Fonts/SFNSRounded.ttf`).
- The first run per weight (~400, 700) takes ~8 seconds to instantiate the variable font into a static `.ttf`; results are cached in `scripts/.font_cache/`.
- Add `scripts/.font_cache/` to `.gitignore`.
- On non-Mac CI, replace `load_font()` with `ImageFont.truetype("path/to/your/font.ttf", size)`.

---

## Part 3: Preview Video Recording (optional)

If you want App Store preview videos in addition to screenshots, add this lane to your `Fastfile`. The key idea is a **sentinel file handshake**: the UI test writes a file to `/tmp/` when recording should start and another when it should stop, so the recording brackets exactly the interesting content.

### 3.1 — Add sentinel signals to your video UI test

```swift
import XCTest

@MainActor
final class VideoTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--screenshot-mode"]
        app.launch()
    }

    func testVideoHomeScreen() async throws {
        let ready = URL(fileURLWithPath: "/tmp/yourapp-video-ready")
        let done  = URL(fileURLWithPath: "/tmp/yourapp-video-done")

        // Navigate to starting position BEFORE signalling ready
        XCTAssertTrue(app.buttons["HomeTab"].waitForExistence(timeout: 10))
        app.buttons["HomeTab"].tap()
        try await Task.sleep(for: .seconds(1))

        // Signal: start recording now
        try Data().write(to: ready)

        // Perform the interesting sequence
        app.buttons["SomeFeature"].tap()
        try await Task.sleep(for: .seconds(3))
        app.swipeUp()
        try await Task.sleep(for: .seconds(2))

        // Signal: stop recording (before any teardown / home screen transition)
        try Data().write(to: done)
        try await Task.sleep(for: .seconds(0.5))
    }
}
```

### 3.2 — Add the preview_videos lane

```ruby
desc "Record App Store preview videos"
lane :preview_videos do |options|
  verbose     = options[:verbose] || ENV["VERBOSE"] == "1"
  ios_root    = File.expand_path("..", __dir__)
  repo_root   = File.expand_path("..", ios_root)
  output_dir  = "#{repo_root}/graphics/videos/screen-captures"
  derived     = "/tmp/yourapp-screenshots-derived"
  udid        = "REPLACE-WITH-IPHONE-UDID"

  system("mkdir -p '#{output_dir}'")
  system("which ffmpeg >/dev/null 2>&1 || brew install ffmpeg")

  system("xcrun simctl boot #{udid} 2>/dev/null || true")
  system(
    "xcrun simctl status_bar #{udid} override " \
    "--time '9:41' --batteryState charged --batteryLevel 100 " \
    "--wifiBars 3 --cellularMode active --cellularBars 4"
  )
  system("defaults write com.apple.iphonesimulator ShowSingleTouches 1")

  # Build once (reuse derived-data from screenshots lane if available)
  system(
    "set -o pipefail && xcodebuild build-for-testing " \
    "-scheme YourAppScheme " \
    "-project '#{ios_root}/YourApp.xcodeproj' " \
    "-destination 'platform=iOS Simulator,id=#{udid}' " \
    "-derivedDataPath '#{derived}' > /tmp/video-build.log 2>&1"
  )

  videos = [
    { name: "01-home",     test: "testVideoHomeScreen"    },
    { name: "02-feature",  test: "testVideoFeatureScreen" },
  ]

  ready_signal = "/tmp/yourapp-video-ready"
  done_signal  = "/tmp/yourapp-video-done"

  videos.each do |video|
    out_path = "#{output_dir}/#{video[:name]}.mp4"
    UI.header("Recording #{video[:name]}...")

    system("rm -f '#{ready_signal}' '#{done_signal}'")

    log = "/tmp/video-#{video[:name]}.log"
    test_thread = Thread.new do
      system(
        "xcodebuild test-without-building " \
        "-scheme YourAppScheme " \
        "-project '#{ios_root}/YourApp.xcodeproj' " \
        "-destination 'platform=iOS Simulator,id=#{udid}' " \
        "-derivedDataPath '#{derived}' " \
        "-only-testing:YourAppUITests/VideoTests/#{video[:test]} " \
        "> '#{log}' 2>&1"
      )
    end

    # Wait for ready signal (up to 45 s)
    90.times { break if File.exist?(ready_signal); sleep(0.5) }

    record_pid = Process.spawn(
      "xcrun simctl io #{udid} recordVideo '#{out_path}' --codec h264 --force"
    )
    sleep(0.4)

    until File.exist?(done_signal) || !test_thread.alive?
      sleep(0.3)
    end
    sleep(0.2)

    Process.kill("INT", record_pid)
    Process.wait(record_pid)
    sleep(1.0)

    test_thread.join
    UI.success("Saved → #{out_path}")

    # Convert to GIF for web embedding
    gif     = out_path.sub(/\.mp4$/, ".gif")
    palette = out_path.sub(/\.mp4$/, "_palette.png")
    system("ffmpeg -y -i '#{out_path}' -vf 'fps=15,scale=480:-1:flags=lanczos,palettegen' '#{palette}' >/dev/null 2>&1")
    system("ffmpeg -y -i '#{out_path}' -i '#{palette}' -lavfi 'fps=15,scale=480:-1:flags=lanczos[v];[v][1:v]paletteuse' '#{gif}' >/dev/null 2>&1")
    system("rm -f '#{palette}'")
    UI.success("GIF → #{gif}")
  end

  system("xcrun simctl status_bar #{udid} clear")
  system("defaults write com.apple.iphonesimulator ShowSingleTouches 0")
end
```

---

## Part 4: Upload to App Store Connect

### 4.1 — Generate an App Store Connect API key

1. Go to App Store Connect → Users & Access → Integrations → App Store Connect API
2. Create a key with **App Manager** role
3. Note the **Key ID** and **Issuer ID**
4. Download the `.p8` file — store it at `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`

### 4.2 — Set up Fastlane metadata folder

```
ios/fastlane/metadata/
  en-US/
    release_notes.txt      ← what's new in this version
    description.txt        ← full App Store description
    keywords.txt           ← comma-separated keywords
    promotional_text.txt   ← short promo text (optional)
```

`release_notes.txt` example:
```
- Improved performance on older devices
- Fixed a crash when opening the settings screen
- New dark mode support
```

### 4.3 — Add the deliver_metadata lane

```ruby
desc "Upload screenshots and release notes to App Store Connect"
lane :deliver_metadata do
  api_key = app_store_connect_api_key(
    key_id:       "YOUR_KEY_ID",
    issuer_id:    "YOUR_ISSUER_ID",
    key_filepath: "#{ENV['HOME']}/.appstoreconnect/private_keys/AuthKey_YOUR_KEY_ID.p8"
  )

  require 'tmpdir'
  require 'fileutils'

  repo_root       = File.expand_path("../..", __dir__)
  tmp_screenshots = Dir.mktmpdir("deliver_screenshots")
  tmp_locale      = File.join(tmp_screenshots, "en-US")
  FileUtils.mkdir_p(tmp_locale)

  # Flatten device subfolders into a single temp directory
  # deliver expects filenames prefixed with device type
  iphone_files = Dir.glob("#{repo_root}/graphics/app-store/output/en-US/appstore_iphone/*.png")
  ipad_files   = Dir.glob("#{repo_root}/graphics/app-store/output/en-US/appstore_ipad/*.png")

  UI.message("Found #{iphone_files.count} iPhone + #{ipad_files.count} iPad screenshots")
  iphone_files.each { |f| FileUtils.cp(f, File.join(tmp_locale, "iphone_#{File.basename(f)}")) }
  ipad_files.each   { |f| FileUtils.cp(f, File.join(tmp_locale, "ipad_#{File.basename(f)}"))   }

  release_notes_path = File.join(__dir__, "metadata", "en-US", "release_notes.txt")
  release_notes_text = File.read(release_notes_path)

  begin
    upload_to_app_store(
      api_key:                        api_key,
      app_identifier:                 "com.your.bundleid",
      skip_binary_upload:             true,
      screenshots_path:               tmp_screenshots,
      metadata_path:                  "./metadata",
      release_notes:                  { "en-US" => release_notes_text },
      overwrite_screenshots:          true,
      force:                          true,
      precheck_include_in_app_purchases: false,
      app_version:                    "1.0.0"   # update each release
    )
  ensure
    FileUtils.remove_entry_secure(tmp_screenshots)
  end
end
```

Run it:

```bash
cd ios/
bundle exec fastlane deliver_metadata
```

### 4.4 — Set up `ios/fastlane/Appfile`

```ruby
app_identifier("com.your.bundleid")
apple_id("your@email.com")
```

---

## Part 5: Pipeline Script (Orchestrator)

Create `scripts/pipeline.sh` to tie it all together:

```bash
#!/bin/bash
# Asset pipeline
#
# Usage:
#   ./scripts/pipeline.sh              Generate framed assets only
#   ./scripts/pipeline.sh --screenshots  Capture fresh screenshots via Fastlane
#   ./scripts/pipeline.sh --videos       Record App Store preview videos
#   ./scripts/pipeline.sh --all          Capture + record + generate all assets

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IOS_DIR="$REPO_DIR/ios"
GRAPHICS_DIR="$REPO_DIR/graphics"

DO_SCREENSHOTS=false
DO_VIDEOS=false
DO_ASSETS=true

for arg in "$@"; do
  case "$arg" in
    --screenshots) DO_SCREENSHOTS=true; DO_ASSETS=false ;;
    --videos)      DO_VIDEOS=true;      DO_ASSETS=false ;;
    --all)         DO_SCREENSHOTS=true; DO_VIDEOS=true; DO_ASSETS=true ;;
    *) echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

if $DO_SCREENSHOTS; then
  echo "==> Capturing screenshots..."
  cd "$IOS_DIR"
  bundle exec fastlane screenshots
fi

if $DO_VIDEOS; then
  echo "==> Recording preview videos..."
  cd "$IOS_DIR"
  bundle exec fastlane preview_videos
fi

if $DO_ASSETS; then
  echo "==> Installing Python dependencies..."
  pip3 install -q -r "$REPO_DIR/scripts/requirements.txt"

  echo "==> Generating App Store assets..."
  python3 "$REPO_DIR/scripts/generate.py" --config "$GRAPHICS_DIR/app-store/config.yaml"
fi

echo ""
echo "Done."
if $DO_ASSETS; then
  echo "  Framed screenshots → $GRAPHICS_DIR/app-store/output/"
fi
if $DO_VIDEOS; then
  echo "  Preview videos     → $GRAPHICS_DIR/videos/screen-captures/"
fi
echo ""
echo "Next: cd ios && bundle exec fastlane deliver_metadata"
```

```bash
chmod +x scripts/pipeline.sh
```

---

## Part 6: App Store Connect Screenshot Naming

Fastlane's `deliver` tool determines which device slot a screenshot goes into based on the **filename prefix**. The `deliver_metadata` lane prefixes files with `iphone_` or `ipad_` before uploading. Deliver maps them to display sizes automatically based on image dimensions:

| Dimensions   | Slot |
|---|---|
| 1320×2868    | 6.9" iPhone (16 Pro Max) |
| 1290×2796    | 6.7" iPhone (15 Plus) |
| 2048×2732    | 13" iPad Pro |

Only supply the sizes you want to fill. If you submit without screenshots for a device size, the previous ones remain.

---

## Troubleshooting

**`snapshot()` writes no files**
- Check that `SnapshotHelper.swift` is in the UI test target's Compile Sources.
- Check that the fastlane cache files exist: `ls ~/Library/Caches/tools.fastlane/`.
- Run with `VERBOSE=1 bundle exec fastlane screenshots` and check `/tmp/snapshot-iphone-xcodebuild.log`.

**xcodebuild test fails**
- Make sure the simulator is booted: `xcrun simctl list devices booted`.
- The derived data path must be writable by the current user.
- Verify the scheme name and `.xcodeproj` path are correct.

**Font not found**
- `SFNSRounded.ttf` ships with macOS. If running on CI (Linux), set `FONT_PATH` to a TTF you bundle yourself and replace the `load_font()` call.

**deliver fails: "No screenshots found"**
- The temp directory must contain a locale folder (`en-US/`) with PNGs directly inside it (not in sub-folders).
- File names must start with `iphone_` or `ipad_` for deliver to classify them.

**App Store Connect API key rejected**
- Ensure the `.p8` file path is absolute and the file exists.
- The key must have at least App Manager role.
- Issuer ID and Key ID must match exactly what's shown in App Store Connect.

---

## `.gitignore` additions

```gitignore
# Generated assets
graphics/app-store/output/
graphics/insta/output/
graphics/videos/screen-captures/*.mp4
graphics/videos/screen-captures/*.gif
graphics/screenshots/captured/

# Font cache (regenerates automatically)
scripts/.font_cache/

# Fastlane
ios/fastlane/report.xml
ios/fastlane/logs/
```
