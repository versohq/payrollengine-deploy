#!/usr/bin/env bash
# Regenerate stack/init/*.sql from PayrollEngine.Backend sources.
# Create-Model.mysql.sql is self-contained (tables + 7 functions + 44 stored procs).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="${REPO_ROOT}/PayrollEngine.Backend/Database/Create-Model.mysql.sql"
DST="${REPO_ROOT}/stack/init/01-Create-Model.mysql.sql"

if [[ ! -f "${SRC}" ]]; then
  echo "ERROR: source not found: ${SRC}" >&2
  exit 1
fi

mkdir -p "$(dirname "${DST}")"
cp "${SRC}" "${DST}"
echo "✓ $(wc -l < "${DST}") lines → ${DST#${REPO_ROOT}/}"
