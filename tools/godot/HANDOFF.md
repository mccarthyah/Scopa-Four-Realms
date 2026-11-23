# Handing the headless Godot to another session

A ready-made Linux x86_64 Godot for this repo, built from `4.7.2-stable` source
(see `BUILD.md` for how). Paste the block below into another chat or ticket.

---

## The paste block

> **Headless Godot 4.7.2 for the Scopa: Four Realms audit**
>
> Google Drive file ID: `1Th2hbOq7lZuDZKyYYkSKqeGMnOGmKRqF`
> Name: `godot-4.7.2-linuxbsd-headless-f1bee50a8b01.x86_64.gz`
>
> - View: https://drive.google.com/file/d/1Th2hbOq7lZuDZKyYYkSKqeGMnOGmKRqF/view
> - Download: https://drive.google.com/uc?id=1Th2hbOq7lZuDZKyYYkSKqeGMnOGmKRqF&export=download
> - or `gdown 1Th2hbOq7lZuDZKyYYkSKqeGMnOGmKRqF`
>
> ```
> 78,108,839 bytes gzipped  ->  151,196,256 bytes uncompressed
> bd2a1b0c2688df2dbbc48251392b0344f7ada4e1182b4a610bac9de7d986223e  *.x86_64.gz
> f1bee50a8b010d8631c8ed659791105ecd7135b1a42fc960f8579066fc5d2132  *.x86_64   (uncompressed)
> ```
>
> **What it is:** `4.7.2.stable.custom_build`, a *headless editor* build for
> Linux x86_64. It imports assets, runs GDScript, boots the game with the dummy
> renderer, and runs `scripts/audit.gd` — 193 assertions, 0 failures.
>
> **What it is NOT:** it cannot draw anything. It was compiled with `x11=no
> wayland=no vulkan=no opengl3=no`, so a windowed or rendered run fails **by
> design** — do not debug that as a bug. It is also Linux x86_64 only (no arm64,
> macOS or Windows), and it is not an official Godot binary, so do not quote it
> as one. It has no fontconfig, so it logs `Godot was compiled without
> fontconfig, system font support is disabled` once per font load; that line is
> expected, not an error.
>
> To use it:
>
> ```bash
> gdown 1Th2hbOq7lZuDZKyYYkSKqeGMnOGmKRqF
> echo "bd2a1b0c2688df2dbbc48251392b0344f7ada4e1182b4a610bac9de7d986223e  godot-4.7.2-linuxbsd-headless-f1bee50a8b01.x86_64.gz" | sha256sum -c -
> gunzip godot-4.7.2-linuxbsd-headless-f1bee50a8b01.x86_64.gz
> chmod +x godot-4.7.2-linuxbsd-headless-f1bee50a8b01.x86_64
> echo "f1bee50a8b010d8631c8ed659791105ecd7135b1a42fc960f8579066fc5d2132  godot-4.7.2-linuxbsd-headless-f1bee50a8b01.x86_64" | sha256sum -c -
> ./godot-4.7.2-linuxbsd-headless-f1bee50a8b01.x86_64 --headless --version   # 4.7.2.stable.custom_build
> ```
>
> Then, in the repo:
>
> ```bash
> GODOT=/abs/path/godot-4.7.2-linuxbsd-headless-f1bee50a8b01.x86_64 ./safe-check.sh
> ```
>
> Expect `ALL HEADLESS CHECKS PASSED.` — import, boot, then 193 assertions.
> If you only want the test suite:
>
> ```bash
> "$GODOT" --headless --path . --import        # once, builds the .godot cache
> "$GODOT" --headless --path . -- --audit      # grep for "failures=0"
> ```
>
> **If you need a rendered run**, ignore this file entirely. Download
> `Godot_v4.7.2-stable_linux.x86_64.zip` from
> `https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable`
> (sha256 `cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4`) —
> that is the official build, and CI uses exactly it.

---

## Why the hashes are named this way

`f1bee50a8b01` in the filename is the first 12 hex of the **uncompressed**
binary, so the name survives a re-gzip. Verify that hash after `gunzip`; verify
`bd2a1b0c…` on the archive as downloaded.

The binary is deliberately **not in Git** — `tools/godot/bin/` is ignored, and
the repo has no business carrying 78 MB of toolchain.
