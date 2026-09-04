#!/usr/bin/env bash
set -euo pipefail

NAME="$1"
URL="$2"
LAST_CHECK="$3"

RELEASE="$(curl -fsSL "$URL")"
LATEST="$(jq -r '.tag_name | gsub("^v"; "")' <<<"$RELEASE")"
PUBLISHED="$(jq -r '.published_at' <<<"$RELEASE")"

echo "latest-version=$LATEST" >> "$GITHUB_OUTPUT"
echo "published-at=$PUBLISHED" >> "$GITHUB_OUTPUT"

if [[ "$PUBLISHED" > "$LAST_CHECK" ]]; then
  echo "needs-update=true" >> "$GITHUB_OUTPUT"
else
  echo "needs-update=false" >> "$GITHUB_OUTPUT"
  echo "$NAME $LATEST is older than last check"
fi
echo "$NAME $LATEST (published: $PUBLISHED)"
