# KFE · KadeFuck Engine

[![KFE Build (Windows)](https://github.com/DFJK117/KFE/actions/workflows/kfe-build.yml/badge.svg)](https://github.com/DFJK117/KFE/actions/workflows/kfe-build.yml)
[![KFE Build (Linux)](https://github.com/DFJK117/KFE/actions/workflows/kfe-linux.yml/badge.svg)](https://github.com/DFJK117/KFE/actions/workflows/kfe-linux.yml)

> **One engine that runs modcharts from every generation.**
>
> Built on Kade Engine 1.8 with a compatibility layer on top, so that
> KE-native scripts, LE (Andromeda) style object scripts, and older mods'
> assets all load and run in the same build — instead of switching engine
> versions every time you switch mods.

[简体中文文档 / Chinese version](KFE.zh-CN.md)

---

## Why does this exist

The FNF modchart ecosystem never had a standard. Each engine branch grew its own dialect:

- The same object is called by different names in different branches
- The same event has different hook names (`start` vs `create`)
- modchart files live at different paths
- Some save-data toggles are even stored **inverted**

So a mod only runs on the exact engine version it was written for. Move it
one version over and it either errors out or silently does nothing.

KFE takes the opposite approach: **don't rewrite the mods — teach the engine
every dialect.** Objects get registered under multiple names, events fan out
to all known hook names, and paths are probed from a candidate list.
The mod side stays untouched.

---

## Contents

- [Features](#features)
- [Patch list](#patch-list)
- [Platforms and builds](#platforms-and-builds)
- [Graphics options](#graphics-options)
- [Base verification](#base-verification)
- [Not done / incompatible](#not-done--incompatible)
- [Troubleshooting](#troubleshooting)
- [About](#about)

---

## Features

### 1. Multi-dialect modchart loading

| Feature | Description |
|---|---|
| Path candidate probing | Loading path changed from one hardcoded path to a **candidate list** (KE native / LE style / legacy `<song>/modchart` / StepMania dirs …) |
| Quiet fallback | Vanilla pops an error window and kicks you back to Freeplay when the modchart is missing; KFE just logs it and keeps running normally |
| One source of truth | Existence check and actual loading share the same candidate table — no more "check says yes, loader says no" |

### 2. Event fan-out across dialects

A single `executeState` fans out to every dialect's event name:

| KE 1.8 name | LE style name | Meaning |
|---|---|---|
| `start` | `create` | song starts |
| `playerTwoSing` | `dadNoteHit` | opponent sings |
| `playerOneMiss` | `doMiss` | player misses |
| … | … | 12 mappings total |

- **Zero cost**: calling a global that doesn't exist yields
  `attempt to call a nil value` and gets swallowed silently, so extra names cost nothing
- **Fixed a stack leak**: each call left a value on the Lua stack, which adds
  up over a full song and eventually hits the stack limit — KFE pops it properly

### 3. Dual naming for objects

Every object registers under both names, so either spelling works:

| Object | KE name | LE name |
|---|---|---|
| Receptors | `receptor_0..7` | `leftDadNote` / `leftPlrNote` … |
| Cameras | `camGame` / `camHUD` / `camSustains` / `camNotes` | `gameCam` / `HUDCam` / `holdCam` / `receptorCam` |
| Characters | `boyfriend` / `gf` / `dad` | `bf` / `gf` / `dad` |

Also **fixed a vanilla typo**: KE 1.8 bound `camNotes` to `camSustains` as well.
KFE binds it to the real `camNotes` object.

### 4. Extra globals injected for scripts

Vanilla KE 1.8 never exposed these, so modcharts couldn't branch on stage or mode:

- `curStage` (current stage)
- `storyMode` (story mode or not)

### 5. Type-aware `setVar`

Vanilla `setVar` always pushed numbers, which caused two bugs:

- Booleans became numbers — and in **Lua `0` is truthy**, so the logic inverted
- Strings ended up with the wrong type

KFE dispatches on the actual type instead.

### 6. New script callbacks

Seven new callbacks available to scripts:

`playSound` / `stopSound` / `playMusic` / `cameraFade` / `pushWarnNote` / `getOption` / `makeSpriteEx`

`makeSpriteEx` loads through the normal asset path, working around vanilla
`makeSprite` only looking inside the song folder.

### 7. Save-option semantics

`getOption()` returns the **raw save value** (a bool stays a bool) — no inversion.

> Worth noting: some mods store their toggles **inverted**
> (stored value is the opposite of what the menu shows).
> So when a script says `!save.data.X`, translating it straight to
> `not getOption("X")` is correct — **don't try to be clever and "fix" it**.

### 8. Warning-note system

- `Note` gains warning / fake fields plus the graphic switch to match
- Warning notes can be injected into the pending-notes queue, and the queue
  is **re-sorted afterwards** (it was already sorted once upstream; without
  re-sorting, stepping from the head of the queue skips later notes)
- The hit callback can replace vanilla's hardcoded health-drain logic
- The notes queue is exposed publicly so the compatibility layer can inject

### 9. Graphics options

See [Graphics options](#graphics-options).

### 10. Compatibility layer API (`KFECompat.hx`)

| API | Purpose |
|---|---|
| `modchartCandidates()` | modchart path candidate table |
| `findModchartPath()` | probe the candidate table for a real path |
| `hasModchart()` | existence check (same source as the loader) |
| `hookAliases(name)` | event-name mapping across dialects |
| `receptorAliases(i)` / `cameraAliases(ke, le)` / `characterAliases(name)` | dual-name tables |
| `registerAliased(obj, lua, names)` | register one object under several names |
| `getSaveOption(name)` | read a save toggle (raw value) |

---

## Patch list

**16 patches** across 4 vanilla files, plus 3 new files, with 36 automated assertions.

| Patch | File | What it does |
|---|---|---|
| `MS-1` | `ModchartState.hx` | multi-dialect load path, quiet fallback when not found |
| `MS-2` | `ModchartState.hx` | inject `curStage` / `storyMode` |
| `MS-3` | `ModchartState.hx` | 6 new callbacks |
| `MS-4` | `ModchartState.hx` | dual naming for receptors |
| `MS-5` / `MS-5b` | `ModchartState.hx` | `executeState` fan-out + stack-leak fix |
| `MS-6` | `ModchartState.hx` | sound-handle table + warning-note injection (with re-sort) + `makeSpriteEx` |
| `MS-7` | `ModchartState.hx` | type-aware `setVar` |
| `PS-1` | `PlayState.hx` | multi-candidate `executeModchart` check |
| `PS-2` | `PlayState.hx` | camera / character dual naming, fix `camNotes` binding |
| `PS-3` | `PlayState.hx` | warning-note hit callback |
| `PS-4` | `PlayState.hx` | notes queue made public |
| `PS-5` | `PlayState.hx` | register main camera with the graphics layer (enables motion blur) |
| `NT-1` | `Note.hx` | warning / fake note fields and graphic switch |
| `OM-1` | `OptionsMenu.hx` | Appearance group gains "Motion Blur" and "Renderer" |
| — | `Project.xml` | `--no-opt` (lowers compile-time memory peak); Lua modchart support widened to desktop |

### New files (3)

| File | Purpose |
|---|---|
| `source/KFECompat.hx` | dialect compatibility layer (all APIs above) |
| `source/KFEGraphics.hx` | graphics state machine and two option controls |
| `source/KFEBlurShader.hx` | motion-blur shader |

> `Lua_helper` is deliberately **left untouched**: its module path can't be
> resolved from inside the project, so every new capability goes through the
> callback-registration entry point that is known to work.

---

## Platforms and builds

You don't need a local Haxe toolchain (haxe / haxelib / lime / hxcpp / MSVC).
The workflows under `.github/workflows/` run automatically on push:

| Workflow | Platform | Artifact |
|---|---|---|
| `kfe-build.yml` | Windows | `KFE-windows` |
| `kfe-linux.yml` | Linux | `KFE-linux` |
| `kfe-baseline.yml` | Windows | control group: builds the **unpatched** vanilla engine |

Pinned dependency versions (each verified to exist on lib.haxe.org):

```
hxcpp 4.2.1   lime 7.9.0   openfl 9.1.0   flixel 4.9.0
flixel-addons 2.10.0   flixel-ui 2.3.3   hscript 2.0.7   actuate 1.8.7
polymod 1.4.3
git: discord_rpc / extension-webm / linc_luajit / hxvm-luajit
```

After installing, the pipeline **reads back the effective versions** and stops
immediately if they don't match — because haxelib's current version can get
silently bumped by a later command.

The base (Lime 7.9 / OpenFL 9.1) supports Windows / Linux / macOS / HTML5 /
mobile / Switch, but **only the Windows and Linux pipelines are actually
exercised**; the rest are unverified.

---

## Graphics options

Two new entries in the Appearance group:

| Option | Levels | Applies |
|---|---|---|
| `Motion Blur` | off / low / medium / high | immediately (shader only) |
| `Renderer` | Auto / OpenGL / Direct3D 11 (via ANGLE) / Software | needs restart — press to restart now |

**About "DX11", to be clear:**

> Lime 7.9.0's render-context enum has **no `d3d11`**. The full set is
> `cairo / canvas / dom / flash / opengl / opengles / webgl / custom`.
> Passing `d3d11` is silently dropped — that kind of "DX11 toggle" is fake.
>
> The real D3D path on Windows is **ANGLE**: GLES calls go
> EGL → ANGLE → translated to D3D11.
> So this engine's "DX11" level actually passes `opengles`, and the UI
> honestly labels it `Direct3D 11 (via ANGLE)` rather than pretending
> it's native DX11.

**Motion blur here is a single-frame radial multi-tap approximation**, not
physically correct motion blur (real motion blur needs frame history or a
velocity buffer, which this pipeline doesn't have). Hence "approximation".

| Level | Strength | Samples |
|---|---|---|
| off | 0.000 | 2 |
| low | 0.020 | 6 |
| medium | 0.045 | 12 |
| high | 0.080 | 20 |

The graphics layer also garbage-collects destroyed cameras and uses replace
semantics so repeated application is idempotent.

Full evidence trail in `docs/06_画质选项.md`.

---

## Base verification

Regenerating the distribution **byte-asserts** the checksums of anchor files
and refuses to continue on mismatch — so the base can't silently drift.

> Learned this the hard way: a repo calling itself "1.8 Template" had actually
> been modified (sprite registration commented out, the Lua modchart guard
> removed). That's why this check is mandatory, not optional.

---

## Not done / incompatible

**Not done** (later phases):

- **LE object members**: LE's script sprite exposes 32 members, KE 1.8 only 9
  (missing `visible` / `scaleX` / `scaleY` / `scrollFactorX` / `makeGraphic`, …)
- **Bridge for the flat KE 1.5.x–1.6.2 API**: those generations used around a
  hundred flat global functions — a completely different paradigm
- `countdown` trigger point

**Incompatible**:

- `doEvent` — KE 1.8 has no song-event system, so there's no host for it

---

## Troubleshooting

Everything hit during the build process is written up in
`docs/07_云端编译排错.md`, including:

- An upstream dependency repo that 404s (the vanilla CI address is stale)
- One `haxelib` command that quietly blew away the whole version matrix —
  and the script at the time was hiding it
- Two real syntax errors in the patches (a stray brace closing the
  constructor early)
- A counter-intuitive lesson: **equal brace counts do not catch that kind of
  bug** (the totals still balanced out)
- The compiler process running out of memory on Windows, where the ceiling is
  the commit limit = physical RAM + page file

New failures get appended to that document.

---

## About

| | |
|---|---|
| **Author** | **京葉Viii** (Jingye Viii) |
| **Assisted by** | This project was generated with the assistance of **Hy4** |
| **Inspiration** | While studying the Lua modchart scripts of the KE-based mod *Bob's Onslaught*, the idea came up: build an engine that truly masters KE mods |
| **Base source** | [`kadedev/Kade-Engine` @ tag `1.8`](https://github.com/kadedev/Kade-Engine) |
| **License** | Inherits the base `LICENSE` |
| **Docs** | [简体中文 / Chinese](KFE.zh-CN.md) |

Patch design, evidence gathering, and CI debugging were done with Hy4's
assistance; the project belongs to 京葉Viii, who makes the final calls.

This is a fork of Kade Engine and contains no source code from any other mod.
