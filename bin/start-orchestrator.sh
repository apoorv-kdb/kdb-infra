#!/usr/bin/env bash
# Start the kdb-infra orchestrator (ingestion pipeline)
#
# Usage:
#   ./bin/start-orchestrator.sh [-p PORT] [-dbPath PATH] [-csvPath PATH] [-timerInterval MS]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KDB_ROOT="${KDB_ROOT:-$(dirname "$SCRIPT_DIR")}"

PORT="${PORT:-9000}"
DB_PATH="${DB_PATH:-$KDB_ROOT/curated_db}"
CSV_PATH="${CSV_PATH:-$KDB_ROOT/data/csv}"
TIMER_INTERVAL="${TIMER_INTERVAL:-3600000}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p)             PORT="$2";           shift 2 ;;
    -dbPath)        DB_PATH="$2";        shift 2 ;;
    -csvPath)       CSV_PATH="$2";       shift 2 ;;
    -timerInterval) TIMER_INTERVAL="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

echo "=========================================="
echo "  Orchestrator"
echo "  Root:   $KDB_ROOT"
echo "  Port:   $PORT"
echo "  DB:     $DB_PATH"
echo "  CSV:    $CSV_PATH"
echo "  Timer:  ${TIMER_INTERVAL}ms"
echo "=========================================="

mkdir -p "$DB_PATH" "$CSV_PATH"

cd "$KDB_ROOT"
exec q init.q -p "$PORT" -dbPath "$DB_PATH" -csvPath "$CSV_PATH" -timerInterval "$TIMER_INTERVAL"
