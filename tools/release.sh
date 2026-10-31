#!/bin/zsh
# Cuts an update release: bumps the version, builds, makes the DMG, and signs it into the update feed (appcast.xml).
# It does NOT publish; it prints the exact `gh` commands so you review before anything goes public.
#
#   tools/release.sh 0.3.0 4        # marketing version, build number (must be higher than the last release's)
#
# Needs the Sparkle signing key in your login Keychain (made once with generate_keys) and the feed host decided in
# project.yml (STRACOTTO_FEED_URL).
set -euo pipefail
cd "${0:A:h}/.."

VERSION=${1:?usage: tools/release.sh <version> <build>}
BUILD=${2:?usage: tools/release.sh <version> <build>}
[[ $BUILD == <-> ]] || { echo "build must be a whole number"; exit 1 }

FEED=$(sed -n 's/^ *STRACOTTO_FEED_URL: *//p' project.yml)
REPO=$(print -r -- "$FEED" | sed -E 's#https://github.com/([^/]+/[^/]+)/releases/.*#\1#')
[[ $REPO == */* ]] || { echo "STRACOTTO_FEED_URL in project.yml isn't a GitHub releases URL: $FEED"; exit 1 }

if [[ -n $(git status --porcelain -- App Shared Resources project.yml) ]]; then
  echo "Commit your changes first, so the release matches a commit."; exit 1
fi

OLD_BUILD=$(sed -n 's/^ *CFBundleVersion: *"\{0,1\}\([0-9]*\)"\{0,1\}.*/\1/p' project.yml)
(( BUILD > OLD_BUILD )) || { echo "Build $BUILD must be higher than the current $OLD_BUILD, or installed copies won't see an update."; exit 1 }

sed -i '' -E "s/(CFBundleShortVersionString: )\"[^\"]*\"/\1\"$VERSION\"/; s/(CFBundleVersion: )\"[^\"]*\"/\1\"$BUILD\"/" project.yml
xcodegen generate >/dev/null
echo "→ Building $VERSION ($BUILD)"
xcodebuild -project Stracotto.xcodeproj -scheme Stracotto -configuration Release -derivedDataPath build build 2>&1 | grep -E 'error|BUILD' || true
APP=build/Build/Products/Release/Stracotto.app
codesign --verify --deep --strict "$APP"

UPDATES=dist/updates
mkdir -p "$UPDATES"
DMG="$UPDATES/Stracotto-$VERSION.dmg"
./tools/make-dmg.sh "$APP" "$DMG"

echo "→ Signing the feed"
TOOLS=build/SourcePackages/artifacts/sparkle/Sparkle/bin
"$TOOLS/generate_appcast" --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" "$UPDATES"
cp "$DMG" "dist/Stracotto.dmg"

cat <<DONE

✓ Built $VERSION ($BUILD). Nothing is published yet. To publish:

  git add project.yml && git commit -m "Release $VERSION" && git push
  gh release create v$VERSION -R $REPO --title "Stracotto $VERSION" --notes "..." \\
      "$DMG" dist/Stracotto.dmg "$UPDATES/appcast.xml"

Installed copies pick it up from $FEED within a day (or via Check for Updates…).
DONE
