#!/bin/bash
# Injects a unique build timestamp into build/web/index.html so the
# cache-busting logic embedded there (see web/index.html) can correctly
# detect "this is a NEW deploy" and clear old service-worker caches.
#
# WITHOUT this step, the placeholder '__BUILD_TS__' is shipped literally
# on every deploy, so the browser always sees "same build as last time"
# and never clears its old cached main.dart.js / flutter_service_worker.js
# - meaning users only get the update after manually clearing site data
# or force-closing the app many times.
#
# Usage: run this AFTER `flutter build web --release` and BEFORE deploying
# (e.g. `bash scripts/inject_build_ts.sh && npx wrangler pages deploy build/web ...`)
set -e
cd "$(dirname "$0")/.."
BUILD_TS=$(date +%s)
sed -i "s/__BUILD_TS__/${BUILD_TS}/g" build/web/index.html
echo "Injected build timestamp: ${BUILD_TS}"
