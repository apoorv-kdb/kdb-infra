#!/usr/bin/env bash
# Start the sales app HTTP server
# Must be run from the kdb-infra root, or set KDB_ROOT explicitly
#
# Usage:
#   ./bin/start-sales-server.sh [-p PORT] [-dbPath PATH] [-catPath PATH] [-csvPath PATH]
#
# Examples:
#   ./bin/start-sales-server.sh
#   ./bin/start-sales-server.sh -p 5020 -dbPath /data/prod/curated_db
#   KDB_ROOT=/opt/kdb ./bin/start-sales-server.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KDB_ROOT="${KDB_ROOT:-$(dirname "$SCRIPT_DIR")}"

PORT="${PORT:-5010}"
DB_PATH="${DB_PATH:-$KDB_ROOT/curated_db}"
CAT_PATH="${CAT_PATH:-$KDB_ROOT/config/catalog_sales.csv}"
CSV_PATH="${CSV_PATH:-$KDB_ROOT/data/csv}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p)        PORT="$2";     shift 2 ;;
    -dbPath)   DB_PATH="$2";  shift 2 ;;
    -catPath)  CAT_PATH="$2"; shift 2 ;;
    -csvPath)  CSV_PATH="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

echo "=========================================="
echo "  Sales server"
echo "  Root:    $KDB_ROOT"
echo "  Port:    $PORT"
echo "  DB:      $DB_PATH"
echo "  Catalog: $CAT_PATH"
echo "=========================================="

mkdir -p "$DB_PATH"

cd "$KDB_ROOT"
exec q apps/sales/server.q -p "$PORT" -dbPath "$DB_PATH" -catPath "$CAT_PATH" -csvPath "$CSV_PATH"
