<div align="center">

# 📸 PhotoSwipe

**Local-only · Zero subscription · Swipe, and your photo library is clean**

[![iOS 17+](https://img.shields.io/badge/iOS-17%2B-blue)](#)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-Swift%205-orange)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](#-license)
[![Build IPA](https://img.shields.io/badge/GitHub_Actions-Cloud_Build-2088FF?logo=githubactions&logoColor=white)](#-build-your-own-ipa)
[![Privacy](https://img.shields.io/badge/Privacy-Photos_never_leave_your_device-red)](#)
[![No Subscription](https://img.shields.io/badge/Subscription-None-ff69b4)](#)

[简体中文](README.md) · [English](README_EN.md) · [日本語](README_JA.md)

*13 Swift files · 4,049 lines · Entirely AI-written · From a 3 a.m. idea to a phone in one night*

</div>

---

> [!IMPORTANT]
> **Why does this project exist?** Every comparable app on the App Store locks basic features like "batch delete" behind a subscription wall.
> This project has no subscription, no ads, no server, and requests no network permission — **your photos never leave your device**.

> [!TIP]
> **No Mac needed!** The whole flow is: Fork this repo → GitHub Actions cloud build (~8 min) → sign with [Sideloadly](https://sideloadly.io). See [Build Your Own IPA](#-build-your-own-ipa).

---

## ✨ In One Sentence

PhotoSwipe reads your iPhone photo library and all you do is **swipe in full screen**: swipe up to queue for deletion, swipe down to favorite, swipe left/right to browse. When you're ready, confirm once in the trash bin — and it **shows you how much space the batch will free up before you delete**.

## 🔥 Highlights

| | Feature | Description |
|:---:|---|---|
| 🗑️ | **Pending-delete queue + space estimate** | Swiping up doesn't delete — it queues. See the total reclaimable space before confirming. Undo individual photos; deleted photos go to "Recently Deleted" (30-day recovery) |
| 🧠 | **Smart grouping (4 entries)** | Similar photos & bursts auto-grouped · organize by month · screenshots older than 90 days · blurry detection |
| 👆 | **One-tap group handling** | "Keep this one, delete the other 7" — an 8-photo burst handled with a single swipe |
| 📂 | **Categories match the system exactly** | Reads iOS smart albums directly: Selfies, Screenshots, Live Photos, Videos, Panoramas, Portrait… |
| 📏 | **Sort by file size** | Largest first — perfect for space-hogging videos (the system Photos app can't do this) |
| 🎬 | **Full-screen video playback** | Zoom, gestures, scrubbing — all inside the swipe flow |

## 🚀 Quick Start (No Mac Required)

1. **Fork this repository**
2. Open `Actions` → select `Build IPA` → `Run workflow`
3. After ~8 minutes, download `PhotoSwipe-IPA` from the run's `Artifacts`
4. Unzip to get `PhotoSwipe.ipa`, then sign with [Sideloadly](https://sideloadly.io) using your Apple ID

> [!WARNING]
> Apps signed with a free Apple ID **expire after 7 days** (an Apple limitation, not a bug). To renew: just sideload again with Sideloadly — your data is preserved. If iOS says "Untrusted Developer": `Settings → General → VPN & Device Management → Trust`.

---

## 🤔 The Backstory

While organizing 20,000+ photos, the system Photos app only allowed opening and deleting one photo at a time — completely unacceptable.

The tools on the App Store looked fine, but batch delete, video preview, and sort-by-size were each locked behind a membership.

**A basic, purely local feature being sold as a subscription is, by itself, the motivation to build an alternative.**

At 3 a.m., the requirements were dictated to an AI. About half an hour later, this repository had its first version.

---

## ✋ Features

### Categories

Categories are read directly from iOS smart albums (`PHAssetCollection`) — identical to the system Photos app, no re-filtering.

| Category | Contents |
|---|---|
| All Photos | The entire library, newest first |
| Selfies | Photos taken with the front camera |
| Screenshots | Screenshots |
| Live Photos | Live Photos |
| Videos | All videos, full-screen playback |
| Panoramas | Panoramic photos |
| Portrait | Photos with depth data |
| Favorites | Photos favorited in the system Photos app |

### Gestures

| Gesture | Action |
|---|---|
| Swipe left / right | Previous / next photo, continuous finger-following paging |
| ⬆️ Swipe up | Add to pending-delete queue (**does not delete**) |
| ⬇️ Swipe down | Add to favorites; swipe down again to cancel |
| Pinch | Zoom in on details; while zoomed, dragging only pans |
| Double tap | Toggle between 1× and 2.5× |
| Tap the arrow next to the title | Expand a 4-column thumbnail grid; tap any photo to jump there |
| Tap a video | Full-screen playback |

### Pending-Delete Queue

> [!NOTE]
> **Design trade-off**: deletion is irreversible, so it is never bound to the most accidentally-triggered gesture. Gestures only express intent; execution is concentrated in one final confirmation.

Swiping up writes the photo's identifier to a local queue; the trash button shows the count. Opening the trash first shows **the total space this batch would free**. Undo any photo (it returns to its original position instantly) or delete everything at once. Deletion is committed in a single `PHPhotoLibrary.performChanges` call after a system confirmation, and photos land in "Recently Deleted" (recoverable for 30 days). The queue is persisted locally and survives restarts.

### Sorting

Within any category, switch between: Default (newest first), file size descending, ascending. The choice is remembered; when sorting by size, the actual file size shows under the title.

### Smart Grouping

Four entries on the home screen for four "where do I even start" scenarios:

| Entry | What it does | Requires analysis |
|---|---|:---:|
| Similar / Bursts | Auto-groups look-alike photos and bursts | ✅ |
| By Month | "May 2023 · 486 photos" — clean a whole month at once | — |
| Old Screenshots | Screenshots older than 90 days, grouped separately | — |
| Possibly Blurry | Auto-detects obviously out-of-focus photos, sorted by blur level | ✅ |

**Group handling**: swipe to the keeper, tap "Keep this one, delete the other 7," and the rest of the group joins the queue. **Blur badge**: detected-blurry photos get a "possibly blurry" tag — informational only, never blocking.

---

## ⏱️ Development Timeline

> [!IMPORTANT]
> The AI's actual hands-on time totaled about **50 minutes** (excluding compiles, uploads, device installs). 13 Swift files, 4,049 lines.

| Phase | Work | Time |
|---|---|---:|
| Requirements & prototype | Three-gesture interaction plan, swipeable prototype | ~2 min |
| First working build | Permissions, category grid, full-screen swipe, queue, trash | ~6 min |
| Compile fixes | Three failures: syntax, three nonexistent APIs, a missing `return` | ~3 min |
| Feature iteration | Video playback, All Photos, selfies, continuous paging | ~8 min |
| Feature additions | Sort by size, thumbnail grid, pinch zoom | ~5 min |
| UX fixes | Undo, hit areas, scroll jank, etc. | ~11 min |
| Smart grouping | dHash grouping, by-month, old screenshots, blur detection | ~12 min |
| Gesture fixes | Pan-only while zoomed | ~3 min |

> From first sentence to final version: about 2 hours 30 minutes of wall time. The gap went to waiting on GitHub's macOS runners, uploading code, and installing on a phone — none of it writing code.

---

## 🛠️ Build Your Own IPA

MIT licensed — fork away. **No Mac required**: iOS apps must be built on macOS, so this project borrows GitHub Actions' free macOS runners. The author doesn't own a Mac either; every build happened on GitHub's machines.

### Steps

1. **Fork this repo** to your GitHub account
2. Open the `Actions` tab, select `Build IPA` on the left, click `Run workflow`
3. Wait ~8 minutes; once green, open the run and download `PhotoSwipe-IPA` from `Artifacts`
4. Unzip to get `PhotoSwipe.ipa`, load it in [Sideloadly](https://sideloadly.io), enter your Apple ID, click `Start`

### If You're Unsure

Send this to any AI assistant:

```text
I have an iOS project on GitHub (Swift + SwiftUI, project managed by XcodeGen,
with .github/workflows/build.yml in the repo). I don't have a Mac, only a Windows PC.
Give me detailed steps for: forking the repo, building an unsigned IPA with GitHub
Actions, downloading the artifact, and installing it on my iPhone with Sideloadly.
Explain what UI I'll see at each step.
```

### Signing Validity

A free Apple ID signature lasts **7 days**, after which tapping the icon crashes. That's Apple's restriction for free accounts, not a bug. Renewing: reconnect to the computer and sideload again — local data is preserved.

---

## 🔬 Technical Notes

- **Categories come from system smart albums**: judgment is entirely delegated to `PHAssetCollection`'s `smartAlbum` types, matching the Photos app exactly.
- **Rebuild indexes after deletion**: `PHFetchResult` indices shift after deletions; a separate array recalculates valid ranges and only the current page ±1 is rendered.
- **On-demand image loading and prefetching**: only 3 image requests live in memory at once, backed by a 120 MB `NSCache` for instant back-scroll hits.
- **File size via non-public API**: PhotoKit doesn't expose it; it's read from `PHAssetResource` via KVC with a `responds(to:)` check.
- **Similarity via perceptual hash (dHash)**: 64×64 grayscale → 9×8 grid → 64-bit fingerprint; Hamming distance ≤ 10 means similar.
- **Pairwise comparison bucketed**: a full 5,000-photo comparison is 12.5 million operations; splitting the fingerprint into four 16-bit buckets cuts it to tens of thousands. Buckets over 40 photos are skipped.
- **Bursts don't use hashing**: the native `PHAsset.burstIdentifier` groups them, most accurate and thumbnail-free.
- **Blur via Laplacian variance**: threshold of 20, intentionally conservative — prefer misses over false positives.
- **Analysis never downloads iCloud originals**: thumbnail requests disable `isNetworkAccessAllowed` to avoid silently burning gigabytes.
- **Project described by XcodeGen**: no `.xcodeproj` in the repo; it's generated from `project.yml` at build time.

### Code Structure

```text
PhotoSwipe/
├── project.yml                       # Project description; generates .xcodeproj at build time
├── .github/workflows/build.yml       # GitHub Actions build script
└── PhotoSwipe/
    ├── PhotoSwipeApp.swift           # Entry point
    ├── Models/
    │   ├── SmartCategory.swift       # Categories (system smart albums)
    │   ├── SortOption.swift          # Sort options
    │   ├── PhotoGroup.swift          # Groups: bursts / similar / by-month / old screenshots
    │   └── PendingStore.swift        # Pending-delete queue (persisted locally)
    ├── Services/
    │   ├── PhotoLibrary.swift        # Permissions, fetching, prefetch, sorting, batch delete, size totals
    │   └── ImageAnalyzer.swift       # Perceptual hash + sharpness + similarity clustering
    └── Views/
        ├── RootView.swift            # Permission onboarding
        ├── CategoryGridView.swift    # Home: all photos / smart grouping / categories
        ├── SmartGroupsView.swift     # Four smart-grouping entries
        ├── SwipeViewerView.swift     # Full-screen browser (gestures, zoom, groups)
        ├── VideoPlayerView.swift     # Video player
        └── TrashView.swift           # Pending-delete list (with space totals)
```

**Privacy**: everything happens on-device. The app requests no network permission; photos never leave the device.

---

## ⚠️ Known Limitations

- **"Selfies" is system-defined**: only front-camera photos; identical to the Photos app.
- **iCloud photos load slowly at first**: they must be fetched on demand — a network/storage matter, not a logic bug.
- **Re-sign every 7 days**: a general limitation of free Apple IDs.
- **Similarity/blur analysis has a scope**: only the most recent 5,000 photos with local thumbnails; results are cached locally and incrementally refreshed.
- **Blur detection may miss**: the threshold is conservative; slight hand-shake may not be flagged.
- **Not on the App Store**: it's a personal tool; distribution isn't the point.

---

## 📄 License

MIT. Free to use, modify, and distribute.

If this is useful to you, fork it. If not, it at least proves one thing:

> **A person who can't write code dictated one requirement at 3 a.m., and two hours later had an app running on their phone.**

---

<sub>Disclosure: all code and documentation in this repository were generated by AI (WorkBuddy / DeepSeek-V4.1-Flash). No human wrote a single line of code.</sub>

<div align="center">

**[简体中文](README.md) · [English](README_EN.md) · [日本語](README_JA.md)**

</div>
