#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# Copyright salsa-ci-team and others
# SPDX-License-Identifier: FSFAP
# Copying and distribution of this file, with or without modification, are
# permitted in any medium without royalty provided the copyright notice and
# this notice are preserved. This file is offered as-is, without any warranty.

# shellcheck disable=SC1091
source /usr/local/bin/lib.sh

set -eu -o pipefail

# Relative path calculcating must be done before chdir().
INPUT_OUTPUT_PATH="$(realpath -m "${INPUT_OUTPUT_PATH:-${INPUT_SOURCE_PATH}/debian/output}")"

cd "${INPUT_SOURCE_PATH}" || exit 1
create_user_for .

echo "::group::Fixup INPUT_* variables"
# Fixup INPUT_OUTPUT_PATH
SUDO mkdir -vp "${INPUT_OUTPUT_PATH}"
# Fixup INPUT_SETUP_GITATTRIBUTES
INPUT_SETUP_GITATTRIBUTES="$(fixup_boolean "${INPUT_SETUP_GITATTRIBUTES}" true)"
# Fixup INPUT_SOURCE_ARGS
INPUT_SOURCE_ARGS="${INPUT_SOURCE_ARGS:-}"

while IFS='=' read -r -d '' name value; do
  case "${name}" in
  INPUT_*) echo "${name}=${value}";;
  esac
done < <(env -0)
echo "::endgroup::"

echo "::group::apt-get upgrade"
apt-get update && eatmydata apt-get upgrade -y
echo "::endgroup::"

echo "::group::git setup"
SUDO gbp pull --ignore-branch --pristine-tar --track-missing

# gbp setup-gitattributes needs to be called after gbp pull to avoid having
# staging commits (See #322)
if [ "${INPUT_SETUP_GITATTRIBUTES}" = true ]; then
  test -r .gitattributes && SUDO gbp setup-gitattributes
fi
echo "::endgroup::"


echo "::group::orig tarball extraction"
read -r -a BUILD_ARGS <<< "${INPUT_SOURCE_ARGS}"
if find . -maxdepth 3 -wholename "*/debian/source/format" -exec cat {} \; | \
    grep -q '3.0 (gitarchive)'; then
  eatmydata apt-get install --no-install-recommends -y \
    dpkg-source-gitarchive

  SUDO dpkg-source --build . | SUDO tee /tmp/build.out
  DSC="$(sed -n 's/.* \(\S*.dsc$\)/\1/p' /tmp/build.out)"
  SUDO dpkg-source --extract --no-check "../$DSC" "${INPUT_OUTPUT_PATH}/${DSC%.dsc}"
else
  # Check if we can obtain the orig from the git branches

  if ! SUDO gbp export-orig --tarball-dir="${INPUT_OUTPUT_PATH}"; then
    # Fallback using origtargz
    SUDO origtargz -dt
    SUDO cp -v ../*orig*tar* "${INPUT_OUTPUT_PATH}"
    BUILD_ARGS=(--git-overlay "${BUILD_ARGS[@]}")
  fi

  # As of 2020-09-09, gbp doesn't have a simpler method to extract the
  # debianized source package. Use --git-pbuilder=`/bin/true` for the moment:
  # https://bugs.debian.org/969952

  SUDO gbp buildpackage \
    --git-ignore-branch \
    --git-ignore-new \
    --git-no-create-orig \
    --git-export-dir="${INPUT_OUTPUT_PATH}" \
    --no-check-builddeps \
    --git-builder=/bin/true \
    --git-no-pbuilder \
    --git-no-hooks \
    --git-no-purge \
    "${BUILD_ARGS[@]}"
fi
echo "::endgroup::"

cd "${INPUT_OUTPUT_PATH}" || exit 1
DEBIANIZED_SOURCE=$(find . -maxdepth 3 -wholename "*/debian/changelog" | sed -e 's%/\w*/\w*$%%')
if [ ! "${DEBIANIZED_SOURCE}" ] ; then
  echo "Error: No valid debianized source tree found."
  exit 1
fi

SUDO mv -v "${DEBIANIZED_SOURCE}" "${INPUT_OUTPUT_PATH}/source"

echo "::group::Output directory content"
ls -lh
echo "::endgroup::"

# Print size of artifacts
echo "::group::Output directory size"
du -sh
echo "::endgroup::"

echo "::group::Outputs"
{ \
  echo "source_path=$(realpath --relative-to="${GITHUB_WORKSPACE}" "${INPUT_SOURCE_PATH}")"; \
  echo "output_path=$(realpath --relative-to="${GITHUB_WORKSPACE}" "${INPUT_OUTPUT_PATH}")"; \
  echo "setup_gitattributes=${INPUT_SETUP_GITATTRIBUTES}"; \
  echo "built_source_path=$(realpath --relative-to="${GITHUB_WORKSPACE}" "${INPUT_OUTPUT_PATH}/source")"; \
  echo "built_origtar=$(find . -maxdepth 1 -type f -name \*.orig.tar.\*.asc -printf %f | sed 's,\.asc$,,')"; \
} | tee -a "${GITHUB_OUTPUT}"
echo "::endgroup::"
