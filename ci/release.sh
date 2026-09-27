#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./PKGBUILD
version="${pkgver}-${pkgrel}"
tag="v${version}"
[[ ${GITHUB_REF_TYPE:-} == tag && ${GITHUB_REF_NAME:-} == "$tag" ]]

assets=(
    "${pkgname}-${version}-x86_64.pkg.tar.zst"
    "${pkgname}-${version}.src.tar.gz"
)
for asset in "${assets[@]}"; do test -s "dist/$asset"; done
(
    cd dist
    sha256sum "${assets[@]}" > SHA256SUMS
    sha256sum --check SHA256SUMS
)
notes=$(mktemp)
trap 'rm -f "$notes"' EXIT
{
    printf 'Official Obsidian %s application resources repackaged for Arch Linux,\n' "$pkgver"
    cat <<'EOF'
using the latest system `electron` package. Bundled Electron is excluded.

Assets include the x86_64 package, the AUR source archive, and SHA256SUMS.
Application files are installed in `/opt/Obsidian`, with symlinks in the standard
command, desktop-entry, icon and license directories.

Install the package for your architecture with `sudo pacman -U <package>.pkg.tar.zst`.
It replaces the repository's `obsidian` package. The desktop entry matches the
upstream Wayland application ID, `md.obsidian.Obsidian`.
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
        --draft --title "$pkgname $version" --notes-file "$notes"
fi
gh release upload "$tag" dist/* --repo "$GITHUB_REPOSITORY" --clobber
gh release edit "$tag" --repo "$GITHUB_REPOSITORY" --draft=false --latest
