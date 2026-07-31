#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
npm ci
npm run test
npm run build
npm prune --omit=dev
zip -qr kitchen-master-scf.zip dist node_modules package.json package-lock.json scf_bootstrap
npm install
