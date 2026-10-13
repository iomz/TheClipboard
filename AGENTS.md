# Repository instructions

Read `DEVELOPMENT.md` for build, validation, signing and distribution details.

## Merge-to-release authorization

Owner approval to merge a PR, or the owner's merge of a PR, also authorizes the
version/build bump, release commit and push, Git tag, GitHub Release and assets,
and Sparkle appcast publication through the existing `gh-pages` endpoint.
Complete these as one workflow; do not ask for separate publication approval.
An explicit instruction such as "merge only", "hold release" or a specified
version overrides this default. Creating a PR alone is not release approval.

This authorization does not cover deleting/replacing published releases, assets
or tags, rewriting history, changing repository/Pages settings, replacing an
installed app, resetting permissions/preferences, or provisioning/replacing
signing keys. Those still require separate explicit authorization.

## Streamlined release workflow

1. Confirm the approved PR head, required checks and owner acceptance of relevant
   app behavior/appearance. Merge, then synchronize a clean local `main`. Stop
   for failed checks, unaccepted functional changes or unexpected repository
   changes; never discard user work.
2. Choose the next unpublished SemVer from current metadata and published
   releases: minor for new features, patch for fixes/maintenance; follow an
   explicitly requested version. Use a build number greater than all current
   and published builds, including the live appcast. Change canonical version
   and build only in `Resources/Info.plist`; update current README download links
   and development documentation to match, without rewriting historical records.
3. Preserve existing local candidates. Build a fresh bundle with
   `Scripts/build-app.sh`; run applicable checks listed in `DEVELOPMENT.md`,
   including core, interactions, icons/Finder/lifecycle, identity, updater,
   distribution, signing and the identity audit. Owner acceptance before merge
   covers unchanged app behavior/artwork; a metadata-only rebuild does not need
   another approval round. Stop if validation exposes a new problem.
4. Restore the latest published appcast and exact earlier DMGs referenced by it
   from `gh-pages`/GitHub Releases into isolated validation inputs and
   `build/update-archives/TheClipboard`. Do not assume ignored local artifacts
   exist or are authoritative. Package using `Scripts/package-dmg.sh`, run
   `Scripts/test-dmg.sh`, and verify the existing Sparkle signing account with
   `Scripts/verify-sparkle-key.sh`. Generate the merged feed using
   `Scripts/generate-appcast.sh previous-appcast.xml`, then
   `Scripts/prepare-pages.sh`. Validate enclosure URLs, sizes, signatures and
   tamper rejection, preserving all existing feed entries.
5. Commit and push only the release metadata/documentation on `main`, then tag
   that exact validated source commit as `vVERSION` and push the tag. Publish
   `TheClipboard-VERSION-arm64.dmg` as a GitHub Release with concise notes.
   Download the public asset into a separate location and compare SHA-256 and
   byte count with the validated local DMG before exposing the new feed.
6. Publish only generated `appcast.xml` and `.nojekyll` to the existing
   `gh-pages` root from a separate publishing checkout, with a normal commit
   and push. Never force-push or replace older enclosures/assets. Verify deployed
   HTTPS XML matches the generated feed and all referenced downloads remain
   available with valid signatures. Do not trigger installation/update checks
   in the owner's running app.
7. Report version/build, release/tag URLs, source commit, public artifact hash,
   appcast URL and verification results. Leave local `main` clean and synced.
   Do not claim verified OTA installation or notarization from publication checks.

If a step fails, stop before the next public mutation, report the blocker and
retain validated artifacts. Resume from verified state rather than repeating
publication blindly. An existing tag/release must match intended source and
artifact bytes; never overwrite it to make a retry succeed.
