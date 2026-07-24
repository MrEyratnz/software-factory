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

// Structured fields only — NEVER `result.result`. That field is the model's
// free-form final message, which per CLAUDE.md routinely quotes untrusted issue
// and PR text; substring-matching it let any no-op whose summary happened to
// contain "timeout" (or an inbound issue titled "usage limit …") exempt itself
// and pass green, re-opening the very hole this guard closes (#287).
const LIMIT_STOP_VALUES = new Set([
  "max_turns",
  "max_tokens",
  "timeout",
  "usage_limit",
  "session_limit",
  "rate_limit",
  "error_max_turns",
]);

/** True when the session stopped on a usage limit or timeout (exempt path). */
export function isLimitStop(result) {
  if (!result || typeof result !== "object") return false;
  if (result.api_error_status === 429) return true;
  // Exact matches against an allow-list of machine-set fields, case- and
  // separator-normalized ("max turns"/"maxTurns" -> "max_turns").
  return [result.subtype, result.stop_reason, result.terminal_reason].some((v) => {
    if (typeof v !== "string") return false;
    const norm = v.trim().toLowerCase().replace(/[\s-]+/g, "_");
    return LIMIT_STOP_VALUES.has(norm);
  });
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

// A sprint-boundary session legitimately produces ceremony artifacts rather
// than code: planning/retro write factory-ops/sprints/**, a retro files issues,
// a board session lands docs/adr/**. The conductor prompt explicitly allows
// ending there ("unless step 1 or 2 genuinely consumed the whole session"), so
// counting only code would red a compliant run and wedge the hourly cron on a
// permanent red (#281). These paths are ceremony OUTPUT, not the checkpoint.
const CEREMONY_PATH = /^(factory-ops\/sprints\/|docs\/adr\/)/;

/** True when the session produced ceremony artifacts (sprint files, ADRs). */
export function ceremonyOutput(changedPaths) {
  if (!Array.isArray(changedPaths)) return false;
  return changedPaths.some((p) => typeof p === "string" && CEREMONY_PATH.test(p.trim()));
}

/**
 * The guard's verdict.
 * @returns {{ok: boolean, reason: string}} ok=false means fail the job.
 */
export function evaluateProgress({
  result,
  baselineSha,
  prsBefore,
  prsAfter,
  commitSubjects,
  changedPaths,
  issuesFiled,
}) {
  if (isLimitStop(result)) {
    return { ok: true, reason: "limit-stop: usage limit/timeout — checkpoint-and-resume is sanctioned (#253)" };
  }
  // `null`/`undefined` means "could not read" — distinct from a genuine [].
  if (!baselineSha || !Array.isArray(prsBefore)) {
    return { ok: false, reason: "baseline missing or unreadable — failing closed (#254)" };
  }
  const work = countWorkCommits(commitSubjects);
  const pr = prAdvanced(prsBefore, Array.isArray(prsAfter) ? prsAfter : []);
  const ceremony = ceremonyOutput(changedPaths);
  const filed = Number.isInteger(issuesFiled) && issuesFiled > 0;
  if (!work && !pr && !ceremony && !filed) {
    return {
      ok: false,
      reason: "no PR opened/advanced, no work commit, no ceremony artifact, no issue filed — a no-op (#228)",
    };
  }
  return {
    ok: true,
    reason:
      `progress: work commits=${work}, PR opened/advanced=${pr ? 1 : 0}, ` +
      `ceremony artifacts=${ceremony ? 1 : 0}, issues filed=${filed ? issuesFiled : 0}`,
  };
}

// --- evidence readers (kept HERE, not in workflow glue) ----------------------
// The null-vs-[] distinction is what makes the guard fail CLOSED (#254): a
// parse failure must read as "could not prove", never as "nothing was there".
// Living in the module means the fixtures cover it; in inline `node -e` glue a
// plausible `catch { return [] }` simplification would silently defeat it
// (#285).

/** Parse JSON from a file; `null` when absent or unparseable (NOT `[]`). */
export function readJsonOrNull(path, fs) {
  try {
    return JSON.parse(fs.readFileSync(path, "utf8"));
  } catch {
    return null;
  }
}

/** Read a newline-delimited file into trimmed non-empty lines. */
export function readLines(path, fs) {
  try {
    return fs.readFileSync(path, "utf8").split("\n").map((l) => l.trim()).filter(Boolean);
  } catch {
    return [];
  }
}

/** Build the guard input from a temp dir of evidence files, then evaluate. */
export function evaluateFromDir(dir, env, fs) {
  const issues = Number.parseInt(env?.ISSUES_FILED ?? "", 10);
  return evaluateProgress({
    result: readJsonOrNull(`${dir}/session-result.json`, fs) ?? {},
    baselineSha: env?.BASE_SHA || "",
    prsBefore: readJsonOrNull(`${dir}/prs-before.json`, fs),
    prsAfter: readJsonOrNull(`${dir}/prs-after.json`, fs),
    commitSubjects: readLines(`${dir}/work-subjects.txt`, fs),
    changedPaths: readLines(`${dir}/changed-paths.txt`, fs),
    issuesFiled: Number.isNaN(issues) ? 0 : issues,
  });
}

// CLI: `node session-progress.mjs <evidence-dir>` — prints the verdict and
// exits non-zero when the station built nothing, so the workflow step is a
// one-liner and every decision path stays inside the fixture-tested module.
if (process.argv[1] && import.meta.url.endsWith(process.argv[1].split("/").pop())) {
  const fs = await import("node:fs");
  const verdict = evaluateFromDir(process.argv[2] || ".", process.env, fs.default ?? fs);
  if (!verdict.ok) {
    console.log(
      `::error::factory-run built nothing this iteration — ${verdict.reason}. ` +
        "Orienting with /factory-status and writing only the checkpoint is a no-op, not progress.",
    );
    process.exitCode = 1;
  } else {
    console.log(`no-op guard: ${verdict.reason}`);
  }
}
