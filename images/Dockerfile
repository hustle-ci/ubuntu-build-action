# Copyright salsa-ci-team and others
# SPDX-License-Identifier: FSFAP
# Copying and distribution of this file, with or without modification, are
# permitted in any medium without royalty provided the copyright notice and
# this notice are preserved. This file is offered as-is, without any warranty.

ARG BASE_IMAGE
FROM ${BASE_IMAGE} AS base

ARG VENDOR
ARG RELEASE

ENV DEBIAN_FRONTEND noninteractive

RUN set -eux; \
	echo "Acquire::Retries 5;" > /etc/apt/apt.conf.d/hustle-ci; \
	apt-get update --quiet; \
	apt-get upgrade -y; \
	apt-get install --no-install-recommends -y \
		apt \
		ca-certificates \
		eatmydata \
	; \
	apt-get autoremove --purge -y; \
	apt-get clean; \
	rm -rf /var/lib/apt

