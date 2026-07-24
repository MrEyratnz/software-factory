#!/usr/bin/env node
// session-progress.mjs — the no-op / false-green guard's decision logic (#228),
// extracted from claude-session.yml so it is exercised by fixtures rather than
// pinned by grepping the workflow for strings (#256): a review found that
// deleting the detection block left every string-matching assertion green.
//
// A `require_progress` station (factory-run) must end an iteration having built
// something. "Something" is deliberately NOT "a commit": the conductor is
// required to commit a `chore:` checkpoint on EVERY run, so counting commits
// would let orient -> checkpoint -> stop pass green (#251). Progress is:
//   * a non-chore/ci work commit authored this session (scoped to the baseline
//     tip, so a concurrent fetch into refs/remotes cannot satisfy it, #252), or
//   * a pull request opened or advanced (head oid moved) during the session.
//
// Two paths must never be judged as stalls:
//   * a usage-limit / timeout stop — checkpoint-and-resume is the sanctioned
//     protocol and "never exit red on a limit" is a standing law (#253);
//   * a missing/unreadable baseline — that cannot prove progress, so it fails
//     CLOSED rather than passing by default (#254). An empty-list fallback
//     would fail OPEN: with no "before" set every already-open PR reads as
//     newly advanced.

/** True when the session stopped on a usage limit or timeout (exempt path). */
export function isLimitStop(result) {
  if (!result || typeof result !== "object") return false;
  if (result.api_error_status === 429) return true;
  const hay = [result.result, result.subtype, result.stop_reason, result.terminal_reason]
    .filter((v) => typeof v === "string")
    .join(" ")
    .toLowerCase();
  return /usage limit|session limit|rate limit|monthly spend|max_turns|maximum turns|timeout/.test(hay);
}

/** Commit subjects that count as work — `chore:`/`ci:` (any scope) do not. */
export function countWorkCommits(subjects) {
  if (!Array.isArray(subjects)) return 0;
  // Case-sensitive, matching the workflow's grep and the Conventional Commits
  // spec (types are lowercase); an odd-cased "CI(deps):" is not a sanctioned
  // type, so treating it as work is the conservative reading.
  return subjects.filter((s) => typeof s === "string" && s.trim() && !/^(chore|ci)(\([^)]*\))?:/.test(s.trim())).length;
}

/** True when any PR was opened, or an existing PR's head moved. */
export function prAdvanced(before, after) {
  if (!Array.isArray(before) || !Array.isArray(after)) return false;
  const seen = new Map(before.map((p) => [p.number, p.headRefOid]));
  return after.some((p) => !seen.has(p.number) || seen.get(p.number) !== p.headRefOid);
}

/**
 * The guard's verdict.
 * @returns {{ok: boolean, reason: string}} ok=false means fail the job.
 */
export function evaluateProgress({ result, baselineSha, prsBefore, prsAfter, commitSubjects }) {
  if (isLimitStop(result)) {
    return { ok: true, reason: "limit-stop: usage limit/timeout — checkpoint-and-resume is sanctioned (#253)" };
  }
  // `null`/`undefined` means "could not read" — distinct from a genuine [].
  if (!baselineSha || !Array.isArray(prsBefore)) {
    return { ok: false, reason: "baseline missing or unreadable — failing closed (#254)" };
  }
  const work = countWorkCommits(commitSubjects);
  const pr = prAdvanced(prsBefore, Array.isArray(prsAfter) ? prsAfter : []);
  if (work === 0 && !pr) {
    return { ok: false, reason: "no PR opened/advanced and no non-chore work commit — a no-op (#228)" };
  }
  return { ok: true, reason: `progress: work commits=${work}, PR opened/advanced=${pr ? 1 : 0}` };
}
