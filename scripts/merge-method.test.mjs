// Tests for scripts/merge-method.mjs — picking a merge method the repository
// actually allows. Run: node --test scripts/merge-method.test.mjs
//
// The bug this pins (#98): on-pr.yml hardcoded `--merge`, which this repository
// forbids (squash only), so `gh pr merge` failed with "Merge commits are not
// allowed on this repository". It was latent — the job exits early when no
// review approves, so it reported success without ever reaching the merge call,
// and would only have surfaced once the loop was otherwise working.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mergeMethod } from './merge-method.mjs';

test('picks the only method a repository allows', () => {
  assert.equal(mergeMethod({ allow_squash_merge: true, allow_merge_commit: false, allow_rebase_merge: false }), 'squash');
  assert.equal(mergeMethod({ allow_squash_merge: false, allow_merge_commit: true, allow_rebase_merge: false }), 'merge');
  assert.equal(mergeMethod({ allow_squash_merge: false, allow_merge_commit: false, allow_rebase_merge: true }), 'rebase');
});

test('prefers squash when several are allowed — many small PRs, linear main', () => {
  assert.equal(mergeMethod({ allow_squash_merge: true, allow_merge_commit: true, allow_rebase_merge: true }), 'squash');
});

test('falls to the next allowed method in preference order', () => {
  assert.equal(mergeMethod({ allow_squash_merge: false, allow_merge_commit: true, allow_rebase_merge: true }), 'merge');
});

test('a repository with no method enabled yields NONE, never a guess', () => {
  assert.equal(mergeMethod({ allow_squash_merge: false, allow_merge_commit: false, allow_rebase_merge: false }), 'NONE');
});

test('malformed or missing input fails closed', () => {
  assert.equal(mergeMethod(null), 'NONE');
  assert.equal(mergeMethod('nonsense'), 'NONE');
  assert.equal(mergeMethod({}), 'NONE');
  // A non-boolean truthy value is not a policy statement — do not act on it.
  assert.equal(mergeMethod({ allow_squash_merge: 'yes' }), 'NONE');
});

test('this repository resolves to squash', () => {
  // The exact shape `gh api repos/{owner}/{repo}` returns for MrEyratnz/software-factory.
  assert.equal(
    mergeMethod({ allow_squash_merge: true, allow_merge_commit: false, allow_rebase_merge: false }),
    'squash',
  );
});
