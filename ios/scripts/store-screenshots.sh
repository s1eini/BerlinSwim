#!/bin/zsh
# Takes the App Store screenshots in German and English into fastlane/screenshots/<locale>/:
# iPhone 17 Pro Max (6.9", 1_…4_), iPad Pro 13" (ipad_1_…ipad_4_) and the folded iPhone Duo (duo_1_…duo_4_, outer display).
# 3_widget.png (home screen with the large widget) is taken by hand: place the widget in the iPhone simulator, bring its page to the front, `simctl io … screenshot`; once per language (the widget follows the system language).
# The unfolded Duo (inner display) is black while the simulator is folded: unfold it by hand, then run
#   DUO_INNER=1 ios/scripts/store-screenshots.sh     → only the Duo, display 3, files duoinner_1_…duoinner_4_
# Needs a debug build of the app in DerivedData (xcodebuild -scheme BerlinSwim -destination 'id=<udid>' build).
set -e
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
ROOT=${0:A:h}/../..
UDID=${UDID:-3FA23A5F-8E37-432D-97EC-6B8713342923}   # iPhone 17 Pro Max
APP=$(find ~/Library/Developer/Xcode/DerivedData -name BerlinSwim.app -path '*Debug-iphonesimulator*' -not -path '*Index.noindex*' | head -1)
POOL=${POOL:-49}                                      # Stadtbad Neukölln

DUO=${DUO:-FBA0658B-919D-45AF-A466-A27A18011431}      # iPhone Duo (folded: --display=1)
IPAD=${IPAD:-FF66328A-108B-4898-9A49-669C47C9A58D}    # iPad Pro 13-inch (M5)

prepare() { # udid
  xcrun simctl boot $1 2>/dev/null || true
  xcrun simctl bootstatus $1 -b >/dev/null
  xcrun simctl install $1 "$APP"
  xcrun simctl status_bar $1 override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
}

shot() { # udid locale language name args…
  local udid=$1 loc=$2 lang=$3 name=$4; shift 4
  mkdir -p "$ROOT/fastlane/screenshots/$loc"
  xcrun simctl terminate $udid de.eatbl.BerlinSwim >/dev/null 2>&1 || true
  xcrun simctl launch $udid de.eatbl.BerlinSwim -previewHour 17 -AppleLanguages "($lang)" "$@" >/dev/null
  sleep 6
  local display=""; [[ $udid == $DUO ]] && { [[ -n $DUO_INNER ]] && display="--display=3" || display="--display=1"; }
  xcrun simctl io $udid screenshot $display "$ROOT/fastlane/screenshots/$loc/$name.png" >/dev/null 2>&1
}

if [[ -n $DUO_INNER ]]; then
  devices=($DUO:duoinner_); prepare $DUO
else
  devices=($UDID:"" $IPAD:ipad_ $DUO:duo_); prepare $UDID; prepare $IPAD; prepare $DUO
fi

for pair in de-DE:de en-GB:en; do
  loc=${pair%%:*}; lang=${pair##*:}
  for dev in $devices; do
    u=${dev%%:*}; pre=${dev#*:}
    shot $u $loc $lang ${pre}1_list
    shot $u $loc $lang ${pre}2_detail -openPool $POOL
    shot $u $loc $lang ${pre}4_map -sheet map -mapSelect $POOL
  done
done
echo "done"
