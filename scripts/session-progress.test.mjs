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
    { result: "You've hit your session limit · resets 5:20am (UTC)" },
    { result: "monthly spend limit reached" },
    { stop_reason: "max_turns" },
    { terminal_reason: "timeout" },
  ]) {
    assert.equal(
      ok({ result, baselineSha: SHA, prsBefore: [], prsAfter: [], commitSubjects: ["chore: checkpoint"] }),
      true,
      `expected exemption for ${JSON.stringify(result)}`,
    );
  }
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
