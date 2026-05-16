# iOS Pipelines

Two reusable tools for iOS/Claude Code workflows.

---

## 1. App Store Asset Pipeline

Automate screenshot capture, framing with marketing copy, preview video recording, and App Store Connect upload for any Xcode project.

See **[appstore-asset-pipeline-guide.md](appstore-asset-pipeline-guide.md)** for the full guide and agent prompt.

---

## 2. Claude Code Status Line

A rich single-line status bar for Claude Code showing git state, context window usage, cost, and rate limits.

See **[claude-statusline.sh](claude-statusline.sh)** for the script. Install by copying it to `~/.claude/statusline.sh` and adding this to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/Users/YOUR_USERNAME/.claude/statusline.sh"
  }
}
```
