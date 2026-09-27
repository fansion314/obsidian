#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./obsidian-electron/PKGBUILD
release_name=$pkgname
app_version=$pkgver
version="${pkgver}-${pkgrel}"
tag="v${version}"
[[ ${GITHUB_REF_TYPE:-} == tag && ${GITHUB_REF_NAME:-} == "$tag" ]]

asset="${pkgname}-${version}-x86_64.tar.gz"
test -s "dist/$asset"
# Verify against the -bin recipe rather than uploading a second checksum asset.
expected_sha=$(source ./obsidian-electron-bin/PKGBUILD; printf '%s' "${sha256sums_x86_64[0]}")
printf '%s  %s\n' "$expected_sha" "dist/$asset" | sha256sum --check
notes=$(mktemp)
trap 'rm -f "$notes"' EXIT
{
    printf 'Official Obsidian %s application resources repackaged for Arch Linux,\n' "$app_version"
    cat <<'EOF'
using the latest system `electron` package. Bundled Electron is excluded.

Two mutually exclusive package recipes are provided:
- `obsidian-electron`: extracts the required resources from the official installer.
- `obsidian-electron-bin`: downloads this release's prebuilt application archive.

This release stores only the prebuilt application archive consumed by the
`obsidian-electron-bin` AUR recipe. Its SHA-256 is pinned in that recipe.
It is not a pacman installation package. Build either AUR recipe with makepkg;
application files are installed in `/opt/Obsidian` and use system Electron.

EOF
} > "$notes"

# Keep partial uploads hidden. A retry may complete an existing draft, but never
# overwrite assets of a release that has already been published.
if draft=$(gh release view "$tag" --repo "$GITHUB_REPOSITORY" --json isDraft --jq .isDraft); then
    if [[ $draft != true ]]; then
        echo "Release $tag is already published; refusing to replace its assets." >&2
        exit 1
    fi
else
    gh release create "$tag" --repo "$GITHUB_REPOSITORY" --verify-tag \
        --draft --title "$release_name $version" --notes-file "$notes"
fi
gh release upload "$tag" "dist/$asset" --repo "$GITHUB_REPOSITORY" --clobber
gh release edit "$tag" --repo "$GITHUB_REPOSITORY" --draft=false --latest
