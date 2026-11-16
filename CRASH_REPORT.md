# Getting logs out of Scopa: Four Realms

> **Built and tested on Godot 4.7.2** (and still audited green on 4.4.1). Requires **4.4 or newer**.

## If the game freezes your VM

Do not debug a renderer inside the VM you are working in. Run the headless
checks first — they create no window and no GPU context, so they cannot wedge
anything:

```bash
GODOT=/path/to/godot ./safe-check.sh       # import + boot + 57 self-tests
GODOT=/path/to/godot ./safe-check.sh log   # the log from the frozen run
```

**The renderer was the cause of the earlier freeze.** An interim change switched
this project from GL Compatibility to Vulkan/Metal (`mobile`); on a GPU-poor or
virtualised machine that can hard-lock the graphics driver instead of failing
cleanly — no error, no window, just a wedged VM. It is now back on
`gl_compatibility`, with `rendering_device/fallback_to_vulkan=false` so the
engine can never silently escalate to Vulkan.

If you ever change the renderer yourself, note the trade-off:

| Rendering method | Risk on a VM |
|---|---|
| `gl_compatibility` (current) | safest; software/llvmpipe friendly |
| `mobile` (Vulkan/Metal) | can lock the GPU driver on old/virtual GPUs |
| `forward_plus` (Vulkan) | same, plus more GPU work |

Everything in this game is 2D vector drawing, so Compatibility loses nothing.

### After a freeze, the log is still there

Verified by killing a running instance with SIGKILL: the log file retains every
line written up to the kill. So after End Task, run `./safe-check.sh log`.

A `[scopa] heartbeat ... stage=...` line every 5 seconds proves the process was
alive but stuck, and tells you which screen it was stuck on. **No heartbeat at
all** means it died before the main loop — a renderer/display failure, not a
script bug. A `[scopa] stage -> ...` line with nothing after it localises the
hang to that transition.

## Read this first: headless output is not a rendering test

`--headless` forces Godot's **dummy renderer**, so it never touches your GPU, your
window, or your drivers. On 4.7.2 headless all 57 automated checks pass while a
real window can still fail to open. If the game dies with **no script errors** in
headless but not on your machine, the fault is in the display/render layer — the
log line described below tells me which one.

Two ways, depending on whether the game closes itself or just sits there.

---

## 1. Run it from a terminal (best — catches engine crashes too)

The terminal window keeps everything, including engine-level crashes that never
reach the game's own log.

### Godot editor (Easiest)

Open the project, then **Editor → Open Editor Log…** (or press the **Output** panel's
**Errors** tab), press **F5**, reproduce the crash, and copy the panel.

### Windows

```bat
:: the editor ships with a console build — use the *console* exe
"%LOCALAPPDATA%\Programs\Godot\Godot_v4.4.1-stable_win64_console.exe" ^
  --path "C:\path\to\scopa-four-realms" --verbose > "%USERPROFILE%\Desktop\scopa-log.txt" 2>&1
```

If you use the plain `.exe`, the console output is hidden — the `_console.exe`
beside it is the one that prints.

### macOS

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --path ~/Documents/scopa-four-realms --verbose 2>&1 | tee ~/Desktop/scopa-log.txt
```

### Linux

```bash
godot --path ~/scopa-four-realms --verbose 2>&1 | tee ~/Desktop/scopa-log.txt
```

Then **reproduce the crash** and send `scopa-log.txt`. It's plain text — you can
paste it straight into the chat, or attach the file.

---

## 2. The game's own log file (no terminal needed)

This project writes a log to disk every run (enabled in `project.godot`).

> **Note the folder name:** Godot sanitises the project title, so search for
> `Scopa*`, not `Scopa: Four Realms` — on Windows/Linux it is literally
> `Scopa- Four Realms` (colon → dash).

| Platform | Log folder |
|---|---|
| Windows | `%APPDATA%\Godot\app_userdata\Scopa- Four Realms\logs\` |
| macOS | `~/Library/Application Support/Godot/app_userdata/Scopa- Four Realms/logs/` |
| Linux | `~/.local/share/godot/app_userdata/Scopa- Four Realms/logs/` |
| Android | `adb logcat -s godot` |

`godot.log` is the current session; earlier sessions are kept as
`godot2026-11-16T00.50.34.log`, so a crash that kills the process still leaves
the previous run on disk. There's a helper in the project root:

```bash
./logs.sh          # prints the folder and the last 120 lines
./logs.sh copy     # prints just the folder path
```

After a crash, open that `godot.log` and send the **last ~150 lines** — the crash
is at the very end. On desktop, Godot keeps the previous session as `godot.log.old`
if the crash killed the process before it could flush.

---

## The environment block

Every run now prints this at boot and into the log:

```
[scopa] ---- environment ----
[scopa] godot      : 4.7.2-stable (official)  (Windows)
[scopa] rendering  : mobile / driver vulkan · gl driver opengl3
[scopa] adapter    : NVIDIA GeForce RTX 3060 · NVIDIA Corporation
[scopa] display    : windows · window (540, 960) · screen (2560, 1440)
[scopa] viewport   : (720.0, 1280.0)
[scopa] log file   : C:/Users/you/AppData/Roaming/Godot/app_userdata/Scopa- Four Realms/logs/godot.log
[scopa] ---------------------
```

Send those six lines and I can usually tell what failed before seeing the trace.
If `adapter` says *(none — headless/dummy)*, you ran with `--headless` and it
proves nothing about rendering.

## What I need in the report

Anything you can give, in rough order of usefulness:

1. **The last 100–150 lines of the log** (the `ERROR:`/`SCRIPT ERROR:` block near the end).
2. **Which screen it crashed on** — title screen, or after pressing a mode button?
3. **Platform + version** — e.g. "Windows 11, Godot 4.4.1 editor", "Android 14 APK", "Web/Chrome".
4. **Whether it closes instantly** (engine crash / black window) or **freezes with the window open** (script error loop).
5. If it's a black window that never draws anything, that points at the renderer — try
   `--rendering-driver opengl3` and tell me if anything changes.

---

## Quick things to try first

These cover the most common first-open failures and take a minute:

| Try | Why |
|---|---|
| **Project → Reload Current Project** | forces Godot to re-import fonts/audio after a fresh clone |
| Delete the `.godot` folder, reopen the project | clears a stale import cache |
| Confirm **Godot 4.4+** | the project ships `config/features=PackedStringArray("4.7", …)`; 4.4 also passes the full audit |
| **Try the other renderer** — the single most useful test | this project defaults to `mobile` (Vulkan/Metal). If Vulkan is the problem, force OpenGL: `--rendering-driver opengl3`, or switch *Project Settings → Rendering → Renderer → Rendering Method* to **Compatibility** |
| On a phone/emulator, try `--rendering-driver opengl3` | rules out a GLES3 driver issue |
| Run the built-in self-test (below) | if this passes, the rules/AI are fine and it's a scene/UI issue |
| Try the window instead of fullscreen | rules out a windowing/monitor issue |

### The built-in self-test

The project ships with headless checks that also print the first failure precisely:

```bash
godot --headless --path /path/to/scopa-four-realms -- --audit
```

It ends with either `=== AUDIT COMPLETE · failures=0 ===` or a line per failure.
Paste that output — it isolates rules/AI bugs from rendering ones instantly.

It also prints the card/hand/table geometry it measured, which is how the layout
was tuned without a display. If the audit passes but the game crashes on open,
the problem is in rendering or the window — not the game logic.
