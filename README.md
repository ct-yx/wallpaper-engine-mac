Open Wallpaper Engine (Patched)
=========

**English** | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)

A patched fork of [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) for macOS, adding scene wallpaper rendering and web wallpaper fixes.

> **Note:** This is NOT affiliated with the commercial Wallpaper Engine on Steam. This is an open-source macOS app that can display wallpaper assets from Wallpaper Engine's Steam Workshop.

## Project Website

Visit the [project website](https://ct-yx.github.io/wallpaper-engine-mac/) for screenshots, feature highlights, and the latest download.

## Prebuilt Releases

Download the latest macOS build from [Releases](../../releases). Release archives are ad-hoc signed so they do not depend on an expiring Personal Team provisioning profile. They are not notarized by Apple; on first launch, macOS may require you to confirm the app in **Privacy & Security**.

Every release includes a `.sha256` file for verifying the downloaded archive.

## Related Projects

- **[Open Wallpaper Engine for Linux](https://github.com/Unayung/simple-linux-wallpaperengine-gui)** — A PyQt6 GUI for [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine), with Steam Workshop integration and UI design ported from this macOS version.

## Credits

This project is built on top of the work of:

- **[MrWindDog](https://github.com/MrWindDog)** — Maintainer of the upstream [wallpaper-engine-mac](https://github.com/MrWindDog/wallpaper-engine-mac) fork, added new features and UI refinements
- **[Haren Chen](https://github.com/haren724)** — Original creator of [open-wallpaper-engine-mac](https://github.com/haren724/open-wallpaper-engine-mac), built the core app architecture (SwiftUI, video wallpaper playback, import system, playlist UI)
- **[ct-yx](https://github.com/ct-yx)** — Current maintainer and Simplified Chinese localization
- **[Klaus Zhu](https://github.com/klauszhu1105)** — App logo icons
- **[Chen Chia Yang](https://github.com/Unayung)** — Scene wallpaper rendering, web wallpaper fixes, Steam Workshop integration, multi-display support, zip import

Licensed under [GPL-3.0](LICENSE), same as the original project.

## What's New in 0.9.2

### Workshop Access and Scene Textures

- **Browse first, configure downloads when needed** — Workshop search, filters, endless scrolling, and item details now use only the Steam Web API. SteamCMD installation and Steam login are requested from the detail view only when downloading.
- **Reliable cached downloads** — SteamCMD no longer launches while opening the Workshop. It resolves Homebrew symlinks before reusing the same cached SteamCMD session and workshop content directory for queued downloads.
- **DXT scene textures** — The TEX parser now reads TEXB mipmaps and software-decodes DXT1/BC1, DXT3/BC2, and DXT5/BC3 textures, including LZ4-compressed mipmaps.

## What's New in 0.9.1

### In-App Updates

- **Check from the app** — The app checks the latest GitHub Release after launch. You can also choose **Open Wallpaper Engine > Check for Updates…** or use the **Updates** section in Settings > General.
- **Verified installation** — Updates download the published macOS ZIP and its SHA-256 file, verify the archive checksum and app signature, then replace the writable app bundle after quitting and relaunch the updated app.

## What's New in 0.9.0

### Workshop Browsing and Details

- **Collapsible filter sidebar** — Content rating, wallpaper type, and genre filters now live in a vertical left sidebar, so every filter remains reachable on small windows.
- **Wallpaper detail view** — Click any Workshop card to inspect its preview, tags, description, size, and subscription count before downloading. The Steam Workshop link and download action are available in the detail view.
- **Seamless browsing** — The browser loads 40 items per page and automatically preloads the next page as you reach the end of the grid. Pull to refresh remains available.
- **Reliable SteamCMD sessions** — SteamCMD now always runs from its installation directory, preserving its cached session; downloads are serialized and library copies stay off the main thread.

### New Installation Defaults

New installations now pause on focus loss, stop for fullscreen apps and sleeping displays, mute when another app plays audio, keep running on battery, start with macOS, and use below-normal process priority.

## What's New in 0.8.2

### Simplified Chinese Support

The app now includes a complete Simplified Chinese interface, including the Workshop browser, Steam login and download status, multi-display controls, import errors, and status-bar menus. Choose **Chinese Simplified** in Settings > General; the change applies the next time the app opens.

## What's New in 0.8.1

### Multi-Display Support
Assign different wallpapers to each connected monitor with per-screen enable/disable control.
- **Display Settings panel** — Visual monitor layout showing all connected screens, click to select
- **Per-screen wallpaper** — Each display can show a different wallpaper independently
- **Enable/disable toggle** — Turn wallpaper on or off per monitor
- **Auto-detect** — New monitors are automatically detected and enabled when connected

### Multi-Desktop Support
Wallpapers now display across all macOS desktops (Spaces) with continuous playback — no interruption when switching desktops.

### Recent Wallpapers Menu
Quickly switch wallpapers from the status bar menu. The last 10 wallpapers you've used are listed for one-click access.

### Playback Settings — Fixed
Performance playback settings (pause/mute/stop when other apps are focused) now work correctly for all wallpaper types.

### Steam Workshop Browser
Browse, search, and download wallpapers directly from the Steam Workshop without leaving the app.
- **Search & filter** — Search by name, filter by content rating (Everyone/Questionable/Mature), type (Scene/Video/Web), and genre tags
- **Sort options** — Trending, Most Recent, Most Popular, Most Subscribed
- **steamcmd integration** — Auto-detects steamcmd (Homebrew or custom path), with install instructions if not found
- **Steam login** — Supports password, Steam Guard, and cached session authentication
- **Download with progress** — Real-time status updates during download (authenticating, downloading %, validating, copying)
- **Safe defaults** — Content rating defaults to "Everyone" to filter out mature content

### Zip Import
Import wallpaper packages directly from `.zip` files — no need to manually extract first. Works via File > Import and drag-and-drop.

### Multi-Select & Batch Unsubscribe
Cmd+click to select multiple wallpapers, then right-click to batch unsubscribe.

### Wallpaper Storage Isolation
Wallpapers are now stored in `~/Documents/Open Wallpaper Engine/` instead of the raw Documents directory, preventing "error" wallpapers when cloning the repo on a fresh machine.

## What's Patched

### Web Wallpapers — Fixed gray/blank rendering
WebGL-based wallpapers rendered as gray rectangles because `WKWebView` blocked local file access for textures and assets.

**Fix:** Enabled `allowFileAccessFromFileURLs` and `allowUniversalAccessFromFileURLs` on the WKWebView configuration, allowing WebGL shaders to load local texture files.

### Scene Wallpapers — Implemented from scratch
Scene wallpapers (the most common type on Steam Workshop) were completely unimplemented — just showed "Hello, World!".

**New implementation includes:**
- **PKG parser** — Reads Wallpaper Engine's PKGV archive format to extract scene.json, models, materials, and textures
- **TEX parser** — Reads TEXV0005 texture containers, extracts embedded JPEG/PNG data, and software-decodes DXT1/DXT3/DXT5 mipmaps
- **Scene JSON decoder** — Parses scene.json with flexible decoding that handles Wallpaper Engine's polymorphic fields (values can be plain types or `{"script":..,"value":..}` objects)
- **SpriteKit renderer** — Renders scene image layers as SKSpriteNodes with correct positioning, sizing, alpha, color tinting, and blend modes
- **Preview fallback** — Falls back to preview.jpg/png/gif when textures can't be extracted
- **TEXI format detection** — Quickly identifies and skips DXT-compressed textures that can't be decoded

### Import — Fixed folder import
The import panel now correctly handles both individual wallpaper folders and parent directories containing multiple wallpapers.

## Current Limitations

- **Particle effects** — Scene particle systems (rain, snow, sparkles) are parsed but disabled in rendering to avoid visual artifacts. The particle mapping code exists but needs refinement.
- **Audio-reactive scripts** — Wallpaper Engine's JavaScript-based audio visualization scripts are not executed. Properties with scripts fall back to their static `value`.
- **Shader effects** — Custom GLSL shaders (bloom, blur, color correction) are not applied.
- **Camera parallax** — Mouse-tracking camera movement is not implemented.
- **Animated scenes** — Sprite animations and timeline-based object animations are not supported.
- **Some JPEG thumbnails** — A small number of TEXB format 1 files contain non-standard JPEG data that macOS cannot decode. These are typically DXT-compressed textures misidentified as format 1.

## Supported Wallpaper Types

| Type | Status |
|------|--------|
| Video (.mp4, .webm) | Working (original) |
| Web (HTML/WebGL) | Working (patched) |
| Scene (static images) | Working (new) |
| Scene (particles) | Partial (disabled) |
| Scene (DXT1/DXT3/DXT5 textures) | Software-decoded |
| Application | Not supported |

## Build from Source

### Prerequisites
- macOS >= 13.0
- Xcode >= 14.4
- Xcode Command Line Tools

### Steps
```sh
git clone https://github.com/ct-yx/wallpaper-engine-mac.git
cd wallpaper-engine-mac
open "Open Wallpaper Engine.xcodeproj"
```

In Xcode, change the signing certificate to your own or select "Sign to Run Locally", then press `Cmd + R` to build and run.

## Usage

### Browse & Download from Steam Workshop

1. Switch to the **Workshop** tab and enter a [Steam Web API key](https://steamcommunity.com/dev/apikey) when prompted
2. Search, filter, and open a wallpaper card to view its details; this does not require SteamCMD or a Steam login
3. Click **Download**, then install steamcmd (`brew install steamcmd`) or select an existing binary and log in with the Steam account that owns Wallpaper Engine
4. The cached SteamCMD session is reused for later queued downloads

### Import from Local Files

- **Folder:** File > Import from Folder — select wallpaper folders containing `project.json`
- **Zip:** File > Import or drag-and-drop a `.zip` file containing wallpaper packages
- **Manual:** Copy wallpaper folders directly into `~/Documents/Open Wallpaper Engine/`

## Files Changed (vs upstream)

**Modified:**
- `WebWallpaperView.swift` — WKWebView file access configuration
- `WallpaperView.swift` — Scene wallpaper dispatch
- `SceneWallpaperView.swift` — Rewritten as SpriteKit NSViewRepresentable
- `ImportPanels.swift` — Folder import logic fix

**Added:**
- `Services/SceneParsers/PKGParser.swift` — PKGV archive parser
- `Services/SceneParsers/TEXParser.swift` — TEXV texture parser
- `Services/SceneParsers/SceneModels.swift` — Scene JSON data models
- `Services/SceneWallpaperViewModel.swift` — Scene loading and SpriteKit rendering
- `Services/SteamCmdService.swift` — steamcmd detection, login, and workshop download
- `Services/WorkshopAPIService.swift` — Steam Web API client for workshop browsing
- `Services/WorkshopViewModel.swift` — Workshop browser state management
- `Services/WallpaperDirectory.swift` — Centralized wallpaper storage path
- `Services/ZipImporter.swift` — Zip file extraction and import
- `ContentView/Components/WorkshopView.swift` — Workshop browser UI
