#!/bin/sh
# Xcode Cloud: Config/Secrets.xcconfig is ignored by Git, so it is created here.
# YOUTUBE_API_KEY is a secret environment variable of the workflow; CI_TEAM_ID is set by Xcode Cloud.
set -e

cat > "$CI_PRIMARY_REPOSITORY_PATH/Config/Secrets.xcconfig" <<XCCONFIG
DEVELOPMENT_TEAM = ${CI_TEAM_ID}
YOUTUBE_API_KEY = ${YOUTUBE_API_KEY}
XCCONFIG

if [ -z "$YOUTUBE_API_KEY" ]; then
  echo "warning: YOUTUBE_API_KEY is not set, YouTube links go straight to Mealie."
fi
