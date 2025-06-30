#!/usr/bin/env bash
set -euo pipefail

ENTRY_POINT="main"
COMPILED_PATH="src/main" # ← new relative path

echo "Creating dist directory..."
mkdir -p dist

echo "Installing dependencies..."
yarn install --immutable

echo "Building application..."
yarn run build

echo "Creating Cloud-Function wrapper…"
cat >dist/function.js <<EOF
// Auto-generated wrapper for Google Cloud Functions
const { ${ENTRY_POINT} } = require('./${COMPILED_PATH}');
exports.${ENTRY_POINT} = ${ENTRY_POINT};
EOF

echo "Copying and patching package.json…"
tmp=$(mktemp)
jq '.main = "function.js"' package.json >"$tmp" && mv "$tmp" dist/package.json

echo "Copying yarn.lock..."
cp yarn.lock dist/

echo "Copying .yarnrc.yml..."
cp .yarnrc.yml dist/

echo "Verifying dist contents..."
ls -la dist
