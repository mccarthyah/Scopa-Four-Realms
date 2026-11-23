# A locally built Godot for running the audit

`verify.yml` downloads the official Godot 4.7.2 editor. This directory is for the
case where that is awkward — no display, no network to the release host, or you
just want the audit to run on a machine with nothing installed.

## Why the official zip often will not do

The audit needs `--headless`, which is a runtime flag, not a separate build: the
editor binary still links X11/Wayland, ALSA/PulseAudio, Vulkan and OpenGL. On a
container with none of those, the usual fix is to build from source with the
drivers compiled out:

```bash
# fetch the exact tag project.godot and testflight.yml target
curl -L https://codeload.github.com/godotengine/godot/tar.gz/refs/tags/4.7.2-stable \
  -o godot-src.tar.gz
tar xzf godot-src.tar.gz && cd godot-4.7.2-stable

python3 -m venv ../buildenv && ../buildenv/bin/pip install scons
../buildenv/bin/scons \
  platform=linuxbsd target=editor arch=x86_64 \
  use_sowrap=yes x11=no wayland=no alsa=no pulseaudio=no \
  dbus=no udev=no vulkan=no opengl3=no \
  libwebp=no speechd=no fontconfig=no tests=no deprecated=no minizip=no \
  accesskit=no -j"$(nproc)" progress=no
```

`use_sowrap=yes` bundles the X11 headers, so no `pkg-config` and no `-dev`
packages are needed. With every `builtin_*=yes` (the default) all third-party
libraries come from the tree.

The result is `bin/godot.linuxbsd.editor.x86_64`. Strip it, or do not; stripping
only changes the size.

## Where to get the binary

The binary is **not committed** — see `.gitignore`. Keep it in shared storage
(Google Drive, a release asset) rather than in git. Name it with its hash so a
download can be checked:

```
godot-4.7.2-linuxbsd-headless-<first 12 of sha256>.x86_64
```

## Using it

```bash
GODOT=/path/to/godot-4.7.2-linuxbsd-headless-xxxxxxxxxxxx.x86_64
"$GODOT" --headless --path . --import      # first run builds .godot/
"$GODOT" --headless --path . -- --audit    # the audit
```

`safe-check.sh` wraps both steps if you prefer:

```bash
GODOT="$GODOT" ./safe-check.sh
```

## Caveats

- This build has **no** display, audio or Vulkan/OpenGL driver. It proves the
  rules, the serialisation, and that every screen *builds* — it proves nothing
  about rendering. Visual checks still need a real device; see `CRASH_REPORT.md`.
- `godot.pck`-dependent features and export templates are not included. This is a
  test instrument, not a replacement for the editor on a workstation.
