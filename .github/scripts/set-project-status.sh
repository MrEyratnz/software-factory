#!/usr/bin/env bash
# Set the Projects v2 "Status" field for every project item linked to an issue.
#
# Usage: set-project-status.sh <issue-number> <status-name>
# Env:   GH_TOKEN — token with Projects v2 access (classic PAT `project` scope,
#                   or fine-grained PAT with Projects read/write); the default
#                   Actions GITHUB_TOKEN cannot mutate Projects v2.
#        GH_REPO  — owner/name of the repo the issue lives in.
#
# Status names match case-insensitively against the project's single-select
# options. A project without a matching option is skipped with a warning; an
# issue on no project at all is a no-op success.
set -euo pipefail

issue="${1:?usage: set-project-status.sh <issue-number> <status-name>}"
status="${2:?usage: set-project-status.sh <issue-number> <status-name>}"
: "${GH_REPO:?GH_REPO (owner/name) must be set}"
owner="${GH_REPO%/*}"
repo="${GH_REPO#*/}"

items=$(gh api graphql \
  -f owner="$owner" -f repo="$repo" -F number="$issue" \
  -f query='
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        issue(number: $number) {
          projectItems(first: 20) {
            nodes {
              id
              project {
                id
                title
                field(name: "Status") {
                  ... on ProjectV2SingleSelectField {
                    id
                    options { id name }
                  }
                }
              }
            }
          }
        }
      }
    }')

count=$(jq '.data.repository.issue.projectItems.nodes | length' <<<"$items")
if [ "$count" -eq 0 ]; then
  echo "issue #$issue is not on any project — nothing to transition"
  exit 0
fi

jq -c '.data.repository.issue.projectItems.nodes[]' <<<"$items" | while read -r node; do
  item_id=$(jq -r '.id' <<<"$node")
  project_id=$(jq -r '.project.id' <<<"$node")
  title=$(jq -r '.project.title' <<<"$node")
  field_id=$(jq -r '.project.field.id // empty' <<<"$node")
  option_id=$(jq -r --arg s "$status" \
    '.project.field.options[]? | select((.name | ascii_downcase) == ($s | ascii_downcase)) | .id' \
    <<<"$node")
  if [ -z "$field_id" ] || [ -z "$option_id" ]; then
    echo "::warning::project \"$title\" has no Status option named \"$status\" — skipped"
    continue
  fi
  gh api graphql \
    -f project="$project_id" -f item="$item_id" -f field="$field_id" -f option="$option_id" \
    -f query='
      mutation($project: ID!, $item: ID!, $field: ID!, $option: String!) {
        updateProjectV2ItemFieldValue(input: {
          projectId: $project, itemId: $item, fieldId: $field,
          value: { singleSelectOptionId: $option }
        }) { projectV2Item { id } }
      }' >/dev/null
  echo "issue #$issue -> \"$status\" on project \"$title\""
done
