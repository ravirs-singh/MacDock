# MacDock

Turn your iPhone into a remote dock for your Mac: launch apps, control media and
volume, use the phone as a **trackpad and keyboard**, lock or sleep the Mac, and
run Shortcuts — all over your local Wi‑Fi.

**Trackpad tab:** one finger moves the pointer, tap clicks, double-tap double-clicks,
two-finger pan scrolls, two-finger tap right-clicks, press-and-hold then move drags.
The keyboard button forwards typing to the Mac; Esc/Tab/arrows are one tap away.

```
┌─────────────┐   Bonjour (_macdock._tcp)   ┌──────────────────────┐
│  iPhone app │ ──────── TCP / JSON ──────▶ │ MacDock Helper (menu │
│  (SwiftUI)  │ ◀───────────────────────── │ bar app, macOS)      │
└─────────────┘                             └──────────────────────┘
```

## Layout

| Path | What |
|---|---|
| `Shared/` | Swift package `MacDockProtocol` — commands, responses, wire framing |
| `MacDockHelper/` | macOS menu-bar app: Bonjour listener, PIN pairing, command executor |
| `MacDockiOS/` | iOS app: discovery, pairing screen, dock grid |
| `project.yml` | [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec that generates `MacDock.xcodeproj` |

## Build

```bash
brew install xcodegen
cd MacDock
xcodegen generate
open MacDock.xcodeproj
```

1. In Xcode, select your team under **Signing & Capabilities** for both targets
   (bundle IDs default to `in.brainsick.macdock` / `.helper` — change in `project.yml` if needed).
2. Run **MacDockHelper** (scheme → My Mac). A dock icon appears in the menu bar showing a 6‑digit PIN.
3. Run **MacDock** on your iPhone (same Wi‑Fi). Tap your Mac, enter the PIN once.

## Everyday use

- **Mac:** the first time the helper runs from anywhere other than `/Applications` it offers
  to copy itself there and relaunch (also available as **Install to Applications…** in the
  menu bar popover). Then turn on **Launch at login** and forget about it.
  `./install-helper.sh` does the same from the terminal with a Release build.
- **iPhone:** the app remembers the last Mac and reconnects automatically on launch and when
  returning from the background. **Disconnect** in the ⋯ menu forgets it and shows the picker.
- Free Personal Team builds expire after 7 days — re-run from Xcode (⌘R) to refresh.
  A paid developer account extends this to a year.

## First-run permissions on the Mac

- **Local Network** prompt — allow.
- **Automation / Apple Events** — needed for volume and Lock Screen (System Events). macOS prompts the first time.
- **Accessibility** (System Settings → Privacy & Security → Accessibility) — needed for the
  trackpad, keyboard and media keys, which are all posted as HID events. The helper asks on launch.

## Security model

- Pairing uses a one-time 6‑digit PIN displayed on the Mac; a random token is issued and stored on the iPhone (`UserDefaults`) and the Mac.
- The PIN rotates after every successful pairing. "Forget all devices" in the menu bar revokes every token.
- Traffic is plaintext on your LAN. If you want TLS, swap `NWParameters.tcp` for `NWParameters(tls:…)` with a self-signed cert pinned on the phone.

## Roadmap ideas

- Custom tiles (user-defined Shortcuts / URLs) with iCloud sync
- Live "now playing" info pushed from the Mac
- Widgets and Lock Screen controls on iPhone
- Apple Watch companion
