#!/usr/bin/env bash
set -euo pipefail

tag=$1
plugin=$2
name=${plugin##*/}
if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ || "$name" != "ListenBrainzLove-${tag#v}.zip" ]]; then
  echo "Installer filename must match the release tag." >&2
  exit 1
fi

ref="refs/tags/dist-$tag"
if git ls-remote --exit-code origin "$ref" >/dev/null; then
  exit 0
else
  status=$?
  if [[ "$status" != 2 ]]; then
    exit "$status"
  fi
fi

# Build a standalone commit with just the installer and leave the checkout alone.
blob=$(git hash-object -w -- "$plugin")
dist=$(printf '100644 blob %s\t%s\n' "$blob" "$name" | git mktree)
tree=$(printf '040000 tree %s\tdist\n' "$dist" | git mktree)
commit=$(git commit-tree "$tree" -m "Distribute ListenBrainzLove $tag")
git push origin "$commit:$ref"
