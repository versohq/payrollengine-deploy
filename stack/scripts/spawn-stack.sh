#!/usr/bin/env bash
# spawn-stack.sh — spawn a Payroll Engine instance on Dokploy
#
# Usage:
#   ./spawn-stack.sh bootstrap
#     Creates the 'payroll-template' project + compose service on Dokploy (idempotent).
#
#   ./spawn-stack.sh spawn <name> <regulation-repo-url> [entry-file]
#     Duplicates the template into a new project named <name>, overrides the env vars,
#     and triggers deployment.
#
# Requires .env at repo root with DOKPLOY_URL and DOKPLOY_STUDIO_API_KEY.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  . "${REPO_ROOT}/.env"
  set +a
fi

: "${DOKPLOY_URL:?set DOKPLOY_URL in .env}"
: "${DOKPLOY_STUDIO_API_KEY:?set DOKPLOY_STUDIO_API_KEY in .env}"

API="${DOKPLOY_URL%/}/api"
HDR_KEY="x-api-key: ${DOKPLOY_STUDIO_API_KEY}"
HDR_JSON="Content-Type: application/json"

TEMPLATE_NAME="${TEMPLATE_NAME:-payroll-template}"
GIT_URL="${STACK_GIT_URL:-https://github.com/versohq/verso-dokploy}"
GIT_BRANCH="${STACK_GIT_BRANCH:-main}"

trpc_get() {
  curl -sf -H "${HDR_KEY}" "${API}/$1"
}

trpc_post() {
  local endpoint="$1"; shift
  local body="$1"; shift
  curl -sf -X POST -H "${HDR_KEY}" -H "${HDR_JSON}" -d "${body}" "${API}/${endpoint}"
}

find_project_by_name() {
  local name="$1"
  trpc_get "project.all" | python3 -c "
import json,sys
target = '$name'
for p in json.load(sys.stdin):
    if p['name'] == target:
        print(p['projectId'])
        break
"
}

find_compose_in_project() {
  local project_id="$1"
  trpc_get "project.one?projectId=${project_id}" | python3 -c "
import json,sys
d = json.load(sys.stdin)
for env in d['environments']:
    if env['compose']:
        print(env['compose'][0]['composeId'])
        break
"
}

cmd_bootstrap() {
  local existing
  existing="$(find_project_by_name "${TEMPLATE_NAME}" || true)"
  if [[ -n "${existing}" ]]; then
    echo "✓ template project already exists: ${existing}"
    return 0
  fi

  echo "creating project ${TEMPLATE_NAME}..."
  local proj
  proj="$(trpc_post project.create "{\"name\":\"${TEMPLATE_NAME}\",\"description\":\"Payroll Engine template — duplicate this to spawn new instances\"}" | python3 -c "import json,sys; print(json.load(sys.stdin)['projectId'])")"
  echo "  projectId=${proj}"

  local env_id
  env_id="$(trpc_get "project.one?projectId=${proj}" | python3 -c "import json,sys; print(json.load(sys.stdin)['environments'][0]['environmentId'])")"
  echo "  environmentId=${env_id}"

  echo "creating compose service..."
  local compose_id
  compose_id="$(trpc_post compose.create "$(cat <<JSON
{
  "name":"payroll",
  "appName":"payroll-template",
  "description":"Payroll Engine stack",
  "environmentId":"${env_id}",
  "composeType":"docker-compose",
  "sourceType":"git"
}
JSON
)" | python3 -c "import json,sys; print(json.load(sys.stdin)['composeId'])")"
  echo "  composeId=${compose_id}"

  echo "configuring git source + env..."
  trpc_post compose.update "$(cat <<JSON
{
  "composeId":"${compose_id}",
  "customGitUrl":"${GIT_URL}",
  "customGitBranch":"${GIT_BRANCH}",
  "customGitBuildPath":"/",
  "composePath":"./docker-compose.yml",
  "sourceType":"git",
  "env":"STACK_NAME=payroll-template\nSTACK_HOST=payroll-template.catapulte.studio\nMYSQL_ROOT_PASSWORD=changeme\nPAYROLL_API_KEY=changeme\nREGULATION_REPO_URL=https://github.com/Payroll-Engine/Regulation.ES.Nomina\nPE_VERSION=0.10.0-beta.4"
}
JSON
)" > /dev/null
  echo "  done"
  echo
  echo "✓ template ready. Run './spawn-stack.sh spawn <name> <regulation-repo-url>' to spawn instances."
}

cmd_spawn() {
  local name="$1" regu="$2" entry="${3:-}"
  local template_id
  template_id="$(find_project_by_name "${TEMPLATE_NAME}")"
  if [[ -z "${template_id}" ]]; then
    echo "ERROR: template '${TEMPLATE_NAME}' not found. Run './spawn-stack.sh bootstrap' first." >&2
    exit 1
  fi

  echo "duplicating ${TEMPLATE_NAME} → ${name}..."
  local new_id
  new_id="$(trpc_post project.duplicate "$(cat <<JSON
{
  "sourceProjectId":"${template_id}",
  "name":"${name}",
  "description":"Spawned from ${TEMPLATE_NAME}",
  "includeServices":true
}
JSON
)" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('projectId',''))")"

  if [[ -z "${new_id}" ]]; then
    echo "ERROR: project.duplicate returned no projectId" >&2
    exit 1
  fi
  echo "  projectId=${new_id}"

  local compose_id
  compose_id="$(find_compose_in_project "${new_id}")"
  echo "  composeId=${compose_id}"

  local password api_key host
  password="$(openssl rand -hex 16)"
  api_key="pe_$(openssl rand -hex 24)"
  host="${name}.catapulte.studio"

  echo "configuring env overrides..."
  trpc_post compose.update "$(cat <<JSON
{
  "composeId":"${compose_id}",
  "env":"STACK_NAME=${name}\nSTACK_HOST=${host}\nMYSQL_ROOT_PASSWORD=${password}\nPAYROLL_API_KEY=${api_key}\nREGULATION_REPO_URL=${regu}\nREGULATION_ENTRY_FILE=${entry}\nPE_VERSION=0.10.0-beta.4"
}
JSON
)" > /dev/null

  echo "deploying..."
  trpc_post compose.deploy "{\"composeId\":\"${compose_id}\"}" > /dev/null
  echo
  echo "✓ spawned ${name}"
  echo "  URL: https://${host}"
  echo "  API key: ${api_key}"
  echo "  MySQL root pwd: ${password}"
  echo
  echo "Dokploy UI: ${DOKPLOY_URL%/api}/dashboard/project/${new_id}"
}

case "${1:-}" in
  bootstrap) cmd_bootstrap ;;
  spawn)
    shift
    [[ $# -ge 2 ]] || { echo "usage: spawn-stack.sh spawn <name> <regulation-repo-url> [entry-file]" >&2; exit 1; }
    cmd_spawn "$@"
    ;;
  *)
    echo "usage: spawn-stack.sh {bootstrap|spawn <name> <regulation-repo-url> [entry-file]}" >&2
    exit 1
    ;;
esac
