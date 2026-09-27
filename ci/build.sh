#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
target_arch=x86_64
if (( EUID == 0 )); then
    echo 'Run this script as an unprivileged makepkg user.' >&2
    exit 1
fi

# This package only copies prebuilt upstream files.
source ./PKGBUILD
version="${pkgver}-${pkgrel}"
if [[ ${GITHUB_REF_TYPE:-} == tag && ${GITHUB_REF_NAME:-} != "v${version}" ]]; then
    echo "Release tag must be v${version}, matching PKGBUILD." >&2
    exit 1
fi
bash -n PKGBUILD obsidian.sh
desktop-file-validate md.obsidian.Obsidian.desktop
metadata=$(mktemp)
config=$(mktemp)
trap 'rm -f "$metadata" "$config"' EXIT
makepkg --printsrcinfo > "$metadata"
diff -u .SRCINFO "$metadata"

mkdir -p "dist/$target_arch"
outdir=$(realpath "dist/$target_arch")
cat > "$config" <<EOF
source /etc/makepkg.conf
CARCH='$target_arch'
CHOST='$target_arch-pc-linux-gnu'
PKGDEST='$outdir'
SRCDEST='$PWD'
SRCPKGDEST='$outdir'
PKGEXT='.pkg.tar.zst'
SRCEXT='.src.tar.gz'
EOF
makepkg --config "$config" --cleanbuild --force --noconfirm
package="$outdir/${pkgname}-${version}-${target_arch}.pkg.tar.zst"
test -s "$package"
bsdtar -xOf "$package" .PKGINFO | grep -Fx "arch = $target_arch"
bsdtar -xOf "$package" .PKGINFO | grep -Fx 'depend = electron'
test -s "pkg/$pkgname/opt/Obsidian/app.asar"
test -s "pkg/$pkgname/opt/Obsidian/obsidian.asar"
test -f "pkg/$pkgname/opt/Obsidian/md.obsidian.Obsidian.desktop"
[[ $(readlink "pkg/$pkgname/usr/bin/obsidian") == /opt/Obsidian/obsidian ]]
[[ $(readlink "pkg/$pkgname/usr/share/applications/md.obsidian.Obsidian.desktop") == /opt/Obsidian/md.obsidian.Obsidian.desktop ]]
for addon in btime get-fonts; do
    readelf -h "pkg/$pkgname/opt/Obsidian/app.asar.unpacked/node_modules/$addon/binding.node" | grep -F 'Advanced Micro Devices X86-64'
done
makepkg --config "$config" --source --force
printf 'Built %s\n' "$package"
