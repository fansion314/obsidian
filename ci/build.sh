#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
root=$PWD
case ${1:-} in
    ''|--source-only) ;;
    *) echo 'Usage: ci/build.sh [--source-only]' >&2; exit 1 ;;
esac
if (( EUID == 0 )); then
    echo 'Run this script as an unprivileged makepkg user.' >&2
    exit 1
fi
source ./obsidian-electron/PKGBUILD
version="${pkgver}-${pkgrel}"
if [[ ${GITHUB_REF_TYPE:-} == tag && ${GITHUB_REF_NAME:-} != "v${version}" ]]; then
    echo "Release tag must be v${version}, matching PKGBUILD." >&2
    exit 1
fi
outdir="$root/dist/x86_64"
mkdir -p "$outdir" "$root/.cache/sources"
metadata=$(mktemp)
config=$(mktemp)
trap 'rm -f "$metadata" "$config"' EXIT
cat > "$config" <<EOF
source /etc/makepkg.conf
SRCDEST='$root/.cache/sources'
EOF

build_recipe() (
    local recipe=$1
    cd "$root/$recipe"
    bash -n PKGBUILD
    makepkg --printsrcinfo > "$metadata"
    diff -u .SRCINFO "$metadata"
    grep -Fx "pkgname = $recipe" "$metadata"
    grep -Fx $'\tarch = x86_64' "$metadata"
    grep -Fx $'\tdepends = electron' "$metadata"
    # Stage and validate each recipe without producing redundant pacman archives.
    makepkg --config "$config" --cleanbuild --force --noconfirm --noarchive
    local appdir="pkg/$recipe/opt/Obsidian"
    test -s "$appdir/app.asar"
    test -s "$appdir/obsidian.asar"
    desktop-file-validate "$appdir/md.obsidian.Obsidian.desktop"
    [[ $(readlink "pkg/$recipe/usr/bin/obsidian") == /opt/Obsidian/obsidian ]]
    [[ $(readlink "pkg/$recipe/usr/share/applications/md.obsidian.Obsidian.desktop") == /opt/Obsidian/md.obsidian.Obsidian.desktop ]]
    for addon in btime get-fonts; do
        readelf -h "$appdir/app.asar.unpacked/node_modules/$addon/binding.node" | grep -F 'Advanced Micro Devices X86-64'
    done
)

bash -n obsidian-electron/obsidian.sh
build_recipe obsidian-electron

# A deterministic application archive allows the -bin recipe to pin its exact
# release checksum before publishing. Never include pacman build metadata here.
payload="obsidian-electron-${version}-x86_64.tar.gz"
tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner --format=gnu \
    -C obsidian-electron/pkg/obsidian-electron/opt -cf - Obsidian \
    | gzip -n > "$outdir/$payload"
sha256sum "$outdir/$payload"

# Maintainers can build this payload first when updating the -bin checksum.
[[ ${1:-} != --source-only ]] || exit 0
# makepkg still verifies the pinned GitHub source hash, using this CI-built
# archive as its source cache until the matching release has been published.
cp "$outdir/$payload" "$root/.cache/sources/$payload"
build_recipe obsidian-electron-bin
diff -r obsidian-electron/pkg/obsidian-electron/opt/Obsidian \
    obsidian-electron-bin/pkg/obsidian-electron-bin/opt/Obsidian
printf 'Built one release payload and verified both recipes for %s\n' "$version"
