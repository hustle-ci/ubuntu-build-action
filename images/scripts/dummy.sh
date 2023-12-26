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
# Fixup INPUT_IMAGE
INPUT_IMAGE="${INPUT_IMAGE:-}"
# Fixup INPUT_INCLUDE_ENV_MATCH
INPUT_INCLUDE_ENV_MATCH="${INPUT_INCLUDE_ENV_MATCH:-}"
# Fixup INPUT_DOCKER_ARGS
INPUT_DOCKER_ARGS="${INPUT_DOCKER_ARGS:-}"
# Fixup INPUT_IMAGE_CMDS
INPUT_IMAGE_CMDS="${INPUT_IMAGE_CMDS:-}"
# Fixup OUTPUT_PATH
SUDO mkdir -vp "${INPUT_OUTPUT_PATH}"

while IFS='=' read -r -d '' name value; do
  case "${name}" in
  INPUT_*) echo "${name}=${value}";;
  esac
done < <(env -0)
echo "::endgroup::"

echo "::group::Outputs"
{ \
  echo "source_path=$(realpath --relative-to="${GITHUB_WORKSPACE}" "${INPUT_SOURCE_PATH}")"; \
  echo "output_path=$(realpath --relative-to="${GITHUB_WORKSPACE}" "${INPUT_OUTPUT_PATH}")"; \
} | tee -a "${GITHUB_OUTPUT}"
echo "::endgroup::"
