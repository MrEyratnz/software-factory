// Tests for scripts/pr-review-state.mjs — the merge gate's review verdict.
// Run: node --test scripts/pr-review-state.test.mjs
//
// The bug this pins (found by the factory's own review station on PR #96): the
// merge job substring-matched the PR's FULL review history, so one early
// CHANGES_REQUESTED blocked auto-merge forever — even after the same reviewer
// approved a later push. A PR's verdict is the CURRENT state of each reviewer,
// not everything that was ever true of it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { reviewState } from './pr-review-state.mjs';

const r = (login, state, submittedAt) => ({ author: { login }, state, submittedAt });

test('an approval is an approval', () => {
  assert.equal(reviewState([r('bot', 'APPROVED', '2026-07-23T10:00:00Z')]), 'APPROVED');
});

test('no reviews at all is not an approval', () => {
  assert.equal(reviewState([]), 'NONE');
});

test('a comment-only review does not approve', () => {
  assert.equal(reviewState([r('bot', 'COMMENTED', '2026-07-23T10:00:00Z')]), 'NONE');
});

test('outstanding changes-requested blocks', () => {
  assert.equal(reviewState([r('bot', 'CHANGES_REQUESTED', '2026-07-23T10:00:00Z')]), 'CHANGES_REQUESTED');
});

test('a later approval supersedes the same reviewer\'s earlier changes-requested', () => {
  const reviews = [
    r('bot', 'CHANGES_REQUESTED', '2026-07-23T10:00:00Z'),
    r('bot', 'APPROVED', '2026-07-23T11:00:00Z'),
  ];
  assert.equal(reviewState(reviews), 'APPROVED');
});

test('input order does not decide the verdict — submittedAt does', () => {
  const reviews = [
    r('bot', 'APPROVED', '2026-07-23T11:00:00Z'),
    r('bot', 'CHANGES_REQUESTED', '2026-07-23T10:00:00Z'),
  ];
  assert.equal(reviewState(reviews), 'APPROVED');
});

test('a later changes-requested supersedes an earlier approval', () => {
  const reviews = [
    r('bot', 'APPROVED', '2026-07-23T10:00:00Z'),
    r('bot', 'CHANGES_REQUESTED', '2026-07-23T11:00:00Z'),
  ];
  assert.equal(reviewState(reviews), 'CHANGES_REQUESTED');
});

test('one reviewer blocking outweighs another approving', () => {
  const reviews = [
    r('alice', 'APPROVED', '2026-07-23T10:00:00Z'),
    r('bob', 'CHANGES_REQUESTED', '2026-07-23T10:30:00Z'),
  ];
  assert.equal(reviewState(reviews), 'CHANGES_REQUESTED');
});

test('a later COMMENTED does not dismiss an approval (GitHub semantics)', () => {
  const reviews = [
    r('bot', 'APPROVED', '2026-07-23T10:00:00Z'),
    r('bot', 'COMMENTED', '2026-07-23T11:00:00Z'),
  ];
  assert.equal(reviewState(reviews), 'APPROVED');
});

test('a dismissed review no longer counts either way', () => {
  const reviews = [
    r('bot', 'CHANGES_REQUESTED', '2026-07-23T10:00:00Z'),
    r('bot', 'DISMISSED', '2026-07-23T11:00:00Z'),
  ];
  assert.equal(reviewState(reviews), 'NONE');
});

test('malformed input fails closed, never as an approval', () => {
  assert.equal(reviewState(null), 'NONE');
  assert.equal(reviewState('nonsense'), 'NONE');
  assert.equal(reviewState([{ state: 'APPROVED' }]), 'APPROVED'); // missing author still counts
  assert.equal(reviewState([{}]), 'NONE');
});
