#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# Copyright salsa-ci-team and others
# Copyright You-Sheng Yang and others
# SPDX-License-Identifier: FSFAP
# Copying and distribution of this file, with or without modification, are
# permitted in any medium without royalty provided the copyright notice and
# this notice are preserved. This file is offered as-is, without any warranty.

# shellcheck disable=SC1091
source /usr/local/bin/lib.sh

set -eu -o pipefail

cd "${INPUT_SOURCE_PATH}" || exit 1
create_user_for .

echo "::group::Fixup INPUT_* variables"
# Fixup INPUT_OUTPUT_PATH
INPUT_OUTPUT_PATH="$(dirname "${INPUT_SOURCE_PATH}")"
SUDO mkdir -vp "${INPUT_OUTPUT_PATH}"
INPUT_OUTPUT_PATH="$(realpath "${INPUT_OUTPUT_PATH}")"
# Fixup INPUT_BUILD_ARCH. `dpkg-architecture` not installed yet at this moment.
INPUT_BUILD_ARCH="${INPUT_BUILD_ARCH:-$(dpkg --print-architecture)}"
# Fixup INPUT_HOST_ARCH
INPUT_HOST_ARCH="${INPUT_HOST_ARCH:-${INPUT_BUILD_ARCH}}"
# Fixup INPUT_BUILD_TYPE
INPUT_BUILD_TYPE="${INPUT_BUILD_TYPE:-full}"
# Fixup INPUT_BUILD_TWICE
INPUT_BUILD_TWICE="$(fixup_boolean "${INPUT_BUILD_TWICE}" false)"
# Fixup INPUT_BUILD_ARGS
INPUT_BUILD_ARGS="${INPUT_BUILD_ARGS:-}"
# Fixup INPUT_VERSION_BUMP
version_bump_default='true'
if [ "${INPUT_BUILD_TYPE}" = source ] || [ "${INPUT_BUILD_TYPE}" = full ]; then
  version_bump_default='false'
fi
INPUT_VERSION_BUMP="$(fixup_boolean "${INPUT_VERSION_BUMP}" "${version_bump_default}")"

while IFS='=' read -r -d '' name value; do
  case "${name}" in
  INPUT_*) echo "${name}=${value}";;
  esac
done < <(env -0)
echo "::endgroup::"

# Check if architecture is buildable

if [ "${INPUT_BUILD_TYPE}" != full ] \
    && [ "${INPUT_BUILD_TYPE}" != binary ] \
    && [ "${INPUT_BUILD_TYPE}" != source ]; then
  if [ "${INPUT_BUILD_TYPE}" = all ]; then
    pattern="all"
  elif [ "${INPUT_BUILD_TYPE}" = any ]; then
    if [ -n "${INPUT_HOST_ARCH}" ]; then
      pattern=".*(any|[^\!]${INPUT_HOST_ARCH})"
    else
      pattern=".*(any|[^\!]$(dpkg --print-architecture))"
    fi
  else
    echo "Error: Unexpected INPUT_BUILD_TYPE: ${INPUT_BUILD_TYPE}."
    exit 1
  fi
  if ! grep -qE "^Architecture:\s*${pattern}" debian/control; then
    echo "### No binary package matched: '${pattern}'. ###"
    exit 0
  fi
  unset pattern
fi

# add target architecture if cross-compiling
CROSS_COMPILING="${INPUT_BUILD_ARCH#"${INPUT_HOST_ARCH}"}"
test -z "${CROSS_COMPILING}" || dpkg --add-architecture "${INPUT_HOST_ARCH}"

# Add deb-src entries
if [ -f /etc/apt/sources.list ]; then
  sed -n '/^deb\s/s//deb-src /p' /etc/apt/sources.list > /etc/apt/sources.list.d/deb-src.list
fi
if [ -f /etc/apt/sources.list.d/debian.sources ]; then
  sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/debian.sources
fi

echo "::group::apt-get upgrade"
apt-get update && eatmydata apt-get upgrade -y
echo "::endgroup::"

echo "::group::Install prerequisites"
eatmydata apt-get install --no-install-recommends -y \
  ccache \
  fakeroot \
  build-essential

# in case we are cross-building, install some more dependencies
# see #815172 why we need libc-dev and libstdc++-dev
test -z "${CROSS_COMPILING}" || eatmydata apt-get satisfy --no-install-recommends -y \
  "libc-dev:${INPUT_HOST_ARCH}" \
  "libstdc++-dev:${INPUT_HOST_ARCH}" \
  "crossbuild-essential-${INPUT_HOST_ARCH}"

# when cross-compiling, add 'nocheck' to the DEB_BUILD_OPTIONS
test -z "${CROSS_COMPILING}" || export DEB_BUILD_OPTIONS="nocheck ${DEB_BUILD_OPTIONS:-}"

# Install package build dependencies
# use plain "apt-get build-dep" so that we can install only packages for
# architecture indep or arch:any builds
aptopts=(--no-install-recommends -y)
test "${INPUT_BUILD_TYPE}" != "any" || aptopts+=(--arch-only)
test "${INPUT_BUILD_TYPE}" != "all" || aptopts+=(--indep-only)
test -z "${CROSS_COMPILING}" || aptopts+=(--host-architecture "${INPUT_HOST_ARCH}" "-Pcross,nocheck")

eatmydata apt-get build-dep "${aptopts[@]}" .
echo "::endgroup::"

# If not disabled, bump package version
if [ "${INPUT_VERSION_BUMP}" = true ]; then
  SUDO sed -i -e "1 s/)/+salsaci+$(date +"%Y%m%d")+${GITHUB_RUN_ID})/" debian/changelog
fi

# Generate ccache links
echo "::group::ccache statistics before build"
dpkg-reconfigure ccache
PATH="/usr/lib/ccache/:${PATH}"

# Reset ccache stats
export CCACHE_DIR="${INPUT_OUTPUT_PATH}/.ccache"
SUDO mkdir -vp "${CCACHE_DIR}"
SUDO ccache -z
SUDO ccache -s -v
echo "::endgroup::"

# Define buildlog filename
BUILD_LOGFILE_SOURCE="$(dpkg-parsechangelog -S Source)"
BUILD_LOGFILE_VERSION="$(dpkg-parsechangelog -S Version)"
BUILD_LOGFILE_VERSION="${BUILD_LOGFILE_VERSION#*:}"
BUILD_LOGFILE_ARCH="${INPUT_HOST_ARCH}"
BUILD_LOGFILE="${INPUT_OUTPUT_PATH}/${BUILD_LOGFILE_SOURCE}_${BUILD_LOGFILE_VERSION}_${BUILD_LOGFILE_ARCH}.build"

# Define build command
BUILD_COMMAND=(eatmydata dpkg-buildpackage "--build=${INPUT_BUILD_TYPE}")
test -z "${CROSS_COMPILING}" || BUILD_COMMAND+=(--host-arch "${INPUT_HOST_ARCH}" "-Pcross,nocheck")
IFS=" " read -r -a dpkgargs <<< "${INPUT_BUILD_ARGS}"
BUILD_COMMAND+=("${dpkgargs[@]}")
# Set architecture to correct in case it is i386 to avoid pitfalls (See #284)
test "${INPUT_BUILD_ARCH}" = "i386" && BUILD_COMMAND=(/usr/bin/setarch i686 "${BUILD_COMMAND[@]}")

# Print the build environment
echo "::group::Build environment dump"
printenv | sort
echo "::endgroup::"

# Build package as current user
echo "::group::Build"
{ \
  SUDO "${BUILD_COMMAND[@]}" && if [ "${INPUT_BUILD_TWICE}" = true ]; then \
    SUDO "${BUILD_COMMAND[@]}"; \
  fi; \
} | SUDO tee "${BUILD_LOGFILE}"
echo "::endgroup::"

# Restore PWD to ${INPUT_OUTPUT_PATH}
cd "${INPUT_OUTPUT_PATH}" || exit 1

# Print ccache stats on job log
echo "::group::ccache statistics after build"
ccache -s -v
echo "::endgroup::"

# Print size of artifacts after build
echo "::group::Output directory size"
du -sh
echo "::endgroup::"

echo "::group::Outputs"
{ \
  echo "output_path=$(realpath --relative-to="${GITHUB_WORKSPACE}" "${INPUT_OUTPUT_PATH}")"; \
  echo "release=${INPUT_RELEASE}"; \
  echo "source_path=$(realpath --relative-to="${GITHUB_WORKSPACE}" "${INPUT_SOURCE_PATH}")"; \
  echo "build_arch=${INPUT_BUILD_ARCH}"; \
  echo "host_arch=${INPUT_HOST_ARCH}"; \
  echo "build_type=${INPUT_BUILD_TYPE}"; \
  echo "build_twice=${INPUT_BUILD_TWICE}"; \
  echo "version_bump=${INPUT_VERSION_BUMP}"; \
} | tee -a "${GITHUB_OUTPUT}"
echo "::endgroup::"
