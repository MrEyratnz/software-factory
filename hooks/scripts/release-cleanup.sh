#!/usr/bin/env bash
# release-cleanup (Stop) — give the release-state files a lifecycle (issue #14).
# release-intent.json and release-proof.json had no cleanup: once a release was
# attempted the intent flag lingered for the rest of the session, leaving
# guard-mcp-commit stepped-aside and guard-release in the "release in progress"
# regime indefinitely, and a stale proof sat on disk.
#
# A /ship runs to completion within a turn, so at Stop (turn/session end) any
# release is finished: clear both files. A subsequent /ship re-establishes them
# via its sanctioned producers (the release-captain writes intent;
# record-release-proof mints the proof on a green build). Advisory: exit 0.
. "$(dirname "$0")/../lib/common.sh"

removed=0
for f in release-intent.json release-proof.json; do
  if [ -f "$STATE_DIR/$f" ]; then rm -f "$STATE_DIR/$f" 2>/dev/null && removed=$((removed+1)); fi
done
[ "$removed" -gt 0 ] && otel_emit factory_release_cleanup_total sum "$removed" '{}'
exit 0
