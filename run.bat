@echo off
REM ============================================================
REM run.bat -- Windows run script
REM ============================================================

if not exist "out" (
    echo Compiling first...
    call compile.bat
)

echo.
echo   Starting Employee Payroll Management System...
echo.
java -cp "out;lib\mysql-connector-j.jar" Main
