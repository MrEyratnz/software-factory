#!/usr/bin/env bash
# Move a GitHub issue's Projects-v2 item(s) to a given Status column.
#
# Usage: set-issue-project-status.sh <issue-number> <status-name>
#
# Environment:
#   GH_TOKEN           Token for the GraphQL calls. Projects v2 is NOT
#                      readable/writable with the default Actions GITHUB_TOKEN;
#                      use a PAT with the classic `project` scope (or a
#                      fine-grained token with Projects read/write) — the
#                      PROJECT_TOKEN repository secret in this repo's setup.
#   GITHUB_REPOSITORY  owner/repo (set automatically on Actions runners).
#   PROJECT_NUMBER     Optional. When set and the issue is on no project yet,
#                      the issue is first added to this project of the repo
#                      owner, then moved.
#   GH_TOKEN_SOURCE    Optional. Name of the secret GH_TOKEN came from; used
#                      only to make error messages actionable.
set -euo pipefail

ISSUE="${1:?usage: set-issue-project-status.sh <issue-number> <status-name>}"
STATUS="${2:?usage: set-issue-project-status.sh <issue-number> <status-name>}"
OWNER="${GITHUB_REPOSITORY%%/*}"
REPO="${GITHUB_REPOSITORY#*/}"

gql_err=$(mktemp)
trap 'rm -f "$gql_err"' EXIT

# Keeps gh's stdout (the JSON jq parses) separate from its stderr, so a
# warning or error message can never corrupt the JSON stream.
gql() {
  gh api graphql "$@" 2>"$gql_err"
}

hint() {
  echo "::error::$1 (token source: ${GH_TOKEN_SOURCE:-GH_TOKEN}). The default GITHUB_TOKEN cannot access Projects v2 — set the PROJECT_TOKEN repository secret to a PAT with the 'project' scope."
}

fail_gql() {
  cat "$gql_err" >&2
  hint "$1"
  exit 1
}

issue_query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $number) {
      id
      projectItems(first: 10) {
        nodes {
          id
          project {
            id
            title
            field(name: "Status") {
              ... on ProjectV2SingleSelectField { id options { id name } }
            }
          }
        }
      }
    }
  }
}'

data=$(gql -f query="$issue_query" -F owner="$OWNER" -F repo="$REPO" -F number="$ISSUE") ||
  fail_gql "Could not read project items for issue #$ISSUE"

issue_id=$(jq -r '.data.repository.issue.id' <<<"$data")
items=$(jq -c '[.data.repository.issue.projectItems.nodes[]]' <<<"$data")

if [ "$(jq 'length' <<<"$items")" -eq 0 ]; then
  if [ -n "${PROJECT_NUMBER:-}" ]; then
    # Not on any board yet: add it to the configured project, carrying the
    # project's Status field along so the move below can use it.
    project_query='
query($owner: String!, $number: Int!) {
  repositoryOwner(login: $owner) {
    ... on ProjectV2Owner {
      projectV2(number: $number) {
        id
        title
        field(name: "Status") {
          ... on ProjectV2SingleSelectField { id options { id name } }
        }
      }
    }
  }
}'
    proj=$(gql -f query="$project_query" -F owner="$OWNER" -F number="$PROJECT_NUMBER") ||
      fail_gql "Could not read project #$PROJECT_NUMBER"
    add_mutation='
mutation($project: ID!, $content: ID!) {
  addProjectV2ItemById(input: { projectId: $project, contentId: $content }) {
    item { id }
  }
}'
    project_id=$(jq -r '.data.repositoryOwner.projectV2.id' <<<"$proj")
    added=$(gql -f query="$add_mutation" -F project="$project_id" -F content="$issue_id") ||
      fail_gql "Could not add issue #$ISSUE to project #$PROJECT_NUMBER"
    items=$(jq -c --arg item "$(jq -r '.data.addProjectV2ItemById.item.id' <<<"$added")" \
      '[{ id: $item, project: .data.repositoryOwner.projectV2 }]' <<<"$proj")
  elif [ "${GH_TOKEN_SOURCE:-}" != "PROJECT_TOKEN" ]; then
    # With a non-project token, "no items" is indistinguishable from "not
    # allowed to see the items" — fail loudly instead of skipping silently.
    hint "Issue #$ISSUE appears to be on no project board, but the token in use cannot see Projects v2"
    exit 1
  else
    echo "::warning::Issue #$ISSUE is on no project board and PROJECT_NUMBER is not set — nothing to move."
    exit 0
  fi
fi

update_mutation='
mutation($project: ID!, $item: ID!, $field: ID!, $option: String!) {
  updateProjectV2ItemFieldValue(
    input: { projectId: $project, itemId: $item, fieldId: $field, value: { singleSelectOptionId: $option } }
  ) {
    projectV2Item { id }
  }
}'

moved=0
count=$(jq 'length' <<<"$items")
for i in $(seq 0 $((count - 1))); do
  node=$(jq -c ".[$i]" <<<"$items")
  title=$(jq -r '.project.title' <<<"$node")
  # [0] pins a single option id even if two option names collide
  # case-insensitively with $STATUS.
  option_id=$(jq -r --arg status "$STATUS" \
    '[.project.field.options[]? | select(.name | ascii_downcase == ($status | ascii_downcase)) | .id][0] // ""' <<<"$node")
  if [ -z "$option_id" ]; then
    echo "::warning::Project \"$title\" has no \"$STATUS\" option on its Status field — skipping it."
    continue
  fi
  gql -f query="$update_mutation" \
    -F project="$(jq -r '.project.id' <<<"$node")" \
    -F item="$(jq -r '.id' <<<"$node")" \
    -F field="$(jq -r '.project.field.id' <<<"$node")" \
    -F option="$option_id" >/dev/null ||
    fail_gql "Could not set issue #$ISSUE to \"$STATUS\" on project \"$title\""
  echo "Issue #$ISSUE moved to \"$STATUS\" on project \"$title\"."
  moved=$((moved + 1))
done

if [ "$moved" -eq 0 ]; then
  echo "::error::Issue #$ISSUE was not moved to \"$STATUS\" on any project."
  exit 1
fi
