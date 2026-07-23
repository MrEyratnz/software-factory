#!/usr/bin/env node
// pr-review-state — reduce `gh pr view --json reviews` to the PR's CURRENT
// review verdict: APPROVED | CHANGES_REQUESTED | NONE.
//
// Why this exists as a script rather than a jq one-liner inside the workflow:
// the merge gate decides whether an unreviewed change can reach main, and the
// first version of it got this wrong in a way no CI job could have caught. It
// substring-matched the PR's FULL review history, so a single CHANGES_REQUESTED
// from an early push kept matching forever — after the reviewer approved a later
// push the list read "CHANGES_REQUESTED,APPROVED" and the PR could never
// auto-merge again. Logic that guards main belongs somewhere it can be unit
// tested (the same reason scripts/triage-*.sh exist).
//
// The rule mirrors GitHub's own model:
//   * only APPROVED and CHANGES_REQUESTED carry a verdict; COMMENTED and
//     DISMISSED do not, and a later COMMENTED does not dismiss an approval;
//   * each reviewer's LATEST verdict is the one that counts, by submittedAt;
//   * any outstanding CHANGES_REQUESTED blocks, whoever else approved.
//
// Fails closed: anything it cannot parse is NONE (no merge), never APPROVED.
//
// Usage: gh pr view N --json reviews | node scripts/pr-review-state.mjs

const VERDICTS = new Set(['APPROVED', 'CHANGES_REQUESTED']);

// reviewState(reviews) — the PR's current verdict from its review list.
export function reviewState(reviews) {
  if (!Array.isArray(reviews)) return 'NONE';

  // Latest verdict per reviewer. Reviews without a recognizable verdict are
  // ignored rather than overwriting one (GitHub semantics: a comment does not
  // dismiss an approval); a DISMISSED review clears that reviewer's verdict.
  const latest = new Map();
  const ordered = [...reviews]
    .filter((r) => r && typeof r === 'object')
    .sort((a, b) => String(a.submittedAt ?? '').localeCompare(String(b.submittedAt ?? '')));

  for (const r of ordered) {
    const who = r.author?.login ?? '<unknown>';
    if (VERDICTS.has(r.state)) latest.set(who, r.state);
    else if (r.state === 'DISMISSED') latest.delete(who);
  }

  const states = [...latest.values()];
  if (states.includes('CHANGES_REQUESTED')) return 'CHANGES_REQUESTED';
  if (states.includes('APPROVED')) return 'APPROVED';
  return 'NONE';
}

// CLI: read `gh pr view --json reviews` output on stdin, print the verdict.
if (process.argv[1] && import.meta.url.endsWith(process.argv[1].split('/').pop())) {
  let raw = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { raw += c; });
  process.stdin.on('end', () => {
    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch {
      process.stdout.write('NONE\n');
      return;
    }
    process.stdout.write(`${reviewState(parsed?.reviews ?? parsed)}\n`);
  });
}
