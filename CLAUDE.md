# Recipe2Mealie – notes for Claude

Everything in this repo is in English (code, comments, commits, issues).

## Building without a Mac

Cloud sessions run on Linux and can't build iOS. So:

- Every push runs `.github/workflows/ci.yml` (simulator build with Xcode 27.2, no signing). After pushing, wait
  for the result and fix build errors before calling the work done (`gh run watch`, `gh run view --log-failed`).
- TestFlight and App Store builds come from Xcode Cloud, started by hand in App Store Connect.
  `ci_scripts/ci_post_clone.sh` writes `Config/Secrets.xcconfig` from `CI_TEAM_ID` and the secret
  `YOUTUBE_API_KEY`; Xcode Cloud sets the build number.
- Testing happens via TestFlight, i.e. a release build.
