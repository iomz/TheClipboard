# The Clipboard — development

## Identity

The Clipboard v0.4.2/build 7 uses bundle identifier `com.iomz.TheClipboard`, executable/product/target `TheClipboard`, and bundle `The Clipboard.app`. SwiftPM application sources live in `Sources/TheClipboard`; `ClipboardCore` and `ClipboardPlatform` are shared implementation modules. History model is `ClipboardLibrary`; its change notification is `clipboardLibraryDidChange` with name `TheClipboard.didChange`. Canonical hashes use `TheClipboard\0canonical-v1\0`.

Storage is `~/Library/Application Support/TheClipboard/Entries`; app and Sparkle preferences use the new bundle's UserDefaults domain. No migration, fallback, aliases, preference copying or automatic removal of other installations/data. Accessibility authorization must be granted to The Clipboard. The application identity is independent of any other installation.

## Build and automated checks

Requires Apple Silicon, macOS 26+ and Swift tools 6.0+. Sparkle is pinned to 2.10.0. Full Xcode with completed setup is required for modern Finder icon compilation through `actool`; no Xcode project or third-party icon tool. `Scripts/compile-finder-icon.sh` honors explicit `DEVELOPER_DIR`, otherwise selects installed Xcode for its subprocess if Command Line Tools lacks `actool`, without changing global toolchain selection. Native SwiftPM backend remains required by framework integration.

```sh
swift build --scratch-path build/validation/clean-swiftpm --build-system native -c release --arch arm64
Scripts/test-core.sh
Scripts/test-about.sh
Scripts/test-interactions.sh
Scripts/test-updater.sh
Scripts/build-app.sh
Scripts/test-identity.sh
Scripts/test-icon.sh
Scripts/test-finder-icon.sh
Scripts/test-application-icons.sh
Scripts/test-distribution.sh
Scripts/test-signing-identity.sh "build/releases/TheClipboard/0.4.1/The Clipboard.app"
Scripts/package-dmg.sh
Scripts/test-dmg.sh
# Only after authorized signing-account provisioning:
Scripts/verify-sparkle-key.sh "build/releases/TheClipboard/0.4.1/The Clipboard.app"
Scripts/generate-appcast.sh build/releases/TheClipboard/0.4.0/appcast.xml
Scripts/prepare-pages.sh
swift Tests/AppcastMergeChecks.swift Scripts/merge-appcast.swift build/releases/TheClipboard/0.4.1/appcast.xml
python3 Scripts/audit-identity.py
git diff --check
```

Build/package scripts refuse existing outputs. Optional `THECLIPBOARD_SIGNING_IDENTITY` selects a matching installed Apple Development identity hash; sole installed identity is otherwise selected, ambiguity fails. Sparkle components are signed inside-out before outer bundle. New designated requirement must name `com.iomz.TheClipboard`; compare no other application's requirement and assume no TCC continuity. Generated artifacts belong only under ignored `build/`/`.build/` or temporary directories, never in source control.

`Scripts/audit-identity.py` audits filenames and contents of existing Git-managed working-tree files plus intended new, nonignored source files. Deleted paths are excluded because Git history/index retains pre-rename paths until commit. Git internals and ignored build artifacts are not current source. It detects prohibited identity variants using assembled patterns without retaining them in its own text, and fails on a match. No staging or history rewriting.

## Icons and application behavior

Default master `Resources/Artwork/Dustlight.png` and alternative `Lagoon.png` remain exact approved 1254×1254 RGBA PNGs. SHA-256: Dustlight `9b1d66498f16d2ee08b80ed2ad7edc46cd0a1641d66f3d4e37d0f51051751465`; Lagoon `e9da133c0943fc1f35537d3b14eb99a684f36d0cd2e81a609b1700dba8b44885`. Untagged source is interpreted as sRGB; resized PNGs embed sRGB ICC profiles and preserve alpha. No recoloring, masking or thresholding. Apple `iconutil` packages ten standard representations per design. Same-SDK generation is byte-identical.

`CFBundleIconFile = Dustlight.icns` remains fallback; `CFBundleIconName = Dustlight` selects compiled `Assets.car` for Finder. Bundle contains original Dustlight/Lagoon ICNS files and Sparkle notices. Finder/app inside DMG always use Dustlight. Status-menu Application Icon changes `NSApplication.applicationIconImage` immediately, persists explicit choice and checks active item. Missing/corrupt alternative is disabled; current selected image is reapplied after launch/activation/policy transitions without timers or update checks. About explicitly uses selected image. Menu-bar clipboard SF Symbol unchanged; no signed-bundle or Finder writes. Manager-open policy exposes Dock/switcher; closing Manager returns accessory mode. Actual switcher and Sparkle icon appearance remain human tests; Sparkle may use selected running icon.

v0.4.1 Finder fix: macOS 27.0.1 normalized legacy ICNS into a gray container with smaller artwork. Installed v0.4.0 resource bytes matched released bundle, source/extracted ICNS retained alpha, and owner reproduced container in a fresh-identity Finder fixture, ruling out stale installed-app cache. Modern catalog control removed container and owner accepted artwork appearance. `Resources/Dustlight.icon/icon.json` imports exact master as one layer with no explicit fill, glass, shadow, blur or translucency effects. Build assembles temporary authoring package, compiles with Apple's renderer and ships only `Assets.car`, not generated replacement ICNS. Modern canvas normalization is system rendering, not a source artwork edit; raw runtime icons stay unchanged. Do not assume byte-identical catalogs across compiler runs or OS versions. Regression checks require light/dark icon stacks, retained alpha, declarations and catalog immutability during runtime switching. Owner completed Finder-fix HAT: PASS; approved solution stays unchanged. No cache flushing, custom Finder icon assignment or installed-app replacement.

Manager layout: the detail Favorite/Unfavorite button's intrinsic width changed from 91 to 106 points, moving the unconstrained divider from 609 to 594 points at the default window size. Owner rejected the first layout candidate: altered proportions/star presentation and horizontal/diagonal resize failure. Reverted `NSSplitViewController`, split-item holding priorities and row-label changes to the original v0.4.0 `NSSplitView`/row appearance. The rejected controller generated width-holding PreferredSize/FallbackSize constraints; a real AppKit fixture's window expanded to 1300 points while content remained near 804 points. Its narrowed list clipped the unchanged trailing star; window resizable flag, maximum size and aspect ratio were not the restriction. No app-owned SwiftUI hosting/sizing constraints exist. The favorite action alone reserves the maximum intrinsic title width and fixes the original 15-point jump. Independently demonstrated oversized-image/long-source shifts are addressed only by removing horizontal intrinsic sizing from detail previews/labels, bounded by their original pane. Source images still scale proportionally; row styling, star symbol, tint, accessibility and fixed 14-point slot remain exactly original. Minimum content width is computed from full `content.fittingSize` (806 points on this SDK), including AppKit alignment insets; original minimum height remains unchanged. No fixed split ratio, offsets or split-item priorities. Tests check actual window/content size equality for horizontal, vertical and diagonal size changes, normal/dragged divider stability, and unclipped star at original default size. Synthetic content snapshots of original and restored Manager retain the same appearance/proportions (one-point fitting difference); offscreen snapshots do not certify live mouse resizing or full desktop visuals. Those remain owner HAT.

Preserved: clipboard monitoring, opaque/rich/plain representations, favorites, search, Manager, picker/hover previews, Option-Command-V and Shift-Command-V, picker Ctrl-N/P/arrows/Return/Shift-Return/Escape, and picker-local Shift-Command-Space to Manager/search focus. OS input-source conflicts must be resolved by owner, never a new global shortcut.

## Storage, paste safety and maintenance

One entry groups ordered pasteboard items and all supported raw representations. Canonical identity uses SHA-256 over versioned, length-framed bytes: item order matters; representations sort by lowercased type identifier and payload bytes. Derived text, timestamps, source, favorites and UI data are excluded. Duplicate promotion preserves UUID/favorite, updates recency/latest source and creates no second row. Picker and Manager share `ClipboardLibrary` and search semantics; Manager adds All/Favorites filtering without a second store.

Successful Manager Copy/Copy as Plain Text and Picker paste reuse the existing record through `recordReuse(of:)`. Optional persisted `lastUsedAt` orders entries by the later of last capture and last use; it advances monotonically even for equal/backward clock readings. Reuse never changes UUID, first/last capture timestamps, favorite, source or representations. Older records lacking this optional field remain readable without rewriting. Manager promotes after successful restore; Picker promotes only after existing foreground verification and successful event-pair dispatch, not after clipboard restore alone and not after merely selecting/previewing/searching/favoriting. Own writes remain excluded from monitoring; genuine external recapture retains existing deduplication behavior and last-use metadata. Store writes precede in-memory reordering/notifications; persistence failure leaves order unchanged and reports copy/paste success separately. Filter/query stays active, selected identity follows its reordered row, and scrolling keeps that row visible. The next navigation step follows the new order; Picker still dismisses on activation and starts a fresh query on its next normal opening.

`FileEntryStore` writes binary property-list metadata and opaque payload sidecars through per-entry staging/replacement. Loading skips corrupt records independently, never clears the store. Capture polls pasteboard change count, skips own restores and accepts public text, RTF/RTFD, HTML, PNG/TIFF/JPEG, URL and file URL types. Unsupported/promised data is not universally replayable. Plain-text extraction prefers plain representations, then derives from rich text through AppKit. Source attribution uses frontmost application and can race with focus changes. Use isolated named pasteboards and synthetic fixtures; never put real clip payloads into logs, diagnostics, tests or release bundles. Representation reports expose types, byte counts and classification only.

Picker opens near the pointer, offset and clamped to its display's usable frame, with search-focused nonwrapping navigation. Selection/search/preview never write the clipboard; Manager Copy never injects keys. Paste restores first, checks event-post access before dismissal, reactivates captured destination, verifies foreground PID and posts Command-V to that PID. Failed permission/activation/posting leaves restored clipboard ready for manual paste. Successful event posting proves an injection attempt, not destination acceptance. Global shortcuts use an isolated `RegisterEventHotKey` adapter with menu fallback, not a global keyboard event tap; paste authorization is distinct from Input Monitoring and ordinary copy/storage.

Core operation remains local-only; no analytics, ads, accounts or cloud sync. Retention controls, exclusion/settings surfaces, login integration and Save As are not implemented by this rebrand. Future age/count eviction must protect favorites; any storage safety cap must warn and require deliberate resolution. File-reference Save As needs an owner decision on path export versus copying referenced files before implementation. No data-import feature is planned. Do not turn obsolete research proposals into current requirements or add features during release cleanup.

Sparkle owns consent and scheduling: leave `SUEnableAutomaticChecks` absent from bundle metadata, respect persisted choices and 86400-second default, and keep automatic downloads/installation disabled. Do not trigger checks from picker, Manager, icon or activation callbacks. Keychain lookup-only `generate_keys -p` reads existing secret material to derive the public key and fails when missing; normal build/release scripts never provision accounts. Never log, transmit, export or commit private signing material. Publish exact validated archive bytes before exposing the feed; never replace a version's published assets.

## Sparkle signing-account authorization gate

Pipeline uses only Keychain service `https://sparkle-project.org`, account **`com.iomz.TheClipboard`**, protocol SSH. Embedded public key/keypair and owner-retained Bitwarden backup remain unchanged. Do not generate a replacement, delete/update the source item, export private material, or fall back to another account. Owner authorized provisioning on 2026-10-09; the approved seed was copied in memory into the new login-Keychain item. New-account challenge signing and local appcast enclosure verification passed, including tampered-archive rejection. Source item and backup were not modified.

Provisioning procedure retained for review, **already completed; do not rerun**:

1. Owner authorizes reading the existing approved signing item and creating a separate login-Keychain item for `com.iomz.TheClipboard`. Owner supplies source account name locally as a nonsecret command argument, never its password/key value.
2. Compile `Scripts/provision-sparkle-account.swift` into ignored `build/tools/`. Run it with source account and `Resources/Info.plist` arguments. It refuses an existing destination, reads secret into process memory, validates derived public key against `SUPublicEDKey`, adds new item without updating/deleting source, and prints status only. Existing encrypted backup is preserved; no plaintext file is created.

   ```sh
   mkdir -p build/tools
   swiftc Scripts/provision-sparkle-account.swift -o build/tools/provision-sparkle-account
   # SOURCE_ACCOUNT is supplied by owner; no private material goes in arguments.
   build/tools/provision-sparkle-account "$SOURCE_ACCOUNT" Resources/Info.plist
   ```

3. Use new-account-only challenge/signature verification and appcast generation. Confirm exact same public key and valid EdDSA/tamper rejection. No final HAT candidate until this gate and all automated checks pass. Access prompts must be approved by owner; failures stop, never weaken Keychain protection.

Recovery on another Mac requires separate authorization and the existing Bitwarden backup, not a replacement key. Resolve pinned Sparkle tooling, check destination with `generate_keys --account com.iomz.TheClipboard -p`, and stop on a conflicting key. Owner supplies a recovered file outside the repository/synced folders with mode 0600 in a 0700 directory. On a signing-capable Mac, `Scripts/test-sparkle-key-recovery.sh trusted.app recovered.key` imports into a UUID account, verifies public key/challenge, removes only that temporary item and rechecks production signing. On a replacement Mac, after confirming destination absent, official `generate_keys --account com.iomz.TheClipboard -f recovered.key` restores the approved seed; run `Scripts/verify-sparkle-key.sh trusted.app` before release work. Owner removes temporary plaintext once verified; no secure SSD erasure is claimed. Do not assume iCloud Keychain sync, encrypted vault exports including attachments, or certificate recovery from Sparkle-key recovery. Preserve independent protected backup and vault recovery access; never inspect/print recovered private material in agent tools.

## Future distribution

Repository/feed references exclusively target `github.com/iomz/TheClipboard` and `https://iomz.github.io/TheClipboard/appcast.xml`. Changing the Git remote requires owner authorization. First feed contains only this application's build 5; previous-feed preflight rejects other repository release URLs. HTTPS XML is not itself signed; DMG enclosures carry EdDSA signatures.

Candidate release folder: `build/releases/TheClipboard/0.4.1`; archive folder: `build/update-archives/TheClipboard`; candidate Pages payload: `build/pages/TheClipboard/0.4.1`. Release/tag retention and preservation of existing published endpoints/assets require separate owner decisions. GitHub project Pages redirects must not be assumed when renaming a repository. Release DMG must exist before publishing new feed. Root `LICENSE` is MIT, copyright 2026 Iori Mizutani; bundled Sparkle retains its separate attribution. No application CI workflow or public product screenshot is present.

Owner authorized first publication on 2026-10-09 after repository rename. Tag `v0.4.0` targets approved implementation `bf0b42db6881c53a51a105080b1530a1b657e697`. Public DMG SHA-256 is `0fa08da8b2423fc38ece147c7f970487de5ac9b05d59a036d06eb2471fcd9015`; downloaded bytes matched locally. HTTPS appcast contains only build 5; enclosure size, URL, EdDSA signature and tamper rejection passed. Pages deploys from `gh-pages` root with HTTPS enforced. This records publication verification, not a successful future update installation or trusted notarized distribution.

Distribution remains development-signed, not Developer ID signed/notarized. Do not bypass Gatekeeper, remove quarantine, reset TCC or claim trusted-download/installation success from signature verification alone. Developer ID/notarization is separately authorized work.

For each future release, update SemVer/build only in `Resources/Info.plist`; Sparkle orders independent increasing build numbers. Preserve existing candidates before running scripts that refuse overwrites. Package read-only UDZO containing only app and Applications symlink; outer bundle allowlist excludes stores, secrets and signing tools. Keep exact earlier DMGs under the application's archive directory; pass the previous published feed explicitly to `Scripts/generate-appcast.sh previous-appcast.xml`. Feed preflight limits repository identity; merge preserves older enclosures/signatures/URLs and rejects non-older builds. CryptoKit independently verifies each enclosure plus tamper rejection. `--distribution-check` exits before clipboard, hotkeys, event loop or update requests; it is not an installation test.

After separate publication approval: commit/push accepted source and tag, upload exact validated DMG, download/compare public SHA-256, then deploy only generated `appcast.xml` and `.nojekyll` from a separate publishing checkout to `gh-pages` root with HTTPS. Resolve existing endpoint preservation before repository/Pages changes. Verify live XML, enclosure signatures and artifact bytes before owner tests actual update download/install/relaunch. Never force-push publishing history, replace published assets, or report local feed/diagnostic validation as successful OTA.

## HAT gate

Owner completed replacement v0.4.1/build 6 HAT: **PASS**, and authorized commit, push, tag, GitHub Release and Pages appcast publication on 2026-10-10. Approved modern Finder catalog/artwork/runtime switching; original Manager proportions/row/star appearance, stable favorite-action width, horizontal/vertical/diagonal resizing and divider dragging; successful Manager copy/plain and Picker paste promotion, metadata preservation, persistent order and no duplicates. Rejected split-controller implementation is absent. Automated regression coverage also checks search, Favorites, selection/navigation, failure paths and monitor deduplication. Publish the verified DMG before updating the feed, retaining v0.4.0's valid enclosure. This HAT approval does not imply Developer ID signing, notarization or verified OTA installation.

Future HAT uses a fresh writable bundle and disposable `THECLIPBOARD_SUPPORT_DIRECTORY`; this isolates clips, not same-account preferences/TCC. Owner quits other copies before launching to avoid hotkey conflicts; tooling never quits/replaces installations or resets defaults/TCC. Check version/build, original proportions/row/star appearance, selection/type/favorite stability, all resize directions and divider dragging; search/Favorites/keyboard navigation; copy/plain/paste promotion, relaunch order/no duplicates; both icons, clipboard workflows and paste authorization. Keep automatic-check preferences intact and never assume designated-requirement equality proves TCC continuity. Preserve previous candidates and require explicit owner approval before publication.

Owner completed and approved v0.4.0/build 5 HAT, including final README and MIT License, and authorized the rebrand commit. Future candidates still follow the checks above. No push, tag, repository rename, Release, feed/Pages publication, installation removal or history rewrite without separate explicit approval. This document is the single source of truth for development and release procedures.
