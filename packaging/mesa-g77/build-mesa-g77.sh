#!/usr/bin/env bash
# Stage and build the mesa-g77 Arch Linux ARM (aarch64) package offline from
# sources/mesa (commit 7d6bb09d5b59ec5af1a58971f34390a62943bfe0) and the 15
# patches in sources/port/mesa/patches/, without modifying sources/ or leaving
# build artifacts in packaging/mesa-g77/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PKG_DIR="$ROOT/packaging/mesa-g77"
MESA_SRC="$ROOT/sources/mesa"
PATCH_DIR="$ROOT/sources/port/mesa/patches"
EXPECTED_COMMIT="7d6bb09d5b59ec5af1a58971f34390a62943bfe0"

DRY_RUN=0
USE_DOCKER=0
WORKDIR="${MESA_G77_WORKDIR:-$ROOT/out/build/mesa-g77-pkg}"
PKG_OUT="${MESA_G77_OUT:-$ROOT/out/packages}"
DOCKER_IMAGE="${MESA_G77_DOCKER_IMAGE:-}"

usage() {
  cat <<'EOF'
usage: build-mesa-g77.sh [--dry-run] [--docker] [--workdir DIR] [--out DIR]

Options:
  --dry-run      Validate sources, patches, and PKGBUILD without building
  --docker       Build inside an aarch64 Arch Linux ARM container
                 (requires MESA_G77_DOCKER_IMAGE=<aarch64-image> + binfmt/qemu-aarch64)
  --workdir DIR  Staging/makepkg directory (default: out/build/mesa-g77-pkg)
  --out DIR      Output directory for built .pkg.tar.* (default: out/packages)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --docker) USE_DOCKER=1; shift ;;
    --workdir) WORKDIR="$2"; shift 2 ;;
    --out) PKG_OUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

log() { printf '== [mesa-g77] %s ==\n' "$*"; }

[ -d "$MESA_SRC/.git" ] || { echo "missing mesa git repo: $MESA_SRC" >&2; exit 1; }
ACTUAL_COMMIT="$(git -C "$MESA_SRC" rev-parse HEAD)"
if [ "$ACTUAL_COMMIT" != "$EXPECTED_COMMIT" ]; then
  echo "ERROR: sources/mesa HEAD ($ACTUAL_COMMIT) != expected ($EXPECTED_COMMIT)" >&2
  exit 1
fi

for f in PKGBUILD r8s-mesa-g77.sh 90-r8s-mesa-g77.conf mesa-g77-run 20-r8s-mesa-g77.conf; do
  [ -f "$PKG_DIR/$f" ] || { echo "missing packaging file: $PKG_DIR/$f" >&2; exit 1; }
done

PATCH_COUNT=$(find "$PATCH_DIR" -maxdepth 1 -name '*.patch' | wc -l)
if [ "$PATCH_COUNT" -ne 15 ]; then
  echo "ERROR: expected 15 patches in $PATCH_DIR, found $PATCH_COUNT" >&2
  exit 1
fi

bash -n "$PKG_DIR/PKGBUILD"
sh -n "$PKG_DIR/r8s-mesa-g77.sh"
sh -n "$PKG_DIR/mesa-g77-run"

if [ "$DRY_RUN" = "1" ]; then
  log "DRY-RUN: commit=$ACTUAL_COMMIT patches=$PATCH_COUNT workdir=$WORKDIR out=$PKG_OUT docker=$USE_DOCKER"
  exit 0
fi

HOST_ARCH="$(uname -m)"
if [ "$USE_DOCKER" -eq 0 ] && [ "$HOST_ARCH" != "aarch64" ]; then
  echo "ERROR: host is $HOST_ARCH (not aarch64). Run natively on r8s/aarch64 Arch ARM or pass --docker with MESA_G77_DOCKER_IMAGE." >&2
  exit 1
fi
if [ "$USE_DOCKER" -eq 1 ]; then
  if [ -z "$DOCKER_IMAGE" ] || [ "$DOCKER_IMAGE" = "archlinux:latest" ]; then
    echo "ERROR: official archlinux:latest is x86_64-only. Set MESA_G77_DOCKER_IMAGE to an aarch64 Arch Linux ARM image (e.g. locally imported ArchLinuxARM-aarch64-latest.tar.gz)." >&2
    exit 1
  fi
fi

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR/srcdest" "$PKG_OUT"

cp -a "$PKG_DIR"/{PKGBUILD,r8s-mesa-g77.sh,90-r8s-mesa-g77.conf,mesa-g77-run,20-r8s-mesa-g77.conf} "$WORKDIR/"
cp -a "$PATCH_DIR"/*.patch "$WORKDIR/"

# Stage a bare local git upstream from sources/mesa so makepkg clones/fetches offline via file://.
cp -a "$MESA_SRC/.git" "$WORKDIR/mesa-upstream.git"
git -C "$WORKDIR/mesa-upstream.git" config --bool core.bare true

if [ "$USE_DOCKER" -eq 1 ]; then
  log "Building mesa-g77 inside aarch64 container ($DOCKER_IMAGE)"
  docker run --rm --platform linux/arm64 \
    -v "$WORKDIR:/build" \
    -v "$PKG_OUT:/pkgout" \
    "$DOCKER_IMAGE" bash -euo pipefail -c '
      pacman -Syu --noconfirm --needed base-devel git meson ninja pkgconf \
        bison flex python python-mako python-yaml python-packaging python-ply \
        llvm clang spirv-llvm-translator spirv-tools wayland-protocols xorgproto \
        expat libdisplay-info libdrm libelf libglvnd libx11 libxcb libxext \
        libxfixes libxshmfence libxxf86vm systemd-libs wayland zlib zstd
      useradd -m -s /bin/bash builder || true
      chown -R builder:builder /build /pkgout
      su - builder -c "cd /build && MESA_G77_GIT_URL=file:///build/mesa-upstream.git SRCDEST=/build/srcdest PKGDEST=/pkgout makepkg --noconfirm"
    '
else
  log "Building mesa-g77 natively on aarch64 host"
  (
    cd "$WORKDIR"
    MESA_G77_GIT_URL="file://$WORKDIR/mesa-upstream.git" \
      SRCDEST="$WORKDIR/srcdest" \
      PKGDEST="$PKG_OUT" \
      makepkg --syncdeps --noconfirm
  )
fi

log "Built package(s) in $PKG_OUT:"
ls -lh "$PKG_OUT"/mesa-g77-*.pkg.tar.*
