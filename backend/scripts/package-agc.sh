#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

archive_path="$PWD/kitchen-master-agc.zip"
staging_dir="$(mktemp -d)"
trap 'rm -rf "$staging_dir"' EXIT

npm ci
npm test
npm run build
npm prune --omit=dev

cp huawei-index.js "$staging_dir/index.js"
cp deploy/agc/package.json "$staging_dir/package.json"
cp -R dist "$staging_dir/dist"
cp deploy/agc/dist-package.json "$staging_dir/dist/package.json"
cp -R node_modules "$staging_dir/node_modules"

rm -f "$archive_path"
(
  cd "$staging_dir"
  zip -qr "$archive_path" .
)

npm install

echo "Created $archive_path"
