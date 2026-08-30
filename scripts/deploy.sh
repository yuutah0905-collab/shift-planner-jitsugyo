#!/bin/bash
# ============================================================================
# One-shot build + cache-bust + deploy script for Cloudflare Pages.
#
# WHY THIS EXISTS:
# On 2026-08-30 a deploy shipped with the '__BUILD_TS__' placeholder
# un-injected (the separate inject_build_ts.sh step was forgotten), which
# silently disabled the app's auto-update cache-busting logic - users kept
# seeing old cached builds after an update. This script exists so that
# "build -> inject timestamp -> deploy" can NEVER again be done as separate,
# forgettable manual steps: running this ONE script always does all three,
# in the correct order, every time.
#
# USAGE:
#   bash scripts/deploy.sh
#
# Requires CLOUDFLARE_API_TOKEN to be set in the environment before running,
# e.g.:
#   export CLOUDFLARE_API_TOKEN="cfut_..."
#   bash scripts/deploy.sh
# ============================================================================
set -e
cd "$(dirname "$0")/.."

PROJECT_NAME="shift-planner-jitsugyo"

if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
  echo "❌ CLOUDFLARE_API_TOKEN is not set. Export it first, e.g.:"
  echo "   export CLOUDFLARE_API_TOKEN=\"cfut_...\""
  exit 1
fi

echo "1/3 🏗  Building Flutter web (release)..."
flutter build web --release \
  --dart-define=flutter.inspector.structuredErrors=false \
  --dart-define=debugShowCheckedModeBanner=false

echo "2/3 🕒 Injecting build timestamp for cache-busting..."
bash scripts/inject_build_ts.sh

# Safety net: fail loudly instead of silently shipping a broken cache-buster
# if the placeholder somehow didn't get replaced.
if grep -q "__BUILD_TS__" build/web/index.html; then
  echo "❌ __BUILD_TS__ placeholder was NOT replaced! Aborting deploy."
  exit 1
fi

echo "3/3 🚀 Deploying to Cloudflare Pages ($PROJECT_NAME)..."
npx wrangler pages deploy build/web --project-name="$PROJECT_NAME" --branch=main --commit-dirty=true

echo "✅ Deploy complete."
