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
INPUT_OUTPUT_PATH="$(realpath -m "${INPUT_OUTPUT_PATH:-${INPUT_SOURCE_PATH}}")"

cd "${INPUT_SOURCE_PATH}" || exit 1
create_user_for .

echo "::group::Fixup INPUT_* variables"
# Fixup INPUT_OUTPUT_PATH
SUDO mkdir -vp "${INPUT_OUTPUT_PATH}"
# Fixup INPUT_TESTBED
INPUT_TESTBED="${INPUT_TESTBED:-ghcr.io/${GITHUB_REPOSITORY_OWNER}/base:${INPUT_RELEASE}}"
# Fixup INPUT_ARGS
INPUT_ARGS="${INPUT_ARGS:-}"

while IFS='=' read -r -d '' name value; do
  case "${name}" in
  INPUT_*) echo "${name}=${value}";;
  esac
done < <(env -0)
echo "::endgroup::"

echo "::group::Docker info"
docker info
echo "::endgroup::"

echo "::group::Generate report"
autopkgtest "${INPUT_SOURCE_PATH}"/*.changes \
    --setup-commands="apt-get update" \
    --output-dir="${INPUT_OUTPUT_PATH}"/autopkgtest \
    --apt-upgrade \
    -- \
    docker \
    --remote \
    "${INPUT_TESTBED}"
echo "::endgroup::"

echo "::group::Outputs"
{ \
  echo "output_path=$(realpath --relative-to="${GITHUB_WORKSPACE}" "${INPUT_OUTPUT_PATH}")"; \
  echo "release=${INPUT_RELEASE}"; \
  echo "source_path=$(realpath --relative-to="${GITHUB_WORKSPACE}" "${INPUT_SOURCE_PATH}")"; \
  echo "testbed=${INPUT_TESTBED}"; \
} | tee -a "${GITHUB_OUTPUT}"
echo "::endgroup::"
