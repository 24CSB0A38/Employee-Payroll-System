# Employee Payroll Management System

A **full-stack desktop application** combining an enterprise-grade **MySQL database** with a professional **Java Swing GUI**, designed to demonstrate core software engineering competencies in JDBC, OOP, DAO pattern, MVC architecture, stored procedures, and role-based authentication.

Suitable for **FAANG-level software engineering resumes** while remaining simple enough to **explain confidently in interviews**.

---

## Screenshots

| Login Screen | Admin Dashboard |
|:---:|:---:|
| *Centered dual-panel login with branding* | *Sidebar navigation + summary cards* |

| Employee Directory | Salary Report Detail |
|:---:|:---:|
| *JTable with all employees + departments* | *Full payslip breakdown in text dialog* |

> Run the application and take screenshots to fill the `screenshots/` folder.

---

## Features

### Authentication & Security
- ✅ SHA-256 password hashing (verified inside `sp_authenticate_user` stored procedure)
- ✅ Role-Based Access Control: `Admin` / `HR` / `Manager` → Admin Dashboard; `Employee` → Employee Dashboard
- ✅ Inactive account detection
- ✅ Database connectivity pre-check at startup

### Admin / HR / Manager Dashboard
- ✅ **Dashboard Cards**: Total Active Employees, Today's Attendance, Total Payslips Generated
- ✅ **Add Employee**: Atomic transaction via `sp_add_employee` (creates User + Employee + Details + Salary + Leave Balances in one go)
- ✅ **View Employee Directory**: Full list from `Employee_Profile_View`
- ✅ **Mark Attendance**: Calls `sp_add_attendance` (triggers auto-detect Late status)
- ✅ **Increment Salary**: Calls `sp_increment_salary` (triggers history logging + audit trail)
- ✅ **Generate Monthly Payroll**: Calls `sp_generate_monthly_payroll` for all active employees
- ✅ **Salary Reports Table**: Reads from `Monthly_Payroll_View`, status colour-coded

### Employee Self-Service Dashboard
- ✅ **My Profile Tab**: Reads from `Employee_Profile_View`
- ✅ **Attendance History Tab**: Full personal attendance log
- ✅ **Salary Reports Tab**: Monthly payslip list with View Details popup
- ✅ **Check-In Button**: Calls `sp_check_in` (auto-Late detection)
- ✅ **Check-Out Button**: Calls `sp_check_out` (auto-computes working hours + overtime)

### Database & Integration
- ✅ MySQL 8.x stored procedures invoked via `CallableStatement`
- ✅ `PreparedStatement` for all read queries (zero SQL injection risk)
- ✅ `try-with-resources` for all JDBC objects (no connection leaks)
- ✅ `SwingWorker` keeps DB calls off the Event Dispatch Thread
- ✅ All salary formulas config-driven from `Payroll_Config` table

---

## Technologies

| Layer | Technology |
|:---|:---|
| GUI | Java Swing (JFrame, JPanel, JTable, JDialog, JTabbedPane) |
| DB Access | JDBC (PreparedStatement, CallableStatement, ResultSet) |
| Database | MySQL 8.x (`payroll_db`) |
| Driver | MySQL Connector/J 8.3.0 |
| Language | Java 17+ |
| Architecture | DAO Pattern + MVC-style separation |

---

## Folder Structure

```
Employee Payroll System/
│
├── payroll_enterprise.sql       ← Complete MySQL schema (DO NOT MODIFY)
├── README.md
├── compile.sh  / compile.bat   ← Build scripts (macOS / Windows)
├── run.sh      / run.bat       ← Launch scripts
│
├── lib/
│     └── mysql-connector-j.jar ← JDBC driver (already included)
│
├── out/                         ← Compiled .class files (auto-created)
│
├── screenshots/                 ← Add your own screenshots here
│
└── src/
      ├── Main.java              ← Entry point: L&F + DB test + EDT launch
      │
      ├── util/
      │     └── DBConnection.java  ← JDBC connection factory
      │
      ├── models/                ← Plain data objects (POJOs)
      │     ├── User.java
      │     ├── Employee.java
      │     └── Payslip.java
      │
      ├── dao/                   ← All database operations (DAO pattern)
      │     ├── EmployeeDAO.java    authenticate, addEmployee, list, stats
      │     ├── AttendanceDAO.java  addAttendance, checkIn, checkOut, history
      │     ├── SalaryDAO.java      updateSalary, incrementSalary
      │     └── ReportDAO.java      generatePayslip, approvePayslip, list
      │
      └── gui/                   ← Swing windows and panels
            ├── LoginFrame.java      Dual-panel login window
            ├── AdminDashboard.java  Sidebar + CardLayout main window
            └── EmployeeDashboard.java  Tabbed self-service window
```

---

## Database Schema Overview

The database (`payroll_db`) is fully normalised to 3NF and comprises **13 tables**:

| Table | Purpose |
|:---|:---|
| `Users` | Login credentials (SHA-256 hashed), RBAC roles |
| `Employees` | Core employee registry (slim, optimised for JOINs) |
| `Employee_Details` | 1:1 extension with personal/contact info |
| `Employee_Salary` | Current salary components |
| `Employee_Salary_History` | Immutable salary change log (trigger-populated) |
| `Attendance` | Daily records with check-in/out and auto-computed hours |
| `Payslip` | Monthly payslip (Pending → Processed → Approved lifecycle) |
| `Payroll_Config` | Config-driven calculation params (PF%, PT slabs, etc.) |
| `Leave_Types` | Leave category master (Casual, Sick, Earned, …) |
| `Leave_Balance` | Per-employee annual leave quota |
| `Leave_Requests` | Leave workflow (apply → approve/reject) |
| `Audit_Log` | Append-only JSON-diff audit trail |
| `Notifications` | In-system notification queue |

**Key Views used by the Java app:**
- `Employee_Profile_View` — Full employee info join (used in Profile + Directory)
- `Monthly_Payroll_View` — Payslip + employee + approver join (used in Reports)

---

## How to Run

### Prerequisites

1. **Java 17+ JDK** — install from [adoptium.net](https://adoptium.net) or via Homebrew:
   ```bash
   brew install --cask temurin
   ```
2. **MySQL 8.x** running on `localhost:3306`
3. **payroll_db** schema loaded:
   ```bash
   mysql -u root -p < payroll_enterprise.sql
   ```

### Step 1 — Configure DB credentials

Open `src/util/DBConnection.java` and update:
```java
private static final String USERNAME = "root";
private static final String PASSWORD = "yourpassword"; // ← change this
```

### Step 2 — Compile

**macOS / Linux:**
```bash
chmod +x compile.sh run.sh
./compile.sh
```

**Windows:**
```cmd
compile.bat
```

**Manual compile (any OS):**
```bash
javac -cp "lib/mysql-connector-j.jar" -d out \
      src/util/*.java src/models/*.java src/dao/*.java src/gui/*.java src/Main.java
```

### Step 3 — Run

**macOS / Linux:**
```bash
./run.sh
```

**Windows:**
```cmd
run.bat
```

**Manual run:**
```bash
# macOS/Linux
java -cp "out:lib/mysql-connector-j.jar" Main

# Windows
java -cp "out;lib\mysql-connector-j.jar" Main
```

### Step 4 — Login

Default admin credentials seeded by `payroll_enterprise.sql`:
```
Username: admin
Password: Admin@123
```

---

## How JDBC Connects to MySQL

```java
// DBConnection.java
Connection con = DriverManager.getConnection(
    "jdbc:mysql://localhost:3306/payroll_db?useSSL=false&serverTimezone=UTC",
    "root",
    "password"
);
```

Every DAO method uses `try-with-resources`:
```java
try (Connection con = DBConnection.getConnection();
     PreparedStatement ps = con.prepareStatement(sql)) {
    // safe: Connection and Statement closed automatically
}
```

---

## How Stored Procedures Are Called

### Authentication (`EmployeeDAO.authenticate`)
```java
String sql = "{CALL sp_authenticate_user(?, ?, ?, ?, ?)}";
CallableStatement cs = con.prepareCall(sql);
cs.setString(1, username);
cs.setString(2, password);           // hashed inside the stored procedure
cs.registerOutParameter(3, Types.INTEGER);  // OUT user_id
cs.registerOutParameter(4, Types.VARCHAR);  // OUT role
cs.registerOutParameter(5, Types.VARCHAR);  // OUT message
cs.execute();
int userId = cs.getInt(3);
```

### Salary Increment (`SalaryDAO.incrementSalary`)
```java
String sql = "{CALL sp_increment_salary(?,?,?,?,?)}";
// IN: calling_user_id, emp_id, percent, reason
// OUT: message
```

### Monthly Payroll Generation (`ReportDAO.generateMonthlyPayroll`)
```java
String sql = "{CALL sp_generate_monthly_payroll(?,?,?,?,?)}";
// IN: calling_user_id, month, year
// OUT: generated_count, message
```

---

## Interview Concepts Demonstrated

| Concept | Where |
|:---|:---|
| **OOP / Encapsulation** | All model classes (`User`, `Employee`, `Payslip`) |
| **DAO Pattern** | `EmployeeDAO`, `AttendanceDAO`, `SalaryDAO`, `ReportDAO` |
| **MVC Architecture** | Models ↔ DAOs ↔ GUI panels |
| **JDBC** | `DBConnection`, all DAO methods |
| **PreparedStatement** | All `SELECT` queries in DAOs |
| **CallableStatement** | All stored procedure invocations |
| **Stored Procedures** | `sp_authenticate_user`, `sp_add_employee`, `sp_check_in/out`, `sp_increment_salary`, `sp_generate_monthly_payroll` |
| **Role-Based Authentication** | `LoginFrame` → role-check → `AdminDashboard` or `EmployeeDashboard` |
| **CRUD** | Create (Add Employee), Read (View Directory/Profile), Update (Salary Increment), Mark Attendance |
| **Exception Handling** | `JOptionPane` on every `catch (SQLException)` |
| **Event-Driven Programming** | `ActionListener` on every button |
| **SwingWorker** | All DB calls run off the EDT |
| **Normalisation** | 3NF schema, 13 tables, foreign keys |
| **Database Views** | `Employee_Profile_View`, `Monthly_Payroll_View` |
| **Triggers** | Auto-history logging, Late detection (in SQL layer) |
| **Transactions** | Atomic employee onboarding in `sp_add_employee` |

---

## Contributors

Built as a portfolio / interview demonstration project combining:
- **MySQL 8.x** enterprise database engineering
- **Java 17 Swing** desktop GUI development
- **JDBC** database integration

---

*Last updated: July 2026*
