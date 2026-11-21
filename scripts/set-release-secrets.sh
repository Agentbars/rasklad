#!/bin/zsh
# Uploads the release signing identity and the Sparkle EdDSA key to the repo's GitHub Secrets.
#   scripts/set-release-secrets.sh [dir]   (default: ~/.rasklad-release)
# The dir holds release.p12 + pass.txt ("Rasklad Release Signing" certificate) and
# ed_private.txt (exported with: generate_keys --account rasklad -x ed_private.txt).
# Keep that dir backed up: losing the certificate resets macOS permissions for every user
# on the next update, losing the EdDSA key means a key rotation (see docs/releasing.md).
set -euo pipefail
DIR=${1:-$HOME/.rasklad-release}
REPO=Agentbars/rasklad
export GH_TOKEN=${GH_TOKEN:-$(gh auth token --user Agentbars)}
base64 -i "$DIR/release.p12" | tr -d '\n' | gh secret set RELEASE_SIGNING_P12_BASE64 -R $REPO
tr -d '\n' < "$DIR/pass.txt" | gh secret set RELEASE_SIGNING_P12_PASSWORD -R $REPO
tr -d '\n' < "$DIR/ed_private.txt" | gh secret set SPARKLE_ED_PRIVATE_KEY -R $REPO
gh secret list -R $REPO
