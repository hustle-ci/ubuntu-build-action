# Copyright salsa-ci-team and others
# SPDX-License-Identifier: FSFAP
# Copying and distribution of this file, with or without modification, are
# permitted in any medium without royalty provided the copyright notice and
# this notice are preserved. This file is offered as-is, without any warranty.

ARG BASE_IMAGE=debian

################################################################################

FROM bash AS dummy

################################################################################

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
		sudo \
	; \
	apt-get autoremove --purge -y; \
	apt-get clean; \
	rm -rf /var/lib/apt

COPY scripts/lib.sh /usr/local/bin/lib.sh

################################################################################

FROM base AS gbp

# Add deb-src entries
RUN set -eux; \
	if [ -f /etc/apt/sources.list ]; then \
		sed -n '/^deb\s/s//deb-src /p' /etc/apt/sources.list > /etc/apt/sources.list.d/deb-src.list; \
	fi; \
	if [ -f /etc/apt/sources.list.d/debian.sources ]; then \
		sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/debian.sources; \
	fi; \
	:

RUN set -eux; \
	apt-get update --quiet; \
	apt-get upgrade -y; \
	eatmydata apt-get install --no-install-recommends -y \
		curl \
		git-buildpackage \
		pristine-tar \
		unzip \
	; \
	rm -rf /var/lib/apt

COPY scripts/extract-source.sh /usr/local/bin/extract-source.sh
