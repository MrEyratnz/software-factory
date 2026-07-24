// Fixture-driven tests for the no-op guard's decision logic (#228). The review
// of PR #250 showed a string-matching contract test cannot lock this behaviour:
// delete the detection block and the greps still pass. These cases fail if the
// guard ever stops distinguishing a build from a checkpoint-only stall.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  evaluateProgress,
  isLimitStop,
  countWorkCommits,
  prAdvanced,
  ceremonyOutput,
  readJsonOrNull,
  readLines,
  evaluateFromDir,
} from "./session-progress.mjs";

const SHA = "a".repeat(40);
const ok = (o) => evaluateProgress(o).ok;

test("the #228 no-op: orient, checkpoint, stop => FAIL", () => {
  // Exactly what was observed twice in production: a chore checkpoint commit
  // (which the prompt mandates) and nothing else.
  assert.equal(
    ok({
      result: { is_error: false },
      baselineSha: SHA,
      prsBefore: [{ number: 1, headRefOid: "x" }],
      prsAfter: [{ number: 1, headRefOid: "x" }],
      commitSubjects: ["chore(checkpoint): update state"],
    }),
    false,
  );
});

test("a real build (non-chore commit) => PASS", () => {
  assert.equal(
    ok({
      result: {},
      baselineSha: SHA,
      prsBefore: [],
      prsAfter: [],
      commitSubjects: ["chore(checkpoint): update state", "feat: add the thing"],
    }),
    true,
  );
});

test("a PR opened during the session => PASS", () => {
  assert.equal(
    ok({
      result: {},
      baselineSha: SHA,
      prsBefore: [{ number: 1, headRefOid: "x" }],
      prsAfter: [{ number: 1, headRefOid: "x" }, { number: 2, headRefOid: "y" }],
      commitSubjects: ["chore(checkpoint): update state"],
    }),
    true,
  );
});

test("an existing PR advanced (head moved) => PASS", () => {
  assert.equal(
    ok({
      result: {},
      baselineSha: SHA,
      prsBefore: [{ number: 1, headRefOid: "x" }],
      prsAfter: [{ number: 1, headRefOid: "zzz" }],
      commitSubjects: [],
    }),
    true,
  );
});

test("unreadable baseline fails CLOSED, and must not fail OPEN via an empty list (#254)", () => {
  // The bug the review caught: an empty "before" made every open PR look new.
  assert.equal(
    ok({
      result: {},
      baselineSha: SHA,
      prsBefore: null, // could not read
      prsAfter: [{ number: 1, headRefOid: "x" }, { number: 2, headRefOid: "y" }],
      commitSubjects: [],
    }),
    false,
  );
  assert.equal(
    ok({ result: {}, baselineSha: "", prsBefore: [], prsAfter: [], commitSubjects: ["feat: x"] }),
    false,
  );
});

test("a genuinely empty repo baseline is not confused with unreadable", () => {
  // [] before + a PR after is real progress; null before is not provable.
  assert.equal(
    ok({
      result: {},
      baselineSha: SHA,
      prsBefore: [],
      prsAfter: [{ number: 7, headRefOid: "n" }],
      commitSubjects: [],
    }),
    true,
  );
});

test("a usage-limit stop is exempt — never red on a limit (#253)", () => {
  for (const result of [
    { api_error_status: 429 },
    { stop_reason: "max_turns" },
    { terminal_reason: "timeout" },
    { subtype: "error_max_turns" },
    { stop_reason: "Max Turns" }, // normalized: case + separator
  ]) {
    assert.equal(
      ok({ result, baselineSha: SHA, prsBefore: [], prsAfter: [], commitSubjects: ["chore: checkpoint"] }),
      true,
      `expected exemption for ${JSON.stringify(result)}`,
    );
  }
});

test("the limit exemption cannot be forged from model output (#287)", () => {
  // `result.result` is the model's free-form summary and routinely quotes
  // untrusted inbound issue/PR text. A no-op must NOT exempt itself by merely
  // mentioning a limit — this was a live prompt-injection path to false-green.
  for (const text of [
    "the CI job hit a timeout waiting",
    "reviewed issue 'usage limit handling'",
    "monthly spend is discussed in #237",
    "rate limit",
  ]) {
    assert.equal(isLimitStop({ result: text }), false, `must not exempt on: ${text}`);
    assert.equal(
      ok({
        result: { result: text },
        baselineSha: SHA,
        prsBefore: [{ number: 1, headRefOid: "x" }],
        prsAfter: [{ number: 1, headRefOid: "x" }],
        commitSubjects: ["chore(checkpoint): update state"],
      }),
      false,
      `a no-op must stay RED despite: ${text}`,
    );
  }
});

test("ceremony-only sessions are progress, not a stall (#281)", () => {
  // Planning/retro/board sessions produce sprint files, ADRs, or filed issues
  // rather than code; the conductor prompt explicitly permits ending there.
  assert.equal(
    ok({
      result: {},
      baselineSha: SHA,
      prsBefore: [],
      prsAfter: [],
      commitSubjects: ["chore(checkpoint): update state"],
      changedPaths: ["factory-ops/sprints/2/plan.md"],
    }),
    true,
  );
  assert.equal(
    ok({
      result: {},
      baselineSha: SHA,
      prsBefore: [],
      prsAfter: [],
      commitSubjects: ["chore(checkpoint): update state"],
      changedPaths: ["docs/adr/0004-board-session.md"],
    }),
    true,
  );
  // A retro that only files issues still counts.
  assert.equal(
    ok({
      result: {},
      baselineSha: SHA,
      prsBefore: [],
      prsAfter: [],
      commitSubjects: ["chore(checkpoint): update state"],
      issuesFiled: 3,
    }),
    true,
  );
  // But an unrelated touched file is NOT ceremony output.
  assert.equal(ceremonyOutput(["README.md", "src/x.ts"]), false);
  assert.equal(ceremonyOutput(undefined), false);
});

test("a normal completion is NOT treated as a limit stop", () => {
  assert.equal(isLimitStop({ stop_reason: "end_turn", subtype: "success" }), false);
  assert.equal(isLimitStop({}), false);
  assert.equal(isLimitStop(null), false);
});

test("countWorkCommits excludes chore/ci with any scope, counts the rest", () => {
  assert.equal(
    countWorkCommits([
      "chore: bump",
      "chore(checkpoint): state",
      "ci: pin action",
      "feat: a",
      "fix(scope): b",
      "docs: c",
      "   ",
    ]),
    3, // feat, fix, docs — and not the blank/chore/ci ones
  );
  // Matching is case-sensitive, like the workflow's grep and the Conventional
  // Commits spec: a non-canonical "CI(deps):" is counted as work, not skipped.
  assert.equal(countWorkCommits(["CI(deps): x"]), 1);
  assert.equal(countWorkCommits([]), 0);
  assert.equal(countWorkCommits(undefined), 0);
});

test("prAdvanced is false when nothing changed", () => {
  const same = [{ number: 1, headRefOid: "x" }];
  assert.equal(prAdvanced(same, same), false);
  assert.equal(prAdvanced([], []), false);
});

// --- evidence readers: the fail-closed parse must be covered here, not left
// in workflow glue where a `catch { return [] }` "simplification" defeats it.
test("readJsonOrNull returns null (not []) for missing/corrupt files (#254/#285)", () => {
  const fs = { readFileSync: () => { throw new Error("ENOENT"); } };
  assert.equal(readJsonOrNull("/nope.json", fs), null);
  const bad = { readFileSync: () => "{not json" };
  assert.equal(readJsonOrNull("/bad.json", bad), null);
  const good = { readFileSync: () => '[{"number":1,"headRefOid":"x"}]' };
  assert.deepEqual(readJsonOrNull("/ok.json", good), [{ number: 1, headRefOid: "x" }]);
});

test("readLines trims and drops blanks; missing file => []", () => {
  const fs = { readFileSync: () => "feat: a\n\n  chore: b  \n" };
  assert.deepEqual(readLines("/x", fs), ["feat: a", "chore: b"]);
  const missing = { readFileSync: () => { throw new Error("ENOENT"); } };
  assert.deepEqual(readLines("/x", missing), []);
});

test("evaluateFromDir wires the evidence files and fails closed on an unreadable baseline", () => {
  const files = {
    "/e/session-result.json": '{"is_error":false}',
    "/e/prs-before.json": '[{"number":1,"headRefOid":"x"}]',
    "/e/prs-after.json": '[{"number":1,"headRefOid":"x"}]',
    "/e/work-subjects.txt": "chore(checkpoint): update state\n",
    "/e/changed-paths.txt": "",
  };
  const fs = { readFileSync: (p) => { if (!(p in files)) throw new Error("ENOENT"); return files[p]; } };
  // the observed no-op: chore-only, no PR movement, no ceremony => FAIL
  assert.equal(evaluateFromDir("/e", { BASE_SHA: SHA }, fs).ok, false);
  // a real build => PASS
  files["/e/work-subjects.txt"] = "feat: implement the thing\n";
  assert.equal(evaluateFromDir("/e", { BASE_SHA: SHA }, fs).ok, true);
  // unreadable PR baseline => fail CLOSED even with a PR present after
  delete files["/e/prs-before.json"];
  files["/e/work-subjects.txt"] = "chore: checkpoint\n";
  files["/e/prs-after.json"] = '[{"number":9,"headRefOid":"n"}]';
  assert.equal(evaluateFromDir("/e", { BASE_SHA: SHA }, fs).ok, false);
});
