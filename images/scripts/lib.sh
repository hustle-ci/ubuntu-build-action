#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# Copyright salsa-ci-team and others
# SPDX-License-Identifier: FSFAP
# Copying and distribution of this file, with or without modification, are
# permitted in any medium without royalty provided the copyright notice and
# this notice are preserved. This file is offered as-is, without any warranty.

cd "${GITHUB_WORKSPACE}" || exit 1
INPUT_SOURCE_PATH="$(realpath "${INPUT_SOURCE_PATH:-${GITHUB_WORKSPACE}}")"

# $1: the path to a file or a directory whose owner user/group to be created
# $2: optional user name
# $3: optional group name
create_user_for()
{
  local path="$1"; shift
  _UID="$(stat --format=%u "${path}")"
  _GID="$(stat --format=%g "${path}")"

  _USER="u${_UID}"
  [ $# -lt 1 ] || { _USER="$1"; shift; }
  _GROUP="g${_GID}"
  [ $# -lt 1 ] || { _GROUP="$1"; shift; }

  if ! getent group "${_GID}"; then
    groupadd --gid "${_GID}" "${_GROUP}"
  fi

  if ! getent passwd "${_UID}"; then
    useradd --uid "${_UID}" --gid "${_GID}" \
        --no-create-home \
        "${_USER}"
  fi
}

SUDO()
{
  sudo --group="${_GROUP}" --user="${_USER}" --preserve-env -- "$@"
}

