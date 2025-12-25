#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Config ---------------------------------------------------------------

DEBIAN_AMD64_IMAGE="${DEBIAN_AMD64_IMAGE:-docker.io/library/debian:bookworm-slim}"
DEBIAN_I386_IMAGE="${DEBIAN_I386_IMAGE:-docker.io/library/debian:bookworm-slim}"  # force i386 via arch/platform

GEN="${GEN:-Ninja}"                 # Ninja or "Unix Makefiles"
MODE="${MODE:-release}"             # release | debug | both

# MinGW: Script meta target = ALWAYS build 32-bit + 64-bit (via presets)
PRESET_MINGW32_RELEASE="${PRESET_MINGW32_RELEASE:-mingw32-release}"
PRESET_MINGW64_RELEASE="${PRESET_MINGW64_RELEASE:-mingw64-release}"
PRESET_MINGW32_DEBUG="${PRESET_MINGW32_DEBUG:-mingw32-debug}"
PRESET_MINGW64_DEBUG="${PRESET_MINGW64_DEBUG:-mingw64-debug}"

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
- Linux32 uses Debian container forced to i386.
- Linux64 uses Debian container forced to amd64 (important to avoid accidentally running i386).
- MinGW always builds BOTH 32-bit and 64-bit via presets:
    $PRESET_MINGW32_RELEASE / $PRESET_MINGW64_RELEASE
    $PRESET_MINGW32_DEBUG   / $PRESET_MINGW64_DEBUG
- APT package downloads are cached on host via APT_CACHE=1.

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

# Build inside container
# arch: "i386" or "amd64" (required for deterministic results!)
run_container_build() {
  local arch="$1"      # "i386" or "amd64"
  local image="$2"
  local bdir="$3"      # e.g. build/32bit-linux/Release
  local cfg="$4"       # Release|Debug

  [[ -n "$CTR" ]] || die "podman/docker not found (needed for container builds)"
  [[ -n "$arch" ]] || die "run_container_build: arch must be set (i386|amd64)"

  local arch_args=()
  local arch_tag="$arch"

  if [[ "$CTR" == "podman" ]]; then
    # Podman: --arch i386|amd64
    arch_args+=(--arch "$arch")
  else
    # Docker: --platform linux/386|linux/amd64
    local plat="linux/amd64"
    if [[ "$arch" == "i386" ]]; then
      plat="linux/386"
    fi
    arch_args+=(--platform "$plat")
  fi

  local uid gid
  uid="$(id -u)"
  gid="$(id -g)"

  log "Container build: ${image} (arch=${arch}) -> ${bdir} (${cfg})"

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

      # Keep downloaded packages
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

      # Download ONLY
      apt-get -o Acquire::Retries=3 \
              -o APT::Get::Download-Only=true \
        install -y --no-install-recommends \"\${pkgs[@]}\"

      # Install
      apt-get -o Acquire::Retries=3 \
        install -y --no-install-recommends \"\${pkgs[@]}\"

      rm -rf '$bdir'
      mkdir -p '$bdir'

      cmake -S . -B '$bdir' -G '$GEN' -DCMAKE_BUILD_TYPE='$cfg'
      cmake --build '$bdir'
    "
}

run_preset_build() {
  local preset="$1"
  log "Host preset build: ${preset}"
  cmake --preset "$preset"
  cmake --build --preset "$preset"
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
    # IMPORTANT: force amd64 explicitly, otherwise we might accidentally reuse a locally cached i386 image tag
    run_container_build "amd64" "$DEBIAN_AMD64_IMAGE" "build/64bit-linux/$CFG" "$CFG"
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
      run_preset_build "$PRESET_MINGW32_RELEASE"
      run_preset_build "$PRESET_MINGW64_RELEASE"
    else
      run_preset_build "$PRESET_MINGW32_DEBUG"
      run_preset_build "$PRESET_MINGW64_DEBUG"
    fi
  else
    log "Skipping MinGW ($CFG)."
  fi

  collect_artifacts "$CFG"
done

log "Done."
