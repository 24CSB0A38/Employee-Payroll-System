@echo off
REM ============================================================
REM compile.bat -- Windows compile script
REM ============================================================

echo =============================================
echo   Employee Payroll System - Compile
echo =============================================

if not exist "out" mkdir out

javac -cp "lib\mysql-connector-j.jar" -d out ^
  src\util\DBConnection.java ^
  src\models\User.java ^
  src\models\Employee.java ^
  src\models\Payslip.java ^
  src\dao\EmployeeDAO.java ^
  src\dao\AttendanceDAO.java ^
  src\dao\SalaryDAO.java ^
  src\dao\ReportDAO.java ^
  src\gui\LoginFrame.java ^
  src\gui\AdminDashboard.java ^
  src\gui\EmployeeDashboard.java ^
  src\Main.java

if %ERRORLEVEL% == 0 (
    echo.
    echo   Compilation successful! Run: run.bat
) else (
    echo.
    echo   Compilation FAILED. Check errors above.
)
