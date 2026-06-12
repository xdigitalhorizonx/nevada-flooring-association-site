#!/bin/bash
# SessionStart hook for Claude Code cloud sessions. Installs dependencies,
# then prints a freshness report of every Digital Horizon repo so Claude can
# relay it and ask which repo to work on. No-op outside the cloud.
set -uo pipefail

[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
if [ -f package.json ] && [ ! -d node_modules ]; then
  npm install --no-audit --no-fund --silent || true
fi

if [ -z "${GH_TOKEN:-}" ]; then
  echo "Repo activity report unavailable: add GH_TOKEN to the cloud environment's variables (a GitHub PAT with read access to xdigitalhorizonx repos)."
  exit 0
fi

OWNER="xdigitalhorizonx"
repos=$(curl -sf --max-time 20 \
  -H "Authorization: Bearer $GH_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/user/repos?affiliation=owner,collaborator,organization_member&sort=pushed&per_page=100") || {
  echo "Repo activity report unavailable: GitHub API request failed (check GH_TOKEN and network access)."
  exit 0
}

echo "## Digital Horizon repos by last change (most recent first)"
echo "$repos" | jq -r --arg owner "$OWNER" '
  def ago:
    ((now - (.pushed_at | fromdateiso8601)) / 86400 | floor) as $d
    | if $d <= 0 then "today"
      elif $d == 1 then "yesterday"
      elif $d < 30 then "\($d) days ago"
      else "\($d / 30 | floor) months ago" end;
  [ .[] | select(.owner.login == $owner) ]
  | sort_by(.pushed_at) | reverse | .[]
  | "- \(.name) — last change \(ago) (\(.pushed_at | split("T")[0]))"
' || echo "(could not parse GitHub API response)"

echo ""
echo "Instruction to Claude: present the report above to the user, then tell them you are ready to make edits to whichever repo they choose. If they pick a repo that is not part of this session, bring it into scope with the list_repos/add_repo tools before editing."
