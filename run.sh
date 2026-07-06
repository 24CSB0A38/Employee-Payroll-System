#!/bin/bash
# ============================================================
# run.sh — Runs the Employee Payroll System Java app
# Run compile.sh first if 'out/' directory doesn't exist.
# ============================================================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -d "$PROJECT_DIR/out" ]; then
  echo "  'out/' not found. Running compile.sh first..."
  bash "$PROJECT_DIR/compile.sh"
fi

echo ""
echo "  🚀 Starting Employee Payroll Management System..."
echo ""
java -cp "$PROJECT_DIR/out:$PROJECT_DIR/lib/mysql-connector-j.jar" Main
