# PinShot

A free, open-source screenshot tool for macOS that keeps your captures **floating on top of everything**. Grab part of the screen, and it stays pinned right where it was — perfect for keeping a reference, a design, a code snippet or a chat message in view while you work.

## Features

- **⇧⌘2** to capture: drag to select an area, or **click a window** to capture just that window
- **⇧⌘1** to **capture text**: drag over any text — in an image, a video, a PDF, an app that won't let you select — and it's copied to your clipboard. QR codes and barcodes are read too
- The capture **floats above all windows**, exactly where you took it
- **Move** it by dragging, **resize** by scrolling, pinching or dragging its edges, **double-click** for 100%
- **Copy text** out of any capture with built-in text recognition (OCR) — no internet needed
- **Copy**, **save**, or **drag** a capture straight into Mail, Slack, Finder, a browser…
- **Opacity** and **click-through** mode, so you can work "underneath" a reference image
- A **library** of past captures — double-click to pin again, or drag them anywhere
- Full-screen capture from the menu bar
- Lives in the menu bar; change the shortcut and other options in Settings

## Capturing text

Press **⇧⌘1**, then drag over the text you want (or click a window). The recognized text goes straight to the clipboard — nothing is pinned or saved. If the area contains a QR code or barcode, its contents (for example a link) are copied as well. Recognition runs entirely on your Mac. In Settings you can choose whether line breaks are kept.

You can also copy the text out of any pin (⌘T) or library item later.

## Using a pin

Hover over a pin to show its toolbar:

| Button | Shortcut | Action |
|---|---|---|
| ✕ | Esc / ⌘W | Close |
| Copy | ⌘C | Copy the image |
| Text | ⌘T | Copy the text in the image |
| Save | ⌘S | Save as PNG |
| ✋ Drag | | Drag the image into another app |
| ⋯ | | Opacity, click-through, actual size, show in Finder |
| | ⌘+ / ⌘− / ⌘0 | Bigger / smaller / actual size |

Right-click a pin for the same options. If you turn on **click-through**, unlock it again from the menu bar icon → **Unlock Click-Through Pins**.

## Install

Requires **macOS 14.6 or later** (Apple Silicon or Intel).

1. Download the latest `PinShot-x.x.dmg` from [Releases](../../releases).
2. Open it and drag **PinShot** into **Applications**.
3. Open PinShot. macOS will say *"Apple could not verify PinShot is free of malware"* — this is expected, because PinShot isn't distributed through Apple's paid developer program. Click **Done**.
4. Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the PinShot message. Confirm with your password. You only do this once.

   If you see the same message when opening the `.dmg`, use **Open Anyway** for it in the same way.

   <details><summary>Prefer Terminal?</summary>

   ```bash
   xattr -dr com.apple.quarantine /Applications/PinShot.app
   ```
   </details>

5. Press **⇧⌘2**. PinShot will ask for **Screen Recording** permission — turn it on in **System Settings → Privacy & Security → Screen Recording**, then choose **Quit & Reopen PinShot**.

## Privacy

PinShot makes no network connections. Screen Recording permission is only used to take the screenshots you ask for — nothing is recorded in the background. Captures are stored only on your Mac, in `~/Library/Application Support/PinShot/Captures/` (open it from the Library window). Text recognition runs on your Mac.

## Build from source

Requires Xcode 16 or later.

```bash
git clone <this repo>
cd PinShot
open PinShot.xcodeproj
```

Then press ⌘R. Builds are signed with a self-signed certificate named "ClipVault Developer"; create your own code-signing certificate and change `CODE_SIGN_IDENTITY` in the project (and `SIGN_ID` in `scripts/release.sh`). To build a DMG:

```bash
./scripts/release.sh
```

## Related

- [ClipVault](https://github.com/shahmirfaisal/ClipVault) — a free clipboard manager for macOS
- [DropShelf](https://github.com/shahmirfaisal/DropShelf) — a free drag-and-drop shelf: shake while dragging to park files

## License

MIT — see [LICENSE](LICENSE).
