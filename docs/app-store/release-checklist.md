# Release checklist

## GitHub

- [x] Create the repository `RainerZufall00/recipe2mealie`.
- [ ] Push `main`.
- [ ] Fill in `[NAME]`, `[ADDRESS]` and `[EMAIL]` in `docs/privacy.md`.
- [ ] Set `FEEDBACK_EMAIL` in `Config/Base.xcconfig`
      so the app's feedback screen appears. The issue forms are in `.github/ISSUE_TEMPLATE/`.
- [ ] Settings → Pages → *Deploy from a branch* → `main` / `docs`. The privacy policy is then at
      `https://rainerzufall00.github.io/recipe2mealie/privacy`.
- [ ] Check that the CI workflow runs green (it needs a runner image with Xcode 27).
- [ ] Optional: add screenshots to the README, enable Discussions, announce in the Mealie community.

## Apple Developer Program

- [ ] Enroll (individual or organization) and wait for approval.
- [ ] Put the new team ID into `Config/Secrets.xcconfig` (`DEVELOPMENT_TEAM`).
- [ ] App Store Connect → Business: decide on EU trader status. A free app without in-app purchases can usually be
      offered as a non-trader.

## Google Cloud (YouTube Data API)

- [ ] Restrict the API key to the iOS apps `de.recipe2mealie.app` and `de.recipe2mealie.app.ShareExtension`
      and to the YouTube Data API v3.
- [ ] Watch the quota (10,000 units per day, 1 per YouTube import) and request more when needed.

## App Store Connect

- [ ] New app: name *Recipe2Mealie*, bundle ID `de.recipe2mealie.app`, SKU e.g. `recipe2mealie`,
      primary language German.
- [ ] Texts in German and English from `listing.md` (run `python3 docs/app-store/check-lengths.py`).
- [ ] App Privacy: *Data Not Collected*. Privacy Policy URL from GitHub Pages.
- [ ] Age rating questionnaire (all "no" → 4+).
- [ ] Screenshots: iPhone 6.9" and iPad 13", German and English (taken from the demo, see `listing.md`).
- [ ] App Review information: notes from `review-notes.md`, test server credentials, contact details.

## Build

- [ ] Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` if needed.
- [ ] Test on a real device: share extension from YouTube/Instagram/Safari, camera scan, on-device processing,
      YouTube description check, editing, cover images, German and English.
- [ ] Xcode → Product → Archive → Distribute App → App Store Connect.
- [ ] TestFlight: internal testing first, then a small external group (needs a short beta review).
- [ ] Submit for review.
