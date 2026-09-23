#!/usr/bin/env zsh
# Uploads website/ to curator.sstools.co with rsync over SSH, like Batty's deploy-website.sh.
#
#   CURATOR_WEB_HOST=user@host CURATOR_WEB_PATH=/var/www/curator scripts/deploy-website.sh [--dry-run]
#
# Optional: CURATOR_WEB_PORT, CURATOR_WEB_KEY (SSH identity file).
# Files removed locally are removed on the server, except downloads/: past releases' DMGs stay
# there even if this Mac doesn't have them.

set -euo pipefail

REPO_ROOT="${0:A:h:h}"
: "${CURATOR_WEB_HOST:?set CURATOR_WEB_HOST (e.g. user@host)}"
: "${CURATOR_WEB_PATH:?set CURATOR_WEB_PATH (e.g. /var/www/curator)}"

xmllint --noout "$REPO_ROOT/website/appcast.xml" || { print -u2 "error: appcast.xml isn't valid XML"; exit 1; }

ssh_cmd=(ssh)
[[ -n "${CURATOR_WEB_PORT:-}" ]] && ssh_cmd+=(-p "$CURATOR_WEB_PORT")
[[ -n "${CURATOR_WEB_KEY:-}" ]] && ssh_cmd+=(-i "$CURATOR_WEB_KEY")

args=(-avz --delete --filter 'protect downloads/**' --exclude 'src/' --exclude 'README.md' --exclude '.gitkeep' --exclude '.DS_Store')
[[ "${1:-}" == "--dry-run" ]] && args+=(--dry-run)

print "==> Uploading website/ to $CURATOR_WEB_HOST:$CURATOR_WEB_PATH"
rsync "${args[@]}" -e "${ssh_cmd[*]}" "$REPO_ROOT/website/" "$CURATOR_WEB_HOST:$CURATOR_WEB_PATH/"
print "==> Done. Check https://curator.sstools.co/ and https://curator.sstools.co/appcast.xml"
