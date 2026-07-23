#!/usr/bin/env node
// merge-method — pick a merge method the repository actually allows, from the
// `gh api repos/{owner}/{repo}` payload. Prints squash | merge | rebase | NONE.
//
// Why: the merge gate hardcoded `--merge`, and this repository allows squash
// only, so every self-merge would have failed with "Merge commits are not
// allowed on this repository" (#98). Hardcoding `--squash` instead just moves
// the breakage to repositories with the opposite policy — and this workflow is
// the factory's, meant to survive being pointed at a repo whose settings nobody
// asked about. So read the policy rather than assume it.
//
// Preference order is squash first: the factory produces many small PRs, and a
// squashed history keeps main readable and bisectable. It is only a preference
// — whatever the repository permits wins.
//
// Fails closed: anything unparseable, or a repository with every method
// disabled, yields NONE so the caller can fail loudly instead of guessing.
//
// Usage: gh api repos/OWNER/REPO | node scripts/merge-method.mjs

const FLAG = {
  squash: 'allow_squash_merge',
  merge: 'allow_merge_commit',
  rebase: 'allow_rebase_merge',
};

// mergeMethod(repo, preference) — the first preferred method the repo allows.
export function mergeMethod(repo, preference = ['squash', 'merge', 'rebase']) {
  if (repo == null || typeof repo !== 'object') return 'NONE';
  // Strict boolean check: GitHub sends real booleans here, and treating a
  // truthy string as consent would be inventing policy from a shape we do not
  // recognize.
  for (const method of preference) {
    if (repo[FLAG[method]] === true) return method;
  }
  return 'NONE';
}

if (process.argv[1] && import.meta.url.endsWith(process.argv[1].split('/').pop())) {
  let raw = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { raw += c; });
  process.stdin.on('end', () => {
    let parsed = null;
    try {
      parsed = JSON.parse(raw);
    } catch {
      process.stdout.write('NONE\n');
      return;
    }
    process.stdout.write(`${mergeMethod(parsed)}\n`);
  });
}
