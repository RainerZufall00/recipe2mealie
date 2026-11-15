# Recipe2Mealie – notes for Claude

Everything in this repo is in English (code, comments, commits, issues).

## Building without a Mac

Cloud sessions run on Linux and can't build iOS. So:

- Every push runs `.github/workflows/ci.yml` (simulator build with Xcode 27.2, no signing). After pushing, wait
  for the result and fix build errors before calling the work done (`gh run watch`, `gh run view --log-failed`).
- TestFlight and App Store builds come from GitHub Actions: `.github/workflows/testflight.yml`, started by hand
  (Actions → TestFlight → Run workflow; `gh workflow run testflight.yml -f version=1.2.3`). It runs
  `ci_scripts/testflight.sh`: archive, sign with the developer's own certificates (repository secrets), check the
  signature, upload. Build number = UTC time `yyMMddHHmm`. Enter a new version when the project's version has
  already been released. Not Xcode Cloud: its cloud-managed certificate breaks on the umlaut in the account
  name (ITMS-90035). `ci_scripts/ci_post_clone.sh` still writes `Config/Secrets.xcconfig` (plus the secret `YOUTUBE_API_KEY`) with the team ID.
- Testing happens via TestFlight, i.e. a release build.
