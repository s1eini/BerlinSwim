#!/bin/sh
# Raise the build number (CURRENT_PROJECT_VERSION in project.yml) by one and regenerate the Xcode project.
# Usage: ios/scripts/bump-build.sh            → next build
#        ios/scripts/bump-build.sh 1.1.0      → also set a new marketing version (build keeps counting)
set -e
cd "$(dirname "$0")/.."

current=$(sed -n 's/^    CURRENT_PROJECT_VERSION: "\([0-9]*\)"$/\1/p' project.yml)
[ -n "$current" ] || { echo "CURRENT_PROJECT_VERSION not found in project.yml" >&2; exit 1; }
next=$((current + 1))
sed -i '' "s/^    CURRENT_PROJECT_VERSION: \"$current\"$/    CURRENT_PROJECT_VERSION: \"$next\"/" project.yml

if [ -n "$1" ]; then
    sed -i '' "s/^    MARKETING_VERSION: \".*\"$/    MARKETING_VERSION: \"$1\"/" project.yml
fi

xcodegen >/dev/null
version=$(sed -n 's/^    MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml)
echo "Version $version, build $next"
