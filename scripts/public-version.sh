#!/bin/zsh
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
    print -u2 "Usage: public-version.sh <major.minor.patch>"
    exit 64
fi

RAW_VERSION="${1#v}"
if [[ ! "${RAW_VERSION}" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    print -u2 "Version must contain exactly three numeric segments: major.minor.patch"
    exit 65
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "${RAW_VERSION}"
MAJOR_VALUE=$((10#${MAJOR}))
MINOR_VALUE=$((10#${MINOR}))
PATCH_VALUE=$((10#${PATCH}))

for VALUE in "${MAJOR_VALUE}" "${MINOR_VALUE}" "${PATCH_VALUE}"; do
    if (( VALUE > 999 )); then
        print -u2 "Each public version segment must be between 000 and 999."
        exit 66
    fi
done

printf 'v%03d.%03d.%03d\n' \
    "${MAJOR_VALUE}" \
    "${MINOR_VALUE}" \
    "${PATCH_VALUE}"
