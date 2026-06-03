# 🏃 The Long Run

> *Tired of running in The Long Dark? Here's The Long Run.*

A tiny macOS tool that **holds your sprint keys for you**. The Long Dark makes you trek for
real-time minutes with **W + Shift** pressed down — The Long Run turns that into a single
toggle. Tap a hotkey once to start auto-running, tap again to stop. Your fingers thank you.

It comes in two flavors:

| | **Menu-bar app** | **CLI** |
|---|---|---|
| Folder | `menubar/` | `cli/` |
| Runs as | menu-bar icon, no terminal | a terminal window |
| Pick keys | menu + live "record a key" | command-line flags |
| Best for | set-and-forget | scripting / tinkering |

Both work by holding the movement keys while a game is focused; The Long Dark (a Unity game)
reads the synthesized key events just like real ones.

---

## Quick start — menu-bar app (recommended)

```sh
cd menubar
./install.sh
open /Applications/TheLongRun.app
```

`install.sh` builds the app, signs it with a **stable identity**, and installs it to
`/Applications`. A little runner icon appears in your menu bar.

On first launch, macOS asks for two permissions — grant **both** for *TheLongRun*:

1. **System Settings ▸ Privacy & Security ▸ Input Monitoring**
2. **System Settings ▸ Privacy & Security ▸ Accessibility**

That's it. Open The Long Dark, tap your hotkey (default **`\`**), and run.

> **Grant once, forever.** Because every build uses the same stable signing identity, macOS
> remembers the permission across updates and no matter where the app lives — you never have
> to re-grant or hunt down the right copy.

### Using the app

Click the menu-bar icon (🚶 idle, 🏃 green while running):

- Each **bind** is a hotkey → a hold mode. Open a bind for:
  - **Start / Stop**
  - **Toggle key ▸** — quick-pick, or **"Record a key… (any key)"** then press any key
  - **Mode ▸** — Sprint (W+Shift), Walk (W), Sprint with ↑, Walk with ↑
  - **Remove this bind**
- **Add bind…** — make a new hotkey (records its key immediately)
- **Active in: …** — by default only acts when **The Long Dark is frontmost**, so your hotkey
  isn't swallowed in other apps. Switch to *Everywhere* or another app if you like.
- **One bind at a time** — starting one bind stops the others (on by default).
- **Key auto-repeat** — re-emits held keys for games that need repeat events (off by default).

**Stuck-key proof:** when the game loses focus (you Cmd-Tab away), all held keys are released
automatically.

---

## Quick start — CLI

```sh
go build -o tldrun ./cli
./tldrun                       # default: "\" toggles W+Shift, quit with F9
```

### Multiple keybinds

Repeat `--bind key=holdkeys` for several independent hotkeys:

```sh
./tldrun --bind x=w,shift --bind z=w        # X = sprint, Z = walk
./tldrun --bind x=w,shift --bind z=w --bind c=up,shift
```

| Flag | Meaning |
|---|---|
| `--bind key=holdkeys` | repeatable; a hotkey and the keys it holds. Modifiers (`shift`, `ctrl`, `alt`, `cmd`) set the right flag automatically. |
| `--quit` | key that exits and releases everything (default `f9`) |
| `--list-keys` | print every key name you can use |
| `--toggle` / `--hold` | shorthand for a single bind, used only when no `--bind` is given |

Keys can be a name (`backslash`), a literal (`=`), or a raw code (`42`).

The first run is blocked until you add your **terminal app** (Terminal / iTerm) to
Privacy & Security ▸ **Accessibility** *and* **Input Monitoring**, then run again.

---

## Building & packaging

All scripts live in `menubar/`:

| Script | What it does |
|---|---|
| `build.sh` | Compiles the app and signs it with the stable identity. |
| `install.sh` | `build.sh` + installs to `/Applications` (and removes the local copy). |
| `compile_dmg.sh` | Builds a shareable **`TheLongRun-1.1.dmg`** with a drag-to-Applications layout. |
| `reset-permissions.sh` | Clears The Long Run's privacy entries by bundle ID (no path hunting) — handy if an old build left stale entries. |
| `ensure-cert.sh` | Creates/reuses the stable self-signed signing identity. Called automatically by the others. |

```sh
cd menubar
./compile_dmg.sh        # → TheLongRun-1.1.dmg
```

> The DMG is **self-signed and not notarized**. On your own Mac it just works. On someone
> else's Mac, Gatekeeper will say "unidentified developer" — they right-click ▸ **Open** once
> to allow it. (Notarization needs a paid Apple Developer account.)

---

## Key codes (handy ones)

| Key | Code | Key | Code | Key | Code |
|----|----|----|----|----|----|
| `\` | 42 | W | 13 | Shift | 56 |
| `=` | 24 | A | 0 | Ctrl | 59 |
| `-` | 27 | S | 1 | Option | 58 |
| `[` | 33 | D | 2 | Cmd | 55 |
| `]` | 30 | Space | 49 | ↑ | 126 |
| `` ` `` | 50 | Tab | 48 | ↓ | 125 |
| F8 | 100 | F9 | 101 | ← / → | 123 / 124 |

Run `./tldrun --list-keys` for the full list. In the app, just **Record a key…** — it
captures anything.

---

## How it works

Both versions install a CoreGraphics keyboard **event tap**: they watch for your hotkey,
**consume** it (so it never reaches the game), and synthesize key-down / key-up events for the
hold keys. macOS requires Input Monitoring (to receive keys) and Accessibility (to post and
consume them) — that's why both permissions are needed.

---

## Notes & caveats

- Sprinting still drains condition/stamina in-game. This saves your fingers, not the rules. ❄️
- macOS function keys (F1–F12) send media keys by default — use `fn`+F-key, or enable
  *"Use F1, F2 as standard function keys"*, if you bind one. That's why the default is `\`.
- If a key ever feels stuck: tap the hotkey again, switch away from the game, or quit the tool
  (it releases everything on exit).
- Requires macOS 12+. The CLI needs Go to build; the app needs the Xcode command-line tools
  (`xcode-select --install`).

---

## License

[MIT](LICENSE). Have fun out there. 🐺
