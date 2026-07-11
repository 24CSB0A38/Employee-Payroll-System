# Employee Payroll Management System

A **full-stack desktop application** combining an enterprise-grade **MySQL 8.x database** with a professional **Java Swing GUI**, demonstrating core software engineering competencies: JDBC, OOP, DAO pattern, MVC architecture, stored procedures, and 4-tier role-based authentication.

> 🎯 Built for software engineering portfolios** — simple enough to explain confidently in interviews, polished enough to impress.

---

## Table of Contents
1. [Features](#features)
2. [Tech Stack](#tech-stack)
3. [Project Structure](#project-structure)
4. [RBAC Login Credentials](#rbac-login-credentials)
5. [How to Run — macOS](#how-to-run--macos)
6. [How to Run — Windows](#how-to-run--windows)
7. [How to Run — Linux](#how-to-run--linux)
8. [How JDBC Connects to MySQL](#how-jdbc-connects-to-mysql)
9. [How Stored Procedures are Used](#how-stored-procedures-are-used)
10. [Database Schema Overview](#database-schema-overview)
11. [Interview Concepts Demonstrated](#interview-concepts-demonstrated)

---

## Features

### 🔐 Authentication & Security
- SHA-256 password hashing verified via `sp_authenticate_user` stored procedure
- 4-tier Role-Based Access Control: `Admin` → `HR` → `Manager` → `Employee`
- Inactive account detection and rejection
- Database connectivity pre-check at startup with a friendly error dialog

### 🧑‍💼 Admin / HR / Manager Dashboard
- **Summary Cards** — Total Active Employees, Today's Attendance Count, Payslips Generated
- **Add Employee** — atomic transaction via `sp_add_employee` (User + Employee + Details + Salary + Leave Balances in one rollback-safe transaction)
- **View Employee Directory** — full table from `Employee_Profile_View`
- **Mark Attendance** — calls `sp_add_attendance` (trigger auto-detects Late arrivals)
- **Increment Salary** — calls `sp_increment_salary` (auto-logs history + audit trail via trigger)
- **Generate Monthly Payroll** — calls `sp_generate_monthly_payroll` for all active employees at once
- **Salary Reports Table** — reads `Monthly_Payroll_View`, status colour-coded (Approved / Processed / Rejected)

### 👤 Employee Self-Service Dashboard
- **My Profile Tab** — personal info from `Employee_Profile_View`
- **Attendance History Tab** — full personal log in JTable
- **Salary Reports Tab** — monthly payslip list with full breakdown popup
- **Check-In / Check-Out** — calls `sp_check_in` / `sp_check_out` (trigger auto-computes hours + overtime)

---

## Tech Stack

| Layer | Technology |
|:---|:---|
| GUI | Java Swing (JFrame, JPanel, JTable, CardLayout, JTabbedPane) |
| DB Access | JDBC (PreparedStatement, CallableStatement, ResultSet) |
| Database | MySQL 8.x (`payroll_db`) |
| JDBC Driver | MySQL Connector/J 8.3.0 (included in `lib/`) |
| Language | Java 17+ |
| Architecture | DAO Pattern + MVC-style separation |

---

## Project Structure

```
Employee Payroll System/
│
├── payroll_enterprise.sql        ← Complete MySQL schema (13 tables, triggers, procedures, events)
├── README.md
├── compile.sh  / compile.bat    ← Build scripts (macOS/Linux / Windows)
├── run.sh      / run.bat        ← Launch scripts
├── .gitignore
│
├── lib/
│     └── mysql-connector-j.jar  ← JDBC driver (included, no download needed)
│
├── out/                          ← Compiled .class files (auto-created by compile script)
│
├── screenshots/                  ← Add your screenshots here
│
└── src/
      ├── Main.java               ← Entry point — L&F setup, DB test, EDT launch
      │
      ├── util/
      │     └── DBConnection.java ← JDBC connection factory (configure credentials here)
      │
      ├── models/                 ← Plain data objects (POJOs — no logic)
      │     ├── User.java
      │     ├── Employee.java
      │     └── Payslip.java
      │
      ├── dao/                    ← All database operations (DAO pattern)
      │     ├── EmployeeDAO.java   authenticate, addEmployee, list, dashboard stats
      │     ├── AttendanceDAO.java addAttendance, checkIn, checkOut, history
      │     ├── SalaryDAO.java     updateSalary, incrementSalary
      │     └── ReportDAO.java     generatePayslip, approvePayslip, reports list
      │
      └── gui/                    ← Swing windows and panels
            ├── LoginFrame.java        Dual-panel login with gradient branding
            ├── AdminDashboard.java    Sidebar + CardLayout multi-panel dashboard
            └── EmployeeDashboard.java Tabbed self-service window
```

---

## RBAC Login Credentials

The SQL script seeds **500 employees** across **20 departments** with 4 tiers of access.

### 👑 Admin — Full System Access
| Username | Password |
|:---|:---|
| `admin` | `Admin@123` |

> Admin can do everything: add employees, run payroll, approve payslips, view all reports, manage attendance.

---

### 🧑‍💼 HR — Payroll + Employee Management
| Username | Password | Name | Title |
|:---|:---|:---|:---|
| `hr.sharma` | `Hr@Sharma1` | Priya Sharma | HR Manager |
| `hr.verma` | `Hr@Verma2` | Amit Verma | HR Executive |

> HR can add employees, generate payroll, update salaries, view all reports — but cannot create other Admin accounts.

---

### 👔 Manager — Department + Leave Approval
| Username | Password | Name | Department |
|:---|:---|:---|:---|
| `mgr.rajesh1` | `Mgr@1Pass` | Rajesh Kumar | Engineering |
| `mgr.sunita2` | `Mgr@2Pass` | Sunita Gupta | Product Management |
| `mgr.vikram3` | `Mgr@3Pass` | Vikram Singh | Data Science |
| `mgr.kavitha4` | `Mgr@4Pass` | Kavitha Reddy | DevOps |
| `mgr.deepak5` | `Mgr@5Pass` | Deepak Patel | Quality Assurance |
| `mgr.nandini6` | `Mgr@6Pass` | Nandini Nair | Finance & Accounting |
| `mgr.suresh7` | `Mgr@7Pass` | Suresh Rao | Marketing |
| `mgr.meena8` | `Mgr@8Pass` | Meena Iyer | Sales |
| `mgr.arjun9` | `Mgr@9Pass` | Arjun Joshi | Customer Success |
| `mgr.pooja10` | `Mgr@10Pass` | Pooja Das | Legal & Compliance |
| `mgr.rohan11` | `Mgr@11Pass` | Rohan Pillai | IT Infrastructure |
| `mgr.anita12` | `Mgr@12Pass` | Anita Menon | Security |
| `mgr.sandeep13` | `Mgr@13Pass` | Sandeep Chauhan | Business Intelligence |
| `mgr.divya14` | `Mgr@14Pass` | Divya Shah | Research & Development |
| `mgr.manoj15` | `Mgr@15Pass` | Manoj Mehta | Operations |
| `mgr.rekha16` | `Mgr@16Pass` | Rekha Bhat | Procurement |
| `mgr.anil17` | `Mgr@17Pass` | Anil Desai | Administration |
| `mgr.sujata18` | `Mgr@18Pass` | Sujata Pandey | Training & Development |
| `mgr.varun19` | `Mgr@19Pass` | Varun Sinha | Executive Office |
| `mgr.lalitha20` | `Mgr@20Pass` | Lalitha Krishnan | Human Resources |

> Managers open the Admin Dashboard (they can view employees, approve leave, check attendance) but cannot modify salaries or run payroll.

---

### 👤 Employee — Self-Service Only
| Username | Password | Name |
|:---|:---|:---|
| `emp.arjiye1` | `Emp@1Pass` | Arjun Iyer |
| `emp.vihmeh2` | `Emp@2Pass` | Vihaan Mehta |
| `emp.saitiw3` | `Emp@3Pass` | Sai Tiwari |
| `emp.rohmal4` | `Emp@4Pass` | Rohan Malhotra |
| `emp.prinai5` | `Emp@5Pass` | Priya Nair |
| `emp.anacha6` | `Emp@6Pass` | Ananya Chauhan |
| `emp.divkri7` | `Emp@7Pass` | Divya Krishnan |

> **Pattern for all 477 employees:** Password = `Emp@{N}Pass` where `{N}` is the trailing number in the username.
> Example: username `emp.xxxyyy42` → password `Emp@42Pass`

---

### 🔄 Role Permission Matrix

| Feature | Admin | HR | Manager | Employee |
|:---|:---:|:---:|:---:|:---:|
| Add / Onboard Employee | ✅ | ✅ | ❌ | ❌ |
| View All Employees | ✅ | ✅ | ✅ | ❌ |
| Mark Attendance (for others) | ✅ | ✅ | ❌ | ❌ |
| Self Check-In / Check-Out | ✅ | ✅ | ✅ | ✅ |
| Increment / Update Salary | ✅ | ✅ | ❌ | ❌ |
| Generate Monthly Payroll | ✅ | ✅ | ❌ | ❌ |
| Approve Payroll | ✅ | ✅ | ❌ | ❌ |
| Approve / Reject Leave | ✅ | ✅ | ✅ | ❌ |
| View All Salary Reports | ✅ | ✅ | ❌ | ❌ |
| View Own Profile | ✅ | ✅ | ✅ | ✅ |
| View Own Attendance History | ✅ | ✅ | ✅ | ✅ |
| View Own Salary Report | ✅ | ✅ | ✅ | ✅ |

---

## How to Run — macOS

### Step 1 — Install Java 17+

```bash
# Option A: Download installer (recommended, no Homebrew needed)
# Go to https://adoptium.net → Download macOS .pkg → Run installer

# Option B: Homebrew
brew install --cask temurin
```

Verify:
```bash
java -version    # should show 17.x.x
javac -version   # should show javac 17.x.x
```

### Step 2 — Install & Start MySQL

```bash
# Option A: Official DMG installer (recommended)
# Go to https://dev.mysql.com/downloads/mysql/ → macOS → Download .dmg → Install

# Option B: Homebrew
brew install mysql
brew services start mysql
```

### Step 3 — Load the Database Schema

```bash
mysql -u root -p < "/path/to/Employee Payroll System/payroll_enterprise.sql"
```

### Step 4 — Configure DB Credentials

Open `src/util/DBConnection.java` and update:
```java
private static final String URL      = "jdbc:mysql://127.0.0.1:3306/payroll_db?useSSL=false&serverTimezone=Asia/Kolkata&allowPublicKeyRetrieval=true";
private static final String USERNAME = "root";
private static final String PASSWORD = "your_mysql_password"; // ← change this
```

### Step 5 — Compile

```bash
cd "/Users/apple/Desktop/Employee Payroll System"
chmod +x compile.sh run.sh
./compile.sh
```

### Step 6 — Run

```bash
./run.sh
```

Or manually:
```bash
java -cp "out:lib/mysql-connector-j.jar" Main
```

---

## How to Run — Windows

### Step 1 — Install Java 17+

1. Go to **https://adoptium.net**
2. Download **Windows x64 .msi installer**
3. Run the installer — check **"Set JAVA_HOME"** and **"Add to PATH"** options
4. Open a new Command Prompt and verify:
   ```cmd
   java -version
   javac -version
   ```

### Step 2 — Install MySQL

1. Go to **https://dev.mysql.com/downloads/installer/**
2. Download **MySQL Installer for Windows**
3. Run installer → choose **Developer Default** or **Server Only**
4. Set a root password during setup — note it down
5. MySQL will start automatically as a Windows Service

### Step 3 — Load the Database Schema

Open **MySQL Command Line Client** or **MySQL Workbench**, then run:
```sql
SOURCE C:\path\to\Employee Payroll System\payroll_enterprise.sql;
```

Or from Command Prompt:
```cmd
mysql -u root -p < "C:\path\to\Employee Payroll System\payroll_enterprise.sql"
```

### Step 4 — Configure DB Credentials

Open `src\util\DBConnection.java` and update:
```java
private static final String URL      = "jdbc:mysql://127.0.0.1:3306/payroll_db?useSSL=false&serverTimezone=Asia/Kolkata&allowPublicKeyRetrieval=true";
private static final String USERNAME = "root";
private static final String PASSWORD = "your_mysql_password"; // ← change this
```

### Step 5 — Compile

```cmd
cd "C:\path\to\Employee Payroll System"
compile.bat
```

### Step 6 — Run

```cmd
run.bat
```

Or manually:
```cmd
java -cp "out;lib\mysql-connector-j.jar" Main
```

---

## How to Run — Linux

### Step 1 — Install Java 17+

**Ubuntu / Debian:**
```bash
sudo apt update
sudo apt install openjdk-17-jdk -y
java -version
```

**Fedora / RHEL / CentOS:**
```bash
sudo dnf install java-17-openjdk-devel -y
java -version
```

**Arch Linux:**
```bash
sudo pacman -S jdk17-openjdk
java -version
```

### Step 2 — Install MySQL

**Ubuntu / Debian:**
```bash
sudo apt update
sudo apt install mysql-server -y
sudo systemctl start mysql
sudo systemctl enable mysql   # auto-start on boot

# Secure the installation and set root password
sudo mysql_secure_installation
```

**Fedora / RHEL:**
```bash
sudo dnf install mysql-server -y
sudo systemctl start mysqld
sudo systemctl enable mysqld

# Get temporary root password from log
sudo grep 'temporary password' /var/log/mysqld.log

# Login and change password
mysql -u root -p
ALTER USER 'root'@'localhost' IDENTIFIED BY 'YourNewPassword123!';
```

**Arch Linux:**
```bash
sudo pacman -S mysql
sudo mysqld --initialize --user=mysql
sudo systemctl start mysqld
sudo systemctl enable mysqld
```

### Step 3 — Load the Database Schema

```bash
mysql -u root -p < "/path/to/Employee Payroll System/payroll_enterprise.sql"
```

### Step 4 — Configure DB Credentials

Open `src/util/DBConnection.java` and update the password.

### Step 5 — Compile & Run

```bash
cd "/path/to/Employee Payroll System"
chmod +x compile.sh run.sh
./compile.sh
./run.sh
```

---

## How JDBC Connects to MySQL

```
Java App
   │
   ├── DBConnection.getConnection()
   │         │
   │         └── DriverManager.getConnection(URL, USERNAME, PASSWORD)
   │                   │
   │                   └── mysql-connector-j.jar (JDBC Driver)
   │                               │
   │                               └── TCP socket → 127.0.0.1:3306
   │                                           │
   │                                           └── MySQL Server → payroll_db
   │
   ├── PreparedStatement  →  SELECT queries (safe, parameterized)
   └── CallableStatement  →  CALL stored_procedure(...) invocations
```

**Key code pattern used everywhere:**
```java
// try-with-resources: Connection and Statement auto-closed (no leaks)
try (Connection con = DBConnection.getConnection();
     PreparedStatement ps = con.prepareStatement("SELECT * FROM Employees WHERE emp_id = ?")) {

    ps.setInt(1, empId);           // parameterized — no SQL injection possible
    ResultSet rs = ps.executeQuery();

    while (rs.next()) {
        String name = rs.getString("name");
        double pay  = rs.getDouble("basic_pay");
    }
}
```

---

## How Stored Procedures are Used

### Authentication — `sp_authenticate_user`
```java
// CallableStatement for stored procedures with OUT parameters
String sql = "{CALL sp_authenticate_user(?, ?, ?, ?, ?)}";
CallableStatement cs = con.prepareCall(sql);

cs.setString(1, username);            // IN  p_username
cs.setString(2, password);            // IN  p_password (hashed inside SP)
cs.registerOutParameter(3, Types.INTEGER); // OUT p_user_id
cs.registerOutParameter(4, Types.VARCHAR); // OUT p_role
cs.registerOutParameter(5, Types.VARCHAR); // OUT p_message

cs.execute();

int    userId  = cs.getInt(3);    // read OUT parameter
String role    = cs.getString(4);
String message = cs.getString(5);
```

### Salary Increment — `sp_increment_salary`
```java
String sql = "{CALL sp_increment_salary(?,?,?,?,?)}";
// IN: calling_user_id, emp_id, percent, reason
// OUT: message
// Side effect: AFTER UPDATE trigger auto-logs history to Employee_Salary_History
```

### Batch Payroll — `sp_generate_monthly_payroll`
```java
String sql = "{CALL sp_generate_monthly_payroll(?,?,?,?,?)}";
// IN: calling_user_id, month, year
// OUT: generated_count, message
// Internally: cursor loops through all active employees, calls sp_generate_payslip for each
```

---

## Database Schema Overview

The database (`payroll_db`) is normalised to 3NF with **13 tables**:

| Table | Purpose |
|:---|:---|
| `Users` | Login credentials (SHA-256 hashed), RBAC roles |
| `Employees` | Core employee registry (slim, optimised for JOINs) |
| `Employee_Details` | 1:1 extension with personal/contact info |
| `Employee_Salary` | Current salary components |
| `Employee_Salary_History` | Immutable salary change log (trigger-populated) |
| `Attendance` | Daily records with check-in/out and auto-computed hours |
| `Payslip` | Monthly payslip — full earnings/deductions breakdown |
| `Payroll_Config` | Config-driven calculation params (PF%, PT slabs, bonus%) |
| `Leave_Types` | Leave category master (Casual, Sick, Earned, Maternity…) |
| `Leave_Balance` | Per-employee annual leave quota |
| `Leave_Requests` | Leave workflow: apply → approve/reject |
| `Audit_Log` | Append-only JSON-diff audit trail |
| `Notifications` | In-system notification queue |

**Views used by the Java app:**
- `Employee_Profile_View` — Full employee info join (used in Profile + Directory panels)
- `Monthly_Payroll_View` — Payslip + employee + approver join (used in Reports panel)

**Payroll Formula:**
```
Gross  = Basic + HRA + DA + Medical + Special + Bonus(8.33%) + Overtime Pay
Net    = Gross − PF(12%) − Professional Tax (slab) − Income Tax(10%) − Loss of Pay
LOP    = Absent Days × (Basic Pay / 26 working days)
```
All percentages are read from `Payroll_Config` table — nothing is hardcoded.

---

## Interview Concepts Demonstrated

| Concept | Where in Code |
|:---|:---|
| **OOP / Encapsulation** | All model classes — private fields, public getters only |
| **DAO Pattern** | `EmployeeDAO`, `AttendanceDAO`, `SalaryDAO`, `ReportDAO` |
| **MVC Architecture** | Models ↔ DAOs ↔ GUI panels |
| **JDBC** | `DBConnection`, all DAO methods |
| **PreparedStatement** | All `SELECT` queries — prevents SQL injection |
| **CallableStatement** | All stored procedure invocations — `{CALL sp_name(...)}` |
| **OUT Parameters** | `cs.registerOutParameter()` for SP return values |
| **Stored Procedures** | `sp_authenticate_user`, `sp_add_employee`, `sp_check_in/out`, `sp_increment_salary`, `sp_generate_monthly_payroll` |
| **Transactions** | `sp_add_employee` atomically creates 5 records or rolls back all |
| **Triggers** | Auto-history logging, Late detection, block-delete guard |
| **Database Views** | `Employee_Profile_View`, `Monthly_Payroll_View` |
| **Role-Based Auth** | Login → role check → route to `AdminDashboard` or `EmployeeDashboard` |
| **CRUD Operations** | Create (Add Employee), Read (View All), Update (Salary Increment), Mark Attendance |
| **Exception Handling** | Every DAO wrapped in try-catch → `JOptionPane` user-friendly dialogs |
| **Event-Driven Programming** | `ActionListener` on every button |
| **SwingWorker** | All DB calls on background thread — EDT never blocked |
| **CardLayout** | Admin Dashboard swaps panels without creating new windows |
| **Normalisation** | 3NF schema, 13 tables, proper foreign keys |

---

## Seeded Sample Data

The SQL script automatically populates the database with:

| Data | Count |
|:---|:---|
| Employees | 500 (across 20 departments) |
| Attendance records | 64,500 (Jan–Jun 2025, weekdays only) |
| Monthly payslips | 2,000 (Jan–Apr 2025) |
| Leave requests | 450 |
| Salary history entries | 20 (manager increments) |
| Audit log entries | 64,503 |

---

*Last updated: July 2026*
