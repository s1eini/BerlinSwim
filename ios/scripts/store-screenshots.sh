#!/bin/zsh
# Takes the App Store screenshots (iPhone 17 Pro Max = 6.9") in German and English into fastlane/screenshots/<locale>/.
# Needs a debug build of the app in DerivedData (xcodebuild -scheme BerlinSwim -destination 'id=<udid>' build).
set -e
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
ROOT=${0:A:h}/../..
UDID=${UDID:-3FA23A5F-8E37-432D-97EC-6B8713342923}   # iPhone 17 Pro Max
APP=$(find ~/Library/Developer/Xcode/DerivedData -name BerlinSwim.app -path '*Debug-iphonesimulator*' -not -path '*Index.noindex*' | head -1)
POOL=${POOL:-49}                                      # Stadtbad Neukölln

xcrun simctl boot $UDID 2>/dev/null || true
xcrun simctl bootstatus $UDID -b >/dev/null
xcrun simctl install $UDID "$APP"
xcrun simctl status_bar $UDID override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3

shot() { # locale language name args…
  local loc=$1 lang=$2 name=$3; shift 3
  mkdir -p "$ROOT/fastlane/screenshots/$loc"
  xcrun simctl terminate $UDID de.eatbl.BerlinSwim >/dev/null 2>&1 || true
  xcrun simctl launch $UDID de.eatbl.BerlinSwim -previewHour 17 -AppleLanguages "($lang)" "$@" >/dev/null
  sleep 6
  xcrun simctl io $UDID screenshot "$ROOT/fastlane/screenshots/$loc/$name.png" >/dev/null 2>&1
}

for pair in de-DE:de en-GB:en; do
  loc=${pair%%:*}; lang=${pair##*:}
  shot $loc $lang 1_list
  shot $loc $lang 2_detail -openPool $POOL
  shot $loc $lang 3_prices -openPool $POOL -detailScroll prices
  shot $loc $lang 4_map -sheet map -mapSelect $POOL
done
echo "done"
