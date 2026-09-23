#!/bin/zsh
# run-ui-tests-vm.sh — run Curator's UI tests inside a disposable Tart VM on cameron.
#
# UI tests never run on a host Mac: XCUITest loads XCTAutomationSupport into every running GUI
# app, and on cameron that once crashed Batty and every terminal session in it. The
# CuratorUITests target refuses to build outside a VM, and this script is the only way to run
# it. See docs/ui-testing-vm.md.
#
# Per run:
#   1. Preflight: Tart and the golden image present, no other VM running, disk free, memory
#      requested through the memory-signal protocol if the host is short, stale
#      `curator-uitest-<run-id>` clones swept.
#   2. Export a clean snapshot (`git archive HEAD`, never the live working copy) plus
#      `uitest.env`: the Plex URL (host name resolved to an IP for the guest), token and TMDB
#      key from the repo's .env, as TEST_RUNNER_* variables. Omit them with --offline.
#   3. Clone the golden image, boot headless with the export mounted read-only.
#   4. In the guest: copy the source in and run `xcodebuild -scheme 'Curator UI Tests' test`,
#      ad hoc signed (the guest has no certificates).
#   5. Stream results back to build/ui-tests/<run-id>/.
#   6. Cleanup on EXIT: stop and delete the clone, remove the export (it holds the token).
#
# Usage: scripts/run-ui-tests-vm.sh [--offline]
# Run it in the foreground of a shell: a dropped session costs a clone, not a work session.

set -euo pipefail

GOLDEN="curator-uitest-golden"
PREFIX="curator-uitest"
REPO="${0:A:h:h}"
GUEST_USER="admin"
GUEST_SRC="/Users/$GUEST_USER/src"
GUEST_RESULTS="/Users/$GUEST_USER/results"
RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
CLONE="$PREFIX-$RUN_ID"
EXPORT="$(mktemp -d "${TMPDIR:-/tmp}/$PREFIX-export.XXXXXX")"
RESULTS_DIR="$REPO/build/ui-tests/$RUN_ID"
BOOT_TIMEOUT_SECS=120
# Keep in sync with the golden image's memory (`tart set --memory`).
GUEST_MEM_MB=12288

OFFLINE=0
[[ "${1:-}" == "--offline" ]] && OFFLINE=1

log()  { print -r -- "==> $*"; }
fail() { print -r -- "!! $*" >&2; exit 1; }

cleanup() {
  local rc=$?
  trap - EXIT
  log "Cleaning up (exit $rc)"
  if [[ -n "${MEMORY_REQUEST_ID:-}" && -n "${MEMORY_COORD_DIR:-}" ]]; then
    mkdir -p "$MEMORY_COORD_DIR/release" 2>/dev/null || true
    print -r -- "{\"id\": \"$MEMORY_REQUEST_ID\", \"released\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
      > "$MEMORY_COORD_DIR/release/$MEMORY_REQUEST_ID.json" 2>/dev/null || true
  fi
  tart stop "$CLONE" >/dev/null 2>&1 || true
  tart delete "$CLONE" >/dev/null 2>&1 || true
  rm -rf "$EXPORT"
}
trap cleanup EXIT

# --- Preflight ---------------------------------------------------------------

command -v tart >/dev/null || fail "Tart is not installed (brew install cirruslabs/cli/tart)"
tart list | awk '{ print $2 }' | grep -qx "$GOLDEN" || fail "Golden image '$GOLDEN' not found (see docs/ui-testing-vm.md)"

# Apple allows two macOS guests at once, and every project on cameron shares that and the RAM.
running=$(tart list | awk '$NF == "running" { print $2 }')
[[ -z "$running" ]] || fail "Another VM is running ($running). Wait for it to finish."

free_kb=$(df -k / | awk 'NR == 2 { print $4 }')
(( free_kb / 1024 / 1024 >= 20 )) || fail "Only $((free_kb / 1024 / 1024)) GiB free on / — need at least 20 GiB"

# --- Memory (memory-signal protocol, as in Changeover's run-ui-tests-vm.sh) ----

memory_available_bytes() {
  local page free inactive purgeable
  page=$(sysctl -n vm.pagesize)
  free=$(vm_stat | awk '/Pages free/ {gsub("\\.","",$3); print $3}')
  inactive=$(vm_stat | awk '/Pages inactive/ {gsub("\\.","",$3); print $3}')
  purgeable=$(vm_stat | awk '/Pages purgeable/ {gsub("\\.","",$3); print $3}')
  print -r -- $(( (free + inactive + purgeable) * page ))
}

memory_request_and_wait() {
  local need_bytes=$1 dir hb id deadline
  dir="${MEMORY_COORDINATION_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/memory-coordination}"
  hb="$dir/heartbeat"
  [[ -f "$hb" ]] && (( $(date +%s) - $(stat -f %m "$hb") <= 15 )) || return 4
  id="run-ui-tests-vm-curator-$$-$(date +%s)"
  MEMORY_REQUEST_ID="$id"
  MEMORY_COORD_DIR="$dir"
  mkdir -p "$dir/requests" "$dir/ready" "$dir/failed" "$dir/release"
  print -r -- "{\"id\": \"$id\", \"resource\": \"memory\", \"bytes\": $need_bytes, \"requester\": \"run-ui-tests-vm\", \"reason\": \"Curator UI-test VM needs guest RAM plus build headroom\", \"pid\": $$, \"created\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
    > "$dir/requests/$id.json"
  deadline=$(( SECONDS + 120 ))
  while (( SECONDS < deadline )); do
    [[ -f "$dir/ready/$id.json" ]] && return 0
    [[ -f "$dir/failed/$id.json" ]] && return 3
    sleep 2
  done
  return 4
}

need_bytes=$(( (GUEST_MEM_MB + 4096) * 1024 * 1024 ))
if (( $(memory_available_bytes) < need_bytes )); then
  log "Host memory short — requesting $(( need_bytes / 1073741824 )) GiB through the memory-signal protocol"
  set +e; memory_request_and_wait "$need_bytes"; mem_rc=$?; set -e
  (( mem_rc == 0 )) || fail "Memory request not fulfilled (rc=$mem_rc). Free memory (e.g. unload LM Studio models) and retry."
  (( $(memory_available_bytes) >= need_bytes )) || fail "Observer signaled ready but memory is still short"
fi

# A SIGKILL skips the trap, so sweep clones left by earlier runs. Only this script's own
# run-id shape is matched, which can never be the golden image.
for old in $(tart list | awk -v p="^$PREFIX-[0-9]{8}-[0-9]{6}-[0-9]+\$" '$2 ~ p { print $2 }'); do
  [[ "$old" == "$GOLDEN" || "$old" == "$CLONE" ]] && continue
  log "Sweeping stale clone: $old"
  tart stop "$old" >/dev/null 2>&1 || true
  tart delete "$old" >/dev/null 2>&1 || true
done

# --- Export a clean snapshot -------------------------------------------------

mkdir -p "$EXPORT/src"
log "Exporting HEAD to $EXPORT/src"
git -C "$REPO" archive HEAD | tar -x -C "$EXPORT/src"

env_value() { sed -n "s/^$1=//p" "$REPO/.env" 2>/dev/null | tail -1 | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//"; }

: > "$EXPORT/uitest.env"
if (( OFFLINE )); then
  log "Offline run: no Plex values are passed; live tests will skip"
elif [[ -f "$REPO/.env" ]]; then
  plex_url="$(env_value PLEX_URL)"
  # The guest can't resolve names like "joe"; hand it the IP the host resolves.
  if [[ -n "$plex_url" ]]; then
    host="$(print -r -- "$plex_url" | sed -E 's#^[a-z]+://##; s#[:/].*$##')"
    if [[ ! "$host" =~ '^[0-9.]+$' ]]; then
      ip="$(dscacheutil -q host -a name "$host" | awk '/^ip_address/ { print $2; exit }')"
      [[ -n "$ip" ]] || fail "Couldn't resolve $host for the guest"
      plex_url="${plex_url/$host/$ip}"
      log "Plex server $host → $ip for the guest"
    fi
  fi
  {
    print -r -- "export TEST_RUNNER_CURATOR_PLEX_URL=${(q)plex_url}"
    print -r -- "export TEST_RUNNER_CURATOR_PLEX_TOKEN=${(q)$(env_value PLEX_TOKEN)}"
    print -r -- "export TEST_RUNNER_CURATOR_TMDB_API_KEY=${(q)$(env_value TMDB_API_KEY)}"
  } > "$EXPORT/uitest.env"
else
  log "No .env in the repo: live tests will skip"
fi

# --- Clone and boot ----------------------------------------------------------

log "Cloning $GOLDEN → $CLONE"
tart clone "$GOLDEN" "$CLONE"

log "Booting $CLONE (headless, export mounted read-only)"
tart run "$CLONE" --no-graphics --dir=run:"$EXPORT":ro >"$EXPORT/tart-run.log" 2>&1 &
boot_deadline=$(( SECONDS + BOOT_TIMEOUT_SECS ))
until tart exec "$CLONE" true >/dev/null 2>&1; do
  (( SECONDS < boot_deadline )) || fail "Guest did not become reachable within ${BOOT_TIMEOUT_SECS}s"
  sleep 5
done
log "Guest reachable after $SECONDS s"

# --- In the guest ------------------------------------------------------------

tart exec "$CLONE" /bin/zsh -lc "rm -rf $GUEST_SRC $GUEST_RESULTS && mkdir -p $GUEST_RESULTS"
log "Copying source into the guest"
tart exec "$CLONE" /bin/zsh -lc "cp -R '/Volumes/My Shared Files/run/src' $GUEST_SRC"

log "Running UI tests in the guest"
set +e
tart exec "$CLONE" /bin/zsh -lc "
  source '/Volumes/My Shared Files/run/uitest.env'
  cd $GUEST_SRC && xcodebuild -project Curator.xcodeproj -scheme 'Curator UI Tests' \
    -destination 'platform=macOS' -resultBundlePath $GUEST_RESULTS/UITests.xcresult \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    test 2>&1 | tee $GUEST_RESULTS/xcodebuild.log
  exit \${pipestatus[1]}"
test_rc=$?
set -e

# --- Results back ------------------------------------------------------------

mkdir -p "$RESULTS_DIR"
log "Pulling results into $RESULTS_DIR"
tart exec "$CLONE" /bin/zsh -lc "tar -C $GUEST_RESULTS -cf - ." | tar -x -C "$RESULTS_DIR"

print ""
if (( test_rc == 0 )); then
  log "RESULT: TEST SUCCEEDED"
else
  log "RESULT: TEST FAILED (exit $test_rc)"
fi
grep -E "Test case .* (passed|failed|skipped)|Executed|TEST (SUCCEEDED|FAILED)" "$RESULTS_DIR/xcodebuild.log" | tail -15 || true
print ""
log "Result bundle: $RESULTS_DIR/UITests.xcresult"
log "Full log:      $RESULTS_DIR/xcodebuild.log"

exit "$test_rc"
