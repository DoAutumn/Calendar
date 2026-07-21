#!/bin/bash
# Cut a release: bump VERSION → build → zip → GitHub Release → update the
# Homebrew cask so `brew upgrade --cask doautumn-calendar` picks it up.
#
#   ./release.sh 1.0.1
#
# Needs `gh`, authenticated. The Homebrew tap is cloned on demand.
set -euo pipefail

TAP_REPO="DoAutumn/homebrew-tap"
GH_REPO="DoAutumn/Calendar"
CASK_TOKEN="doautumn-calendar"

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "usage: ./release.sh <version>   e.g. ./release.sh 1.0.1"; exit 1; }

ROOT="$(cd "$(dirname "$0")" && pwd)"
ZIP="$ROOT/dist/Calendar.app.zip"
TAG="v$VERSION"

[ -z "$(git -C "$ROOT" status --porcelain)" ] || { echo "!! working tree is dirty — commit first"; exit 1; }
git -C "$ROOT" rev-parse "$TAG" >/dev/null 2>&1 && { echo "!! tag $TAG already exists"; exit 1; }

echo "==> Checking the remote"
git -C "$ROOT" fetch -q origin
[ -z "$(git -C "$ROOT" ls-remote --tags origin "$TAG")" ] || {
    echo "!! tag $TAG already exists on the remote — someone released it elsewhere."
    echo "   Pull, then pick the next free version."
    exit 1
}
UPSTREAM="$(git -C "$ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || echo origin/main)"
BEHIND="$(git -C "$ROOT" rev-list --count "HEAD..$UPSTREAM" 2>/dev/null || echo 0)"
[ "$BEHIND" -eq 0 ] || {
    echo "!! HEAD is $BEHIND commit(s) behind $UPSTREAM — rebase first, then rerun."
    exit 1
}

command -v gh >/dev/null || { echo "!! gh not found — install it first (brew install gh)"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "!! gh is not authenticated — run: gh auth login"; exit 1; }

if [ -n "${TAP_DIR:-}" ]; then
    TAP="$TAP_DIR"
    git -C "$TAP" pull -q --ff-only
else
    TAP="$(mktemp -d)/homebrew-tap"
    trap 'rm -rf "$(dirname "$TAP")"' EXIT
    echo "==> Cloning $TAP_REPO"
    git clone -q "https://github.com/$TAP_REPO.git" "$TAP"
fi
CASK="$TAP/Casks/${CASK_TOKEN}.rb"

echo "$VERSION" > "$ROOT/VERSION"

"$ROOT/build_app.sh"
"$ROOT/make_zip.sh"

echo "==> Tagging $TAG"
if git -C "$ROOT" diff --quiet VERSION 2>/dev/null && \
   [ -z "$(git -C "$ROOT" status --porcelain VERSION)" ]; then
    echo "    VERSION already $VERSION — no release commit needed"
else
    git -C "$ROOT" add VERSION
    git -C "$ROOT" commit -m "release: $TAG"
fi
git -C "$ROOT" tag "$TAG"
git -C "$ROOT" push origin HEAD "$TAG"

echo "==> Creating GitHub release $TAG"
gh release create "$TAG" "$ZIP" --repo "$GH_REPO" --generate-notes

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "==> Writing cask $CASK_TOKEN $VERSION ($SHA)"
cat > "$CASK" <<CASK
cask "$CASK_TOKEN" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$GH_REPO/releases/download/v#{version}/Calendar.app.zip"
  name "Calendar"
  desc "Menu-bar calendar with lunar dates, holidays and makeup workdays"
  homepage "https://github.com/$GH_REPO"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :big_sur

  app "Calendar.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Calendar.app"]
  end

  uninstall quit: "io.github.calendar"

  zap trash: [
    "~/Library/Preferences/io.github.calendar.plist",
    "~/Library/Saved Application State/io.github.calendar.savedState",
  ]
end
CASK

git -C "$TAP" add -A
git -C "$TAP" commit -m "doautumn-calendar $VERSION"
git -C "$TAP" push || {
    echo "!! pushing the tap failed — the GitHub release for $TAG is already published,"
    echo "   only the cask bump is missing. Fix the git credentials and bump the cask by hand."
    exit 1
}

echo
echo "==> Released $TAG"
echo "    brew install --cask DoAutumn/tap/doautumn-calendar"
echo "    brew upgrade --cask doautumn-calendar"
