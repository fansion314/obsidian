#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./obsidian-electron/PKGBUILD
release_name=$pkgname
app_version=$pkgver
version="${pkgver}-${pkgrel}"
tag="v${version}"
[[ ${GITHUB_REF_TYPE:-} == tag && ${GITHUB_REF_NAME:-} == "$tag" ]]

asset="${pkgname}-${version}-x86_64.pkg.tar.zst"
test -s "dist/x86_64/$asset"
notes=$(mktemp)
trap 'rm -f "$notes"' EXIT
{
    printf 'Official Obsidian %s application resources repackaged for Arch Linux,\n' "$app_version"
    cat <<'EOF'
using the latest system `electron` package. Bundled Electron is excluded.

Two mutually exclusive package recipes are provided:
- `obsidian-electron`: extracts the required resources from the official installer.
- `obsidian-electron-bin`: downloads this release's prebuilt application archive.

This release contains an Arch package installable with `pacman -U`.
The `obsidian-electron-bin` AUR recipe downloads it, verifies its SHA-256,
and repackages it through makepkg. Application files are installed in
`/usr/lib/obsidian-electron` and use system Electron.

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
gh release upload "$tag" "dist/x86_64/$asset" --repo "$GITHUB_REPOSITORY" --clobber
gh release edit "$tag" --repo "$GITHUB_REPOSITORY" --draft=false --latest
