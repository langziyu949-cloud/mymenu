#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

archive_path="$PWD/kitchen-master-agc.zip"
staging_dir="$(mktemp -d)"
trap 'rm -rf "$staging_dir"' EXIT

npm ci
npm test

cp deploy/agc/package.json "$staging_dir/package.json"
./node_modules/.bin/esbuild src/huaweiHandler.ts \
  --bundle \
  --minify \
  --platform=node \
  --format=cjs \
  --target=node20 \
  --outfile="$staging_dir/index.js"

rm -f "$archive_path"
(
  cd "$staging_dir"
  zip -qr "$archive_path" .
)

echo "Created $archive_path"
