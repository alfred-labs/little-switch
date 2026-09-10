#!/bin/sh
set -eu

script_root=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=tools/release/common.sh
. "$script_root/common.sh"
release_initialize "$script_root/../.."

release_tools bump "$@"
