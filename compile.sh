#!/bin/bash
# ============================================================
# compile.sh — Compiles the Employee Payroll System Java app
# ============================================================
# Prerequisites: Java 17+ JDK must be installed.
#   macOS  : brew install --cask temurin    (or download from adoptium.net)
#   Windows: download JDK from adoptium.net and add to PATH
# ============================================================

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$PROJECT_DIR/src"
LIB_DIR="$PROJECT_DIR/lib"
OUT_DIR="$PROJECT_DIR/out"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Employee Payroll System — Compile Script"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Verify javac is available
if ! command -v javac &>/dev/null; then
  echo ""
  echo "  ERROR: javac not found."
  echo "  Install Java 17+ JDK first:"
  echo "    macOS  : brew install --cask temurin"
  echo "    Other  : https://adoptium.net"
  echo ""
  exit 1
fi

echo ""
echo "  Java version:"
java -version 2>&1 | head -1
echo ""

# Create output directory
mkdir -p "$OUT_DIR"

# Compile all source files
echo "  Compiling source files..."
javac \
  -cp "$LIB_DIR/mysql-connector-j.jar" \
  -d "$OUT_DIR" \
  "$SRC_DIR/util/DBConnection.java" \
  "$SRC_DIR/models/User.java" \
  "$SRC_DIR/models/Employee.java" \
  "$SRC_DIR/models/Payslip.java" \
  "$SRC_DIR/dao/EmployeeDAO.java" \
  "$SRC_DIR/dao/AttendanceDAO.java" \
  "$SRC_DIR/dao/SalaryDAO.java" \
  "$SRC_DIR/dao/ReportDAO.java" \
  "$SRC_DIR/gui/LoginFrame.java" \
  "$SRC_DIR/gui/AdminDashboard.java" \
  "$SRC_DIR/gui/EmployeeDashboard.java" \
  "$SRC_DIR/Main.java"

if [ $? -eq 0 ]; then
  echo ""
  echo "  ✅ Compilation successful! Run the app with:"
  echo "     ./run.sh"
  echo "  or:"
  echo "     java -cp \"out:lib/mysql-connector-j.jar\" Main"
  echo ""
else
  echo ""
  echo "  ❌ Compilation failed. Check the errors above."
  echo ""
  exit 1
fi
