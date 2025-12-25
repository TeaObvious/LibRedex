#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Config ---------------------------------------------------------------

DEBIAN_AMD64_IMAGE="${DEBIAN_AMD64_IMAGE:-docker.io/library/debian:bookworm-slim}"
DEBIAN_I386_IMAGE="${DEBIAN_I386_IMAGE:-docker.io/library/debian:bookworm-slim}"  # force i386 via --arch

GEN="${GEN:-Ninja}"                 # Ninja or "Unix Makefiles"
MODE="${MODE:-release}"             # release | debug | both

# MinGW: Script meta target = ALWAYS build 32-bit + 64-bit (via workflow presets)
PRESET_MINGW32_RELEASE="${PRESET_MINGW32_RELEASE:-mingw32-release-workflow}"
PRESET_MINGW64_RELEASE="${PRESET_MINGW64_RELEASE:-mingw64-release-workflow}"
PRESET_MINGW32_DEBUG="${PRESET_MINGW32_DEBUG:-mingw32-debug-workflow}"
PRESET_MINGW64_DEBUG="${PRESET_MINGW64_DEBUG:-mingw64-debug-workflow}"

DO_LINUX32="${DO_LINUX32:-1}"
DO_LINUX64="${DO_LINUX64:-1}"
DO_MINGW="${DO_MINGW:-1}"

# APT download cache on host (1 = enabled)
APT_CACHE="${APT_CACHE:-1}"

# Where to store apt cache (host path)
APT_CACHE_ROOT="${APT_CACHE_ROOT:-/mnt/ssd-vault/container-images/apt-cache}"

# --------------------------------------------------------------------------

log(){ echo -e "\n==> $*\n"; }
die(){ echo "ERROR: $*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

detect_container_rt() {
  if command -v podman >/dev/null 2>&1; then echo podman; return; fi
  if command -v docker  >/dev/null 2>&1; then echo docker;  return; fi
  echo ""
}

CTR="$(detect_container_rt)"

usage() {
  cat <<EOF
Usage: ./build-all.sh [--release|--debug|--both] [--no-linux32] [--no-linux64] [--no-mingw]

Notes:
- No git commands are executed.
- Uses your working tree as-is (third_party must already exist).
- Linux32 uses Debian container forced to i386 via --arch i386 (podman).
- MinGW always builds BOTH 32-bit and 64-bit via workflow presets:
    $PRESET_MINGW32_RELEASE / $PRESET_MINGW64_RELEASE
    $PRESET_MINGW32_DEBUG   / $PRESET_MINGW64_DEBUG
- APT package downloads are cached on host via APT_CACHE=1, and we hard-save debs
  into archives/saved/ to survive any post-install unlink/cleanup behavior.

Env overrides:
  MODE=release|debug|both
  GEN=Ninja|"Unix Makefiles"
  DO_LINUX32=0/1 DO_LINUX64=0/1 DO_MINGW=0/1
  APT_CACHE=0/1
  APT_CACHE_ROOT=/mnt/ssd-vault/container-images/apt-cache
  DEBIAN_AMD64_IMAGE=...
  DEBIAN_I386_IMAGE=...
  PRESET_MINGW32_RELEASE=... PRESET_MINGW64_RELEASE=...
  PRESET_MINGW32_DEBUG=...   PRESET_MINGW64_DEBUG=...
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release) MODE="release"; shift ;;
    --debug)   MODE="debug"; shift ;;
    --both)    MODE="both"; shift ;;
    --no-linux32) DO_LINUX32=0; shift ;;
    --no-linux64) DO_LINUX64=0; shift ;;
    --no-mingw)   DO_MINGW=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown arg: $1" ;;
  esac
done

check_worktree() {
  [[ -d "$ROOT/third_party/boost" ]] || die "third_party/boost missing"
  [[ -d "$ROOT/third_party/mariadb-connector-c" ]] || die "third_party/mariadb-connector-c missing"
  [[ -f "$ROOT/CMakePresets.json" ]] || die "CMakePresets.json not found in repo root"
}

cmake_cfgs_for_mode() {
  case "$MODE" in
    release) echo "Release" ;;
    debug)   echo "Debug" ;;
    both)    echo "Release Debug" ;;
    *) die "Invalid MODE=$MODE (use release|debug|both)" ;;
  esac
}

# Sanitize image string into a safe directory name
# docker.io/library/debian:bookworm-slim -> docker.io_library_debian__bookworm-slim
img_to_dir() {
  local s="$1"
  s="${s//\//_}"
  s="${s//:/__}"
  echo "$s"
}

run_container_build() {
  local arch="$1"      # "i386" or "" for default
  local image="$2"
  local bdir="$3"      # e.g. build/32bit-linux/Release
  local cfg="$4"       # Release|Debug

  [[ -n "$CTR" ]] || die "podman/docker not found (needed for container builds)"

  local arch_args=()
  local arch_tag="amd64"
  if [[ -n "$arch" ]]; then
    # NOTE: podman supports --arch. docker would need --platform.
    arch_args+=(--arch "$arch")
    arch_tag="$arch"
  fi

  local uid gid
  uid="$(id -u)"
  gid="$(id -g)"

  log "Container build: ${image} (arch=${arch:-host}) -> ${bdir} (${cfg})"

  local cache_mounts=()
  if [[ "$APT_CACHE" == "1" ]]; then
    local imgdir; imgdir="$(img_to_dir "$image")"
    local apt_archives_host="${APT_CACHE_ROOT}/${imgdir}/${arch_tag}/archives"
    local apt_lists_host="${APT_CACHE_ROOT}/${imgdir}/${arch_tag}/lists"

    mkdir -p "$apt_archives_host" "$apt_lists_host"

    # Mount host cache into container
    cache_mounts+=(
      -v "$apt_archives_host:/var/cache/apt/archives"
      -v "$apt_lists_host:/var/lib/apt/lists"
    )
  fi

  "$CTR" run --rm -t \
    "${arch_args[@]}" \
    -e "HOST_UID=${uid}" \
    -e "HOST_GID=${gid}" \
    "${cache_mounts[@]}" \
    -v "$ROOT:/workspace/LibRedex" \
    -w "/workspace/LibRedex" \
    "$image" bash -lc "
      set -euo pipefail
      export DEBIAN_FRONTEND=noninteractive

      # ensure dirs exist even if mounted empty
      mkdir -p /var/lib/apt/lists/partial /var/cache/apt/archives/partial

      # Debian slim images often ship an APT hook that deletes cached *.deb (docker-clean).
      # Remove it so it can't fight our caching.
      if [[ -f /etc/apt/apt.conf.d/docker-clean ]]; then
        rm -f /etc/apt/apt.conf.d/docker-clean
      fi

      # Be explicit (doesn't hurt), but we also add a hard 'saved/' copy below.
      cat >/etc/apt/apt.conf.d/90keep-downloaded-packages <<'EOF'
APT::Keep-Downloaded-Packages \"true\";
Binary::apt::APT::Keep-Downloaded-Packages \"true\";
EOF

      apt-get -o Acquire::Retries=3 update

      # Packages needed for the build
      pkgs=(
        ca-certificates
        build-essential
        cmake ninja-build
        pkg-config
        python3
        file
        zlib1g-dev
        libssl-dev
        libcurl4-openssl-dev
        libsasl2-dev
        libldap2-dev
        libkrb5-dev
        uuid-dev
      )

      # 1) Download ONLY (fills /var/cache/apt/archives/*.deb)
      apt-get -o Acquire::Retries=3 \
              -o APT::Get::Download-Only=true \
        install -y --no-install-recommends \"\${pkgs[@]}\"

      # 2) Hard-save downloaded debs so they survive even if apt unlinks after install
      mkdir -p /var/cache/apt/archives/saved
      cp -an /var/cache/apt/archives/*.deb /var/cache/apt/archives/saved/ 2>/dev/null || true

      # 3) Install (should mostly use cache)
      apt-get -o Acquire::Retries=3 \
        install -y --no-install-recommends \"\${pkgs[@]}\"

      # 4) Restore (if apt removed anything, put it back from saved/)
      cp -an /var/cache/apt/archives/saved/*.deb /var/cache/apt/archives/ 2>/dev/null || true

      cmake -S . -B '$bdir' -G '$GEN' -DCMAKE_BUILD_TYPE='$cfg'
      cmake --build '$bdir'

      chown -R \"\$HOST_UID:\$HOST_GID\" '$bdir' || true
      chown -R \"\$HOST_UID:\$HOST_GID\" Binaries || true
    "
}

run_workflow() {
  local preset="$1"
  log "Host workflow build: ${preset}"
  cmake --workflow --preset "$preset"
}

collect_artifacts() {
  local cfg="$1"
  local outdir="$ROOT/Binaries/$cfg"
  mkdir -p "$outdir"

  find "$ROOT/Binaries" -maxdepth 4 -type f \( -name "*.so" -o -name "*.dll" \) -print | while read -r f; do
    cp -f "$f" "$outdir/" || true
  done

  log "Artifacts in ${outdir}:"
  ls -la "$outdir" || true

  if command -v file >/dev/null 2>&1; then
    log "file(1) info (${cfg}):"
    find "$outdir" -maxdepth 1 -type f \( -name "*.so" -o -name "*.dll" \) -print0 2>/dev/null \
      | xargs -0 -r file
  fi
}

# ---- Main -----------------------------------------------------------------

need_cmd cmake
check_worktree
mkdir -p "$ROOT/build"

log "Root: $ROOT"
log "Mode: $MODE"
log "Container runtime: ${CTR:-<none>}"
log "Generator: $GEN"
log "APT cache: $APT_CACHE"
log "APT cache root: $APT_CACHE_ROOT"

for CFG in $(cmake_cfgs_for_mode); do
  if [[ "$DO_LINUX32" == "1" ]]; then
    run_container_build "i386" "$DEBIAN_I386_IMAGE" "build/32bit-linux/$CFG" "$CFG"
  else
    log "Skipping Linux32 ($CFG)."
  fi

  if [[ "$DO_LINUX64" == "1" ]]; then
    run_container_build "" "$DEBIAN_AMD64_IMAGE" "build/64bit-linux/$CFG" "$CFG"
  else
    log "Skipping Linux64 ($CFG)."
  fi

  if [[ "$DO_MINGW" == "1" ]]; then
    # MinGW means: ALWAYS build 32-bit + 64-bit
    need_cmd i686-w64-mingw32-gcc
    need_cmd i686-w64-mingw32-g++
    need_cmd x86_64-w64-mingw32-gcc
    need_cmd x86_64-w64-mingw32-g++

    if [[ "$CFG" == "Release" ]]; then
      run_workflow "$PRESET_MINGW32_RELEASE"
      run_workflow "$PRESET_MINGW64_RELEASE"
    else
      run_workflow "$PRESET_MINGW32_DEBUG"
      run_workflow "$PRESET_MINGW64_DEBUG"
    fi
  else
    log "Skipping MinGW ($CFG)."
  fi

  collect_artifacts "$CFG"
done

log "Done."
