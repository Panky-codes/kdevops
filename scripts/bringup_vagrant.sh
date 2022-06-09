#!/bin/bash
# SPDX-License-Identifier: copyleft-next-0.3.1

set -e

source ${TOPDIR}/.config
source ${TOPDIR}/scripts/lib.sh

# Convert the version string x.y.z to a canonical 5 or 6-digit form.
# Inspired by ld-version.sh on linux. This is the way.
get_canonical_version()
{
	IFS=.
	set -- $1

	# If the 2nd or 3rd field is missing, fill it with a zero.
	#
	# The 4th field, if present, is ignored.
	# This occurs in development snapshots as in 2.35.1.20201116
	echo $((10000 * $1 + 100 * ${2:-0} + ${3:-0}))
}

_vagrant_lacks_parallel()
{
	PARALLEL_MISSING="0.7.0"
	VAGRANT_LIBVIRT_VERSION="$(vagrant plugin list | sed -e 's|(| |g' | sed -e 's|,| |g' | awk '{print $2}')"

	OLD=$(get_canonical_version $PARALLEL_MISSING)
	CURRENT=$(get_canonical_version $VAGRANT_LIBVIRT_VERSION)
	if [[ "$CURRENT" -le "$OLD" ]]; then
		return 1
	fi
	return 0
}

echo 1
# This is just a workaround for fedora since we have an old vagrant-libvirt
# plugin that doesn't work with parallel
ARG=
echo 2
if ! _vagrant_lacks_parallel; then
	ARG='--no-parallel'
fi
cd vagrant
vagrant up $ARG
