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

# Relative path calculcating must be done before chdir().
INPUT_OUTPUT_PATH="$(realpath -m "${INPUT_OUTPUT_PATH:-${INPUT_SOURCE_PATH}}")"

cd "${INPUT_SOURCE_PATH}" || exit 1
create_user_for .

echo "::group::Fixup INPUT_* variables"
# Fixup INPUT_OUTPUT_PATH
SUDO mkdir -vp "${INPUT_OUTPUT_PATH}"
# Fixup INPUT_FATAL_WARNING
INPUT_FATAL_WARNING="$(fixup_boolean "${INPUT_FATAL_WARNING}" false)"
# Fixup INPUT_SHOW_OVERRIDES
INPUT_SHOW_OVERRIDES="$(fixup_boolean "${INPUT_SHOW_OVERRIDES}" false)"
# Fixup INPUT_SUPRESS_TAGS
INPUT_SUPRESS_TAGS="${INPUT_SUPRESS_TAGS:-}"
# Fixup INPUT_ARGS
INPUT_ARGS="${INPUT_ARGS:-}"

while IFS='=' read -r -d '' name value; do
  case "${name}" in
  INPUT_*) echo "${name}=${value}";;
  esac
done < <(env -0)
echo "::endgroup::"

echo "::group::Generate report"
lintian --version

args=(--display-info --pedantic)

IFS=" " read -r -a additional_args <<< "${INPUT_ARGS}"
args+=("${additional_args[@]}")

args+=(--suppress-tags "${INPUT_SUPRESS_TAGS}")

[ "${INPUT_SHOW_OVERRIDES}" = true ] && args+=(--show-overrides)

fatal_args=()
if SUDO lintian --fail-on error > /dev/null ; then
  fatal_args+=(--fail-on error)
  [ "${INPUT_FATAL_WARNING}" = true ] && fatal_args+=(--fail-on warning)
fi

# Do not use glob directly here.
# See: https://unix.stackexchange.com/questions/528361/dash-not-expanding-glob-wildcards-in-chroot
changes="$(find . -maxdepth 1 -name \*.changes)"
output=/tmp/lintian.output
SUDO lintian "${args[@]}" "${fatal_args[@]}" "${changes}" | \
    SUDO tee "${output}" || ECODE=$?
[ "${INPUT_FATAL_WARNING}" = true ] && grep -q '^W: ' "${output}" && ECODE=3

SUDO lintian2junit.py --lintian-file "${output}" > "${INPUT_OUTPUT_PATH}"/lintian.xml

# Generate HTML report
SUDO lintian "${args[@]}" \
    --exp-output format=html \
    "${changes}" > "${INPUT_OUTPUT_PATH}"/lintian.html || true
echo "::endgroup::"

echo "::group::Outputs"
{ \
  echo "output_path=$(realpath --relative-to="${GITHUB_WORKSPACE}" "${INPUT_OUTPUT_PATH}")"; \
  echo "xml_report_path=$(realpath --relative-to="${GITHUB_WORKSPACE}" "${INPUT_OUTPUT_PATH}/lintian.xml")"; \
  echo "html_report_path=$(realpath --relative-to="${GITHUB_WORKSPACE}" "${INPUT_OUTPUT_PATH}/lintian.html")"; \
} | tee -a "${GITHUB_OUTPUT}"
echo "::endgroup::"

exit "${ECODE-0}"
