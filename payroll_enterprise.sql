-- ============================================================================
-- ENTERPRISE PAYROLL MANAGEMENT SYSTEM  —  MySQL 8.x
-- Version  : 2.0  (Enterprise Edition)
-- Standard : FAANG-Level Production Database Engineering
-- ============================================================================
-- Features :
--   4-tier RBAC        Admin / HR / Manager / Employee
--   SHA-256 auth       Secure login + last_login tracking
--   Audit Logging      JSON old/new values on every critical table
--   Salary History     Immutable trigger-populated change log
--   Leave Workflow     Apply -> Approve/Reject + balance auto-deduction
--   Payroll Engine     Gross/Net/PF/PT/IT/LOP/Bonus/OT  config-driven
--   Payroll Approval   Pending -> Processed -> Approved lifecycle
--   Attendance+        check_in / check_out / working_hours / overtime
--   Transactions       START / COMMIT / ROLLBACK in every procedure
--   Performance        Composite + functional indexes on hot paths
--   6 Views            Analytics-ready for dashboards and reports
--   4 Events           Auto-payroll, reminders, leave reset, archive
--   500 Sample Emps    20 departments, ~65 000 attendance records
-- ============================================================================

-- ============================================================================
-- SECTION 0 — DATABASE SETUP
-- ============================================================================

CREATE DATABASE IF NOT EXISTS payroll_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci
    COMMENT 'Enterprise Payroll Management System v2.0';

USE payroll_db;

-- Disable FK checks during drops so order does not matter
SET FOREIGN_KEY_CHECKS = 0;
SET SQL_SAFE_UPDATES   = 0;

-- Session variables used by triggers for actor tracking
-- Set by each procedure before executing DML
SET @current_user_id      = NULL;
SET @salary_change_reason = NULL;

-- ============================================================================
-- SECTION 1 — DROP EXISTING OBJECTS  (makes script idempotent)
-- ============================================================================

DROP EVENT IF EXISTS auto_salary_report;
DROP EVENT IF EXISTS evt_monthly_payroll;
DROP EVENT IF EXISTS evt_payroll_reminders;
DROP EVENT IF EXISTS evt_leave_balance_reset;
DROP EVENT IF EXISTS evt_archive_old_reports;

DROP TRIGGER IF EXISTS trg_before_salary_insert;
DROP TRIGGER IF EXISTS trg_before_salary_update;
DROP TRIGGER IF EXISTS trg_after_salary_update;
DROP TRIGGER IF EXISTS trg_before_attendance_insert;
DROP TRIGGER IF EXISTS trg_before_attendance_update;
DROP TRIGGER IF EXISTS trg_after_attendance_insert;
DROP TRIGGER IF EXISTS trg_after_employee_update;
DROP TRIGGER IF EXISTS trg_before_employee_delete;
DROP TRIGGER IF EXISTS trg_before_leave_update;
DROP TRIGGER IF EXISTS trg_after_leave_update;
DROP TRIGGER IF EXISTS trg_after_payslip_update;

DROP VIEW IF EXISTS Employee_Profile_View;
DROP VIEW IF EXISTS Monthly_Payroll_View;
DROP VIEW IF EXISTS Attendance_Summary_View;
DROP VIEW IF EXISTS Department_Expense_View;
DROP VIEW IF EXISTS Leave_Balance_View;
DROP VIEW IF EXISTS Top_Earners_View;

DROP PROCEDURE IF EXISTS add_attendance;
DROP PROCEDURE IF EXISTS increment_salary;
DROP PROCEDURE IF EXISTS apply_decrements;
DROP PROCEDURE IF EXISTS generate_salary_report;
DROP PROCEDURE IF EXISTS sp_authenticate_user;
DROP PROCEDURE IF EXISTS sp_register_user;
DROP PROCEDURE IF EXISTS sp_add_employee;
DROP PROCEDURE IF EXISTS sp_update_salary;
DROP PROCEDURE IF EXISTS sp_increment_salary;
DROP PROCEDURE IF EXISTS sp_check_in;
DROP PROCEDURE IF EXISTS sp_check_out;
DROP PROCEDURE IF EXISTS sp_add_attendance;
DROP PROCEDURE IF EXISTS sp_apply_for_leave;
DROP PROCEDURE IF EXISTS sp_approve_reject_leave;
DROP PROCEDURE IF EXISTS sp_generate_payslip;
DROP PROCEDURE IF EXISTS sp_approve_payroll;
DROP PROCEDURE IF EXISTS sp_generate_monthly_payroll;
DROP PROCEDURE IF EXISTS sp_apply_decrements;
DROP PROCEDURE IF EXISTS sp_create_notification;
DROP PROCEDURE IF EXISTS sp_generate_sample_data;

DROP FUNCTION IF EXISTS fn_get_config;
DROP FUNCTION IF EXISTS fn_calc_professional_tax;
DROP FUNCTION IF EXISTS fn_has_permission;

DROP TABLE IF EXISTS Notifications;
DROP TABLE IF EXISTS Payslip;
DROP TABLE IF EXISTS Salary_Report;
DROP TABLE IF EXISTS Leave_Requests;
DROP TABLE IF EXISTS Leave_Balance;
DROP TABLE IF EXISTS Leave_Types;
DROP TABLE IF EXISTS Audit_Log;
DROP TABLE IF EXISTS Employee_Salary_History;
DROP TABLE IF EXISTS Payroll_Config;
DROP TABLE IF EXISTS Attendance;
DROP TABLE IF EXISTS Employee_Salary;
DROP TABLE IF EXISTS Employee_Details;
DROP TABLE IF EXISTS Employees;
DROP TABLE IF EXISTS Users;

-- ============================================================================
-- SECTION 2 — CORE TABLES  (v1.0 schema preserved and extended)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Table: Users
-- Role hierarchy (high to low): Admin > HR > Manager > Employee
-- Passwords stored as SHA-256 hex strings — plain-text NEVER stored
-- ---------------------------------------------------------------------------
CREATE TABLE Users (
    user_id       INT           AUTO_INCREMENT PRIMARY KEY
                  COMMENT 'System user PK linked to Employees.user_id',
    username      VARCHAR(50)   NOT NULL UNIQUE
                  COMMENT 'Unique login handle — lowercase, no spaces',
    password_hash VARCHAR(64)   NOT NULL
                  COMMENT 'SHA2(password,256) — plain-text never stored',
    role          ENUM('Admin','HR','Manager','Employee') NOT NULL DEFAULT 'Employee'
                  COMMENT 'RBAC role: Admin=full, HR=payroll+emp, Manager=dept+leave, Employee=self',
    is_active     TINYINT(1)    NOT NULL DEFAULT 1
                  COMMENT '0=deactivated; deactivated users are rejected at authentication',
    last_login    DATETIME      NULL
                  COMMENT 'Updated by sp_authenticate_user on every successful login',
    created_at    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_users_username    (username),
    INDEX idx_users_role_active (role, is_active)
                  COMMENT 'Composite: active-users-by-role reports'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='System users — authentication credentials and 4-tier RBAC roles';


-- ---------------------------------------------------------------------------
-- Table: Employees
-- Kept slim for JOIN performance; extended details in Employee_Details (3NF)
-- ---------------------------------------------------------------------------
CREATE TABLE Employees (
    emp_id       INT           AUTO_INCREMENT PRIMARY KEY
                 COMMENT 'Universal employee FK used by all payroll tables',
    user_id      INT           NOT NULL
                 COMMENT 'FK to Users — maps employee to system login account',
    name         VARCHAR(100)  NOT NULL
                 COMMENT 'Display name used in reports and payslips',
    department   VARCHAR(50)   NOT NULL
                 COMMENT 'Department for grouping, cost-center, and RBAC scoping',
    designation  VARCHAR(100)  NULL
                 COMMENT 'Job title (e.g. Staff Engineer, Senior Analyst)',
    emp_type     ENUM('Full-Time','Part-Time','Contract') NOT NULL DEFAULT 'Full-Time',
    status       ENUM('Active','Inactive','Terminated')   NOT NULL DEFAULT 'Active'
                 COMMENT 'Only Active employees are included in payroll runs',
    manager_id   INT           NULL
                 COMMENT 'FK to Employees.emp_id — self-reference for org hierarchy',
    created_at   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (user_id)    REFERENCES Users(user_id)     ON DELETE RESTRICT,
    FOREIGN KEY (manager_id) REFERENCES Employees(emp_id)  ON DELETE SET NULL,

    INDEX idx_emp_dept_status (department, status)
                 COMMENT 'Composite: active employees per department — hot payroll filter',
    INDEX idx_emp_user_id     (user_id),
    INDEX idx_emp_manager     (manager_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Core employee registry — slim table optimised for high-frequency JOINs';


-- ---------------------------------------------------------------------------
-- Table: Employee_Details
-- 1:1 extension of Employees — separated for 3NF compliance
-- ---------------------------------------------------------------------------
CREATE TABLE Employee_Details (
    emp_id    INT           PRIMARY KEY
              COMMENT 'PK + FK to Employees — strict 1:1 relationship',
    fname     VARCHAR(50)   NOT NULL,
    lname     VARCHAR(50)   NOT NULL,
    gender    ENUM('Male','Female','Other') NULL,
    dob       DATE          NULL    COMMENT 'Date of birth',
    hire_date DATE          NOT NULL COMMENT 'Official hire date — affects leave accrual',
    email     VARCHAR(100)  NOT NULL UNIQUE COMMENT 'Corporate email — globally unique',
    phone     VARCHAR(15)   NULL,
    address   VARCHAR(255)  NULL,
    city      VARCHAR(100)  NULL,
    state     VARCHAR(100)  NULL,
    pincode   VARCHAR(10)   NULL,
    country   VARCHAR(100)  NULL DEFAULT 'India',

    FOREIGN KEY (emp_id) REFERENCES Employees(emp_id) ON DELETE CASCADE,

    INDEX idx_empdet_email     (email),
    INDEX idx_empdet_hire_date (hire_date)
                 COMMENT 'Seniority queries'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Employee demographics — 1NF-to-3NF split from Employees core table';


-- ---------------------------------------------------------------------------
-- Table: Employee_Salary
-- Source of truth for current salary components
-- History auto-captured in Employee_Salary_History via AFTER UPDATE trigger
-- ---------------------------------------------------------------------------
CREATE TABLE Employee_Salary (
    sal_id            INT           AUTO_INCREMENT PRIMARY KEY,
    emp_id            INT           NOT NULL,
    basic_pay         DECIMAL(10,2) NOT NULL
                      COMMENT 'Base salary — foundation for PF, bonus, and LOP calculations',
    hra               DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT 'House Rent Allowance',
    da                DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT 'Dearness Allowance',
    medical_allowance DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    special_allowance DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    increments        DECIMAL(10,2) NOT NULL DEFAULT 0.00
                      COMMENT 'v1.0 legacy field — preserved for backward compatibility',
    effective_from    DATE          NOT NULL DEFAULT (CURRENT_DATE)
                      COMMENT 'Date this salary structure became active',

    FOREIGN KEY (emp_id) REFERENCES Employees(emp_id) ON DELETE RESTRICT,

    UNIQUE KEY uq_salary_emp    (emp_id)
               COMMENT 'One active salary record per employee',
    INDEX idx_sal_effective     (effective_from)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Current salary structure — history in Employee_Salary_History (trigger-populated)';


-- ---------------------------------------------------------------------------
-- Table: Attendance
-- Extended with check-in/out time-tracking and overtime calculation
-- UNIQUE (emp_id, date) enforces one record per employee per day
-- ---------------------------------------------------------------------------
CREATE TABLE Attendance (
    att_id         INT    AUTO_INCREMENT PRIMARY KEY,
    emp_id         INT    NOT NULL,
    date           DATE   NOT NULL COMMENT 'Attendance date',
    status         ENUM('Present','Absent','Late','Half-Day','Holiday','On-Leave') NOT NULL
                   COMMENT 'Auto-upgraded to Late by trigger if check_in > threshold',
    check_in       TIME   NULL COMMENT 'NULL when absent',
    check_out      TIME   NULL COMMENT 'Updated by sp_check_out',
    working_hours  DECIMAL(4,2) NOT NULL DEFAULT 0.00
                   COMMENT 'Auto-computed: TIME_TO_SEC(check_out - check_in) / 3600',
    overtime_hours DECIMAL(4,2) NOT NULL DEFAULT 0.00
                   COMMENT 'Auto-computed: working_hours - standard_work_hours (config)',
    remarks        VARCHAR(255) NULL,

    FOREIGN KEY (emp_id) REFERENCES Employees(emp_id) ON DELETE RESTRICT,

    UNIQUE KEY uq_att_emp_date (emp_id, date)
               COMMENT 'Database-level duplicate prevention',
    INDEX idx_att_emp_date     (emp_id, date)   COMMENT 'Primary payroll filter',
    INDEX idx_att_date         (date)            COMMENT 'Daily report scans',
    INDEX idx_att_emp_status   (emp_id, status)  COMMENT 'Status-based per-employee queries'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Daily attendance — extended with time-tracking and auto-computed overtime';


-- ---------------------------------------------------------------------------
-- Table: Salary_Report  (v1.0 preserved for backward compatibility)
-- ---------------------------------------------------------------------------
CREATE TABLE Salary_Report (
    report_id    INT           AUTO_INCREMENT PRIMARY KEY,
    emp_id       INT           NOT NULL,
    month        VARCHAR(7)    NOT NULL COMMENT 'YYYY-MM format',
    total_salary DECIMAL(10,2) NULL     COMMENT 'Net salary for the month',
    generated_on DATE          NOT NULL DEFAULT (CURRENT_DATE),

    FOREIGN KEY (emp_id) REFERENCES Employees(emp_id) ON DELETE RESTRICT,

    UNIQUE KEY uq_salrpt_emp_month (emp_id, month),
    INDEX idx_salrpt_month         (month)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Monthly salary summary — v1.0 table preserved; detail in Payslip table';


-- ============================================================================
-- SECTION 3 — ENTERPRISE EXTENSION TABLES
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Table: Employee_Salary_History
-- Append-only — auto-populated by trg_after_salary_update
-- ---------------------------------------------------------------------------
CREATE TABLE Employee_Salary_History (
    history_id     INT           AUTO_INCREMENT PRIMARY KEY,
    emp_id         INT           NOT NULL,
    old_basic_pay  DECIMAL(10,2) NULL,
    new_basic_pay  DECIMAL(10,2) NULL,
    old_hra        DECIMAL(10,2) NULL,
    new_hra        DECIMAL(10,2) NULL,
    old_da         DECIMAL(10,2) NULL,
    new_da         DECIMAL(10,2) NULL,
    old_medical    DECIMAL(10,2) NULL,
    new_medical    DECIMAL(10,2) NULL,
    old_special    DECIMAL(10,2) NULL,
    new_special    DECIMAL(10,2) NULL,
    effective_date DATE          NOT NULL,
    changed_by     INT           NULL
                   COMMENT 'FK to Users — from @current_user_id session variable',
    changed_at     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reason         VARCHAR(255)  NULL
                   COMMENT 'From @salary_change_reason session variable',

    FOREIGN KEY (emp_id)     REFERENCES Employees(emp_id) ON DELETE RESTRICT,
    FOREIGN KEY (changed_by) REFERENCES Users(user_id)    ON DELETE SET NULL,

    INDEX idx_salh_emp     (emp_id),
    INDEX idx_salh_changed (changed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Immutable salary change log — auto-populated by AFTER UPDATE trigger';


-- ---------------------------------------------------------------------------
-- Table: Audit_Log
-- Centralised append-only audit trail; JSON columns allow schema-free logging
-- ---------------------------------------------------------------------------
CREATE TABLE Audit_Log (
    log_id     INT          AUTO_INCREMENT PRIMARY KEY,
    table_name VARCHAR(50)  NOT NULL COMMENT 'Source table name',
    operation  ENUM('INSERT','UPDATE','DELETE') NOT NULL,
    record_id  INT          NULL COMMENT 'PK of affected row in source table',
    emp_id     INT          NULL COMMENT 'Denormalized for fast employee-centric queries',
    changed_by INT          NULL COMMENT 'FK to Users via @current_user_id',
    old_values JSON         NULL COMMENT 'Previous state as JSON — NULL for INSERT',
    new_values JSON         NULL COMMENT 'New state as JSON — NULL for DELETE',
    changed_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    remarks    VARCHAR(255) NULL,

    INDEX idx_audit_emp      (emp_id),
    INDEX idx_audit_table    (table_name),
    INDEX idx_audit_time     (changed_at),
    INDEX idx_audit_op_table (operation, table_name),
    INDEX idx_audit_by_time  (changed_by, changed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Central audit trail — append-only record of all critical DML with JSON diffs';


-- ---------------------------------------------------------------------------
-- Table: Payroll_Config
-- All payroll calculation parameters — nothing hardcoded in procedures
-- ---------------------------------------------------------------------------
CREATE TABLE Payroll_Config (
    config_id    INT          AUTO_INCREMENT PRIMARY KEY,
    config_key   VARCHAR(100) NOT NULL UNIQUE,
    config_value VARCHAR(255) NOT NULL,
    data_type    ENUM('INT','DECIMAL','STRING','BOOLEAN') NOT NULL DEFAULT 'DECIMAL',
    description  VARCHAR(500) NULL,
    updated_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_cfg_key (config_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Payroll engine configuration — PF%, PT slabs, bonus%, overtime rate, working days';


-- ---------------------------------------------------------------------------
-- Table: Payslip
-- Authoritative monthly payslip record
-- Workflow: Pending -> Processed -> Approved (or Rejected)
-- ---------------------------------------------------------------------------
CREATE TABLE Payslip (
    payslip_id           INT           AUTO_INCREMENT PRIMARY KEY,
    emp_id               INT           NOT NULL,
    month                TINYINT       NOT NULL COMMENT '1 to 12',
    year                 YEAR          NOT NULL,
    -- Earnings
    basic_pay            DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    hra                  DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    da                   DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    medical_allowance    DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    special_allowance    DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    bonus                DECIMAL(10,2) NOT NULL DEFAULT 0.00
                         COMMENT '8.33% of basic per Payment of Bonus Act',
    overtime_pay         DECIMAL(10,2) NOT NULL DEFAULT 0.00
                         COMMENT 'overtime_hours x overtime_rate_per_hour (config)',
    gross_salary         DECIMAL(10,2) NOT NULL DEFAULT 0.00
                         COMMENT 'Sum of all earnings: basic+HRA+DA+medical+special+bonus+OT',
    -- Deductions
    pf_deduction         DECIMAL(10,2) NOT NULL DEFAULT 0.00
                         COMMENT '12% of basic per EPF Act',
    professional_tax     DECIMAL(10,2) NOT NULL DEFAULT 0.00
                         COMMENT 'Slab-based via fn_calc_professional_tax()',
    income_tax           DECIMAL(10,2) NOT NULL DEFAULT 0.00
                         COMMENT 'Simplified TDS: income_tax_percentage% of gross',
    loss_of_pay          DECIMAL(10,2) NOT NULL DEFAULT 0.00
                         COMMENT 'absent_days x (basic / working_days_per_month)',
    other_deductions     DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    total_deductions     DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    -- Net
    net_salary           DECIMAL(10,2) NOT NULL DEFAULT 0.00
                         COMMENT 'net_salary = gross_salary - total_deductions',
    -- Attendance snapshot
    total_working_days   INT           NOT NULL DEFAULT 0,
    days_present         INT           NOT NULL DEFAULT 0,
    days_absent          INT           NOT NULL DEFAULT 0,
    days_late            INT           NOT NULL DEFAULT 0,
    overtime_hours_total DECIMAL(6,2)  NOT NULL DEFAULT 0.00,
    -- Workflow
    status               ENUM('Pending','Processed','Approved','Rejected')
                         NOT NULL DEFAULT 'Pending',
    generated_by         INT           NULL COMMENT 'FK to Users',
    generated_on         TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    approved_by          INT           NULL COMMENT 'FK to Users',
    approved_on          TIMESTAMP     NULL,
    rejection_reason     VARCHAR(255)  NULL,

    FOREIGN KEY (emp_id)       REFERENCES Employees(emp_id) ON DELETE RESTRICT,
    FOREIGN KEY (generated_by) REFERENCES Users(user_id)    ON DELETE SET NULL,
    FOREIGN KEY (approved_by)  REFERENCES Users(user_id)    ON DELETE SET NULL,

    UNIQUE KEY uq_payslip_emp_month_year (emp_id, month, year)
               COMMENT 'Exactly one payslip per employee per month',
    INDEX idx_ps_emp_year   (emp_id, year),
    INDEX idx_ps_month_year (year, month),
    INDEX idx_ps_status     (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Monthly payslip — authoritative payroll record with full earnings/deductions breakdown';


-- ---------------------------------------------------------------------------
-- Table: Notifications
-- Simulates push/email alerts using a DB table
-- ---------------------------------------------------------------------------
CREATE TABLE Notifications (
    notif_id   INT          AUTO_INCREMENT PRIMARY KEY,
    user_id    INT          NULL COMMENT 'NULL = broadcast to all Admin/HR',
    title      VARCHAR(100) NOT NULL,
    message    TEXT         NOT NULL,
    type       ENUM('INFO','WARNING','ALERT','REMINDER') NOT NULL DEFAULT 'INFO',
    is_read    TINYINT(1)   NOT NULL DEFAULT 0,
    created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE,

    INDEX idx_notif_user    (user_id, is_read),
    INDEX idx_notif_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='In-system notifications — simulates push/email for payroll and leave events';


-- ============================================================================
-- SECTION 4 — LEAVE MANAGEMENT TABLES
-- ============================================================================

CREATE TABLE Leave_Types (
    leave_type_id INT          AUTO_INCREMENT PRIMARY KEY,
    leave_name    VARCHAR(50)  NOT NULL UNIQUE,
    max_days      INT          NOT NULL DEFAULT 0,
    is_paid       TINYINT(1)   NOT NULL DEFAULT 1 COMMENT '0=unpaid, LOP applies',
    carry_forward TINYINT(1)   NOT NULL DEFAULT 0 COMMENT '1=unused days roll to next year',
    description   VARCHAR(255) NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Leave type master — categories, annual entitlements, and policies';


CREATE TABLE Leave_Balance (
    balance_id    INT  AUTO_INCREMENT PRIMARY KEY,
    emp_id        INT  NOT NULL,
    leave_type_id INT  NOT NULL,
    year          YEAR NOT NULL,
    total_leaves  INT  NOT NULL DEFAULT 0,
    used_leaves   INT  NOT NULL DEFAULT 0,

    FOREIGN KEY (emp_id)        REFERENCES Employees(emp_id)          ON DELETE CASCADE,
    FOREIGN KEY (leave_type_id) REFERENCES Leave_Types(leave_type_id) ON DELETE RESTRICT,

    UNIQUE KEY uq_lb          (emp_id, leave_type_id, year),
    INDEX idx_lb_emp_year     (emp_id, year)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Employee leave balance — allocated vs consumed days per type per year';


CREATE TABLE Leave_Requests (
    request_id     INT          AUTO_INCREMENT PRIMARY KEY,
    emp_id         INT          NOT NULL,
    leave_type_id  INT          NOT NULL,
    from_date      DATE         NOT NULL,
    to_date        DATE         NOT NULL,
    days_requested INT          NOT NULL,
    reason         VARCHAR(500) NULL,
    status         ENUM('Pending','Approved','Rejected','Cancelled') NOT NULL DEFAULT 'Pending',
    applied_on     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reviewed_by    INT          NULL COMMENT 'FK to Employees — Manager/HR reviewer',
    reviewed_on    TIMESTAMP    NULL,
    review_note    VARCHAR(255) NULL,

    FOREIGN KEY (emp_id)        REFERENCES Employees(emp_id)          ON DELETE RESTRICT,
    FOREIGN KEY (leave_type_id) REFERENCES Leave_Types(leave_type_id) ON DELETE RESTRICT,
    FOREIGN KEY (reviewed_by)   REFERENCES Employees(emp_id)          ON DELETE SET NULL,

    INDEX idx_lr_emp_status  (emp_id, status),
    INDEX idx_lr_dates       (from_date, to_date),
    INDEX idx_lr_status_time (status, applied_on)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Leave request lifecycle — full workflow from application to approval/rejection';

SET FOREIGN_KEY_CHECKS = 1;


-- ============================================================================
-- SECTION 5 — HELPER FUNCTIONS
-- ============================================================================

DELIMITER //

-- ---------------------------------------------------------------------------
-- fn_get_config  : reads a numeric value from Payroll_Config by key
-- ---------------------------------------------------------------------------
CREATE FUNCTION fn_get_config(p_key VARCHAR(100))
RETURNS DECIMAL(12,4)
READS SQL DATA
NOT DETERMINISTIC
COMMENT 'Returns DECIMAL config value from Payroll_Config; 0 if key not found.'
BEGIN
    DECLARE v_val DECIMAL(12,4) DEFAULT 0;
    SELECT CAST(config_value AS DECIMAL(12,4)) INTO v_val
    FROM   Payroll_Config WHERE config_key = p_key LIMIT 1;
    RETURN IFNULL(v_val, 0);
END //


-- ---------------------------------------------------------------------------
-- fn_calc_professional_tax : slab-based PT driven by Payroll_Config
-- Config keys : pt_slab1_limit, pt_slab2_limit, pt_slab1_tax,
--               pt_slab2_tax, pt_slab3_tax
-- ---------------------------------------------------------------------------
CREATE FUNCTION fn_calc_professional_tax(p_gross DECIMAL(10,2))
RETURNS DECIMAL(10,2)
READS SQL DATA
NOT DETERMINISTIC
COMMENT 'Slab-based professional tax; all slab values read from Payroll_Config.'
BEGIN
    DECLARE v_s1_lim DECIMAL(10,2);
    DECLARE v_s2_lim DECIMAL(10,2);
    DECLARE v_s1_tax DECIMAL(10,2);
    DECLARE v_s2_tax DECIMAL(10,2);
    DECLARE v_s3_tax DECIMAL(10,2);

    SET v_s1_lim = fn_get_config('pt_slab1_limit');
    SET v_s2_lim = fn_get_config('pt_slab2_limit');
    SET v_s1_tax = fn_get_config('pt_slab1_tax');
    SET v_s2_tax = fn_get_config('pt_slab2_tax');
    SET v_s3_tax = fn_get_config('pt_slab3_tax');

    IF    p_gross <= v_s1_lim THEN RETURN v_s1_tax;
    ELSEIF p_gross <= v_s2_lim THEN RETURN v_s2_tax;
    ELSE                             RETURN v_s3_tax;
    END IF;
END //


-- ---------------------------------------------------------------------------
-- fn_has_permission : hierarchical RBAC check
-- Hierarchy : Admin > HR > Manager > Employee
-- Returns 1 if user role >= p_min_role, else 0
-- ---------------------------------------------------------------------------
CREATE FUNCTION fn_has_permission(p_user_id INT, p_min_role VARCHAR(20))
RETURNS TINYINT(1)
READS SQL DATA
NOT DETERMINISTIC
COMMENT 'Returns 1 if user holds role >= p_min_role in the RBAC hierarchy.'
BEGIN
    DECLARE v_role   VARCHAR(20);
    DECLARE v_active TINYINT(1);

    SELECT role, is_active INTO v_role, v_active
    FROM   Users WHERE user_id = p_user_id LIMIT 1;

    IF v_role IS NULL OR v_active = 0 THEN RETURN 0; END IF;
    IF v_role = 'Admin'       THEN RETURN 1; END IF;
    IF p_min_role = 'Admin'   THEN RETURN 0; END IF;
    IF v_role = 'HR'          THEN RETURN 1; END IF;
    IF p_min_role = 'HR'      THEN RETURN 0; END IF;
    IF v_role = 'Manager'     THEN RETURN 1; END IF;
    IF p_min_role = 'Manager' THEN RETURN 0; END IF;
    RETURN 1;
END //

DELIMITER ;


-- ============================================================================
-- SECTION 6 — TRIGGERS
-- ============================================================================

DELIMITER //

-- ── Employee_Salary ──────────────────────────────────────────────────────────

-- Validates basic_pay > 0 and allowances >= 0 on INSERT
CREATE TRIGGER trg_before_salary_insert
BEFORE INSERT ON Employee_Salary FOR EACH ROW
BEGIN
    IF NEW.basic_pay <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Validation: basic_pay must be > 0';
    END IF;
    IF NEW.hra < 0 OR NEW.da < 0 OR NEW.medical_allowance < 0 OR NEW.special_allowance < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Validation: Allowances cannot be negative';
    END IF;
    IF NEW.effective_from IS NULL THEN SET NEW.effective_from = CURDATE(); END IF;
END //


-- Validates updated salary values before applying the change
CREATE TRIGGER trg_before_salary_update
BEFORE UPDATE ON Employee_Salary FOR EACH ROW
BEGIN
    IF NEW.basic_pay <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Validation: basic_pay must be > 0';
    END IF;
    IF NEW.hra < 0 OR NEW.da < 0 OR NEW.medical_allowance < 0 OR NEW.special_allowance < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Validation: Allowances cannot be negative';
    END IF;
END //


-- Auto-inserts Employee_Salary_History + Audit_Log on every salary UPDATE
-- Uses @current_user_id and @salary_change_reason session variables
CREATE TRIGGER trg_after_salary_update
AFTER UPDATE ON Employee_Salary FOR EACH ROW
BEGIN
    INSERT INTO Employee_Salary_History (
        emp_id,
        old_basic_pay, new_basic_pay, old_hra, new_hra,
        old_da, new_da, old_medical, new_medical, old_special, new_special,
        effective_date, changed_by, reason
    ) VALUES (
        NEW.emp_id,
        OLD.basic_pay, NEW.basic_pay, OLD.hra, NEW.hra,
        OLD.da, NEW.da, OLD.medical_allowance, NEW.medical_allowance,
        OLD.special_allowance, NEW.special_allowance,
        CURDATE(), @current_user_id, @salary_change_reason
    );
    INSERT INTO Audit_Log (table_name, operation, record_id, emp_id, changed_by, old_values, new_values)
    VALUES (
        'Employee_Salary', 'UPDATE', NEW.sal_id, NEW.emp_id, @current_user_id,
        JSON_OBJECT('basic_pay', OLD.basic_pay, 'hra', OLD.hra, 'da', OLD.da,
                    'medical_allowance', OLD.medical_allowance,
                    'special_allowance', OLD.special_allowance),
        JSON_OBJECT('basic_pay', NEW.basic_pay, 'hra', NEW.hra, 'da', NEW.da,
                    'medical_allowance', NEW.medical_allowance,
                    'special_allowance', NEW.special_allowance,
                    'effective_from', NEW.effective_from)
    );
END //


-- ── Attendance ───────────────────────────────────────────────────────────────

-- Auto-determines Late status; auto-computes working_hours and overtime_hours
CREATE TRIGGER trg_before_attendance_insert
BEFORE INSERT ON Attendance FOR EACH ROW
BEGIN
    DECLARE v_std_hours      DECIMAL(4,2);
    DECLARE v_late_threshold INT;

    IF NEW.check_in IS NOT NULL AND NEW.status = 'Present' THEN
        SET v_late_threshold = CAST(fn_get_config('late_arrival_threshold_minutes') AS UNSIGNED);
        IF (HOUR(NEW.check_in) * 60 + MINUTE(NEW.check_in)) > (9 * 60 + v_late_threshold) THEN
            SET NEW.status = 'Late';
        END IF;
    END IF;

    IF NEW.check_in IS NOT NULL AND NEW.check_out IS NOT NULL THEN
        SET NEW.working_hours  = ROUND(TIME_TO_SEC(TIMEDIFF(NEW.check_out, NEW.check_in)) / 3600.0, 2);
        SET v_std_hours        = fn_get_config('standard_work_hours');
        SET NEW.overtime_hours = GREATEST(0, ROUND(NEW.working_hours - v_std_hours, 2));
    END IF;
END //


-- Recalculates working_hours and overtime_hours when check_out is updated
CREATE TRIGGER trg_before_attendance_update
BEFORE UPDATE ON Attendance FOR EACH ROW
BEGIN
    DECLARE v_std_hours DECIMAL(4,2);
    IF NEW.check_in IS NOT NULL AND NEW.check_out IS NOT NULL THEN
        SET NEW.working_hours  = ROUND(TIME_TO_SEC(TIMEDIFF(NEW.check_out, NEW.check_in)) / 3600.0, 2);
        SET v_std_hours        = fn_get_config('standard_work_hours');
        SET NEW.overtime_hours = GREATEST(0, ROUND(NEW.working_hours - v_std_hours, 2));
    END IF;
END //


-- Writes attendance INSERT event to Audit_Log
CREATE TRIGGER trg_after_attendance_insert
AFTER INSERT ON Attendance FOR EACH ROW
BEGIN
    INSERT INTO Audit_Log (table_name, operation, record_id, emp_id, changed_by, new_values)
    VALUES (
        'Attendance', 'INSERT', NEW.att_id, NEW.emp_id, @current_user_id,
        JSON_OBJECT('date', NEW.date, 'status', NEW.status,
                    'check_in', NEW.check_in, 'check_out', NEW.check_out,
                    'working_hours', NEW.working_hours, 'overtime_hours', NEW.overtime_hours)
    );
END //


-- ── Employees ────────────────────────────────────────────────────────────────

-- Logs employee record modifications to Audit_Log
CREATE TRIGGER trg_after_employee_update
AFTER UPDATE ON Employees FOR EACH ROW
BEGIN
    INSERT INTO Audit_Log (table_name, operation, record_id, emp_id, changed_by, old_values, new_values)
    VALUES (
        'Employees', 'UPDATE', NEW.emp_id, NEW.emp_id, @current_user_id,
        JSON_OBJECT('name', OLD.name, 'department', OLD.department,
                    'designation', OLD.designation, 'status', OLD.status),
        JSON_OBJECT('name', NEW.name, 'department', NEW.department,
                    'designation', NEW.designation, 'status', NEW.status)
    );
END //


-- Blocks hard-delete when employee has pending payslips or leave requests
-- Use status = 'Terminated' for soft-delete instead
CREATE TRIGGER trg_before_employee_delete
BEFORE DELETE ON Employees FOR EACH ROW
BEGIN
    DECLARE v_payslip_count INT DEFAULT 0;
    DECLARE v_leave_count   INT DEFAULT 0;

    SELECT COUNT(*) INTO v_payslip_count
    FROM   Payslip WHERE emp_id = OLD.emp_id AND status IN ('Pending','Processed');

    SELECT COUNT(*) INTO v_leave_count
    FROM   Leave_Requests WHERE emp_id = OLD.emp_id AND status = 'Pending';

    IF v_payslip_count > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Delete blocked: Unprocessed payslips exist. Use status=Terminated.';
    END IF;
    IF v_leave_count > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Delete blocked: Pending leave requests exist. Resolve first.';
    END IF;
END //


-- ── Leave_Requests ───────────────────────────────────────────────────────────

-- Validates approval: blocks re-approval and checks leave balance
CREATE TRIGGER trg_before_leave_update
BEFORE UPDATE ON Leave_Requests FOR EACH ROW
BEGIN
    DECLARE v_remaining INT DEFAULT 0;

    IF OLD.status = 'Approved' AND NEW.status = 'Approved' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Validation: Leave request is already Approved';
    END IF;

    IF NEW.status = 'Approved' AND OLD.status = 'Pending' THEN
        SELECT (total_leaves - used_leaves) INTO v_remaining
        FROM   Leave_Balance
        WHERE  emp_id = NEW.emp_id AND leave_type_id = NEW.leave_type_id
          AND  year   = YEAR(NEW.from_date) LIMIT 1;

        IF v_remaining IS NULL OR v_remaining < NEW.days_requested THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Approval blocked: Insufficient leave balance';
        END IF;
    END IF;

    IF NEW.status != OLD.status THEN SET NEW.reviewed_on = NOW(); END IF;
END //


-- Deducts balance when Approved; restores on reversal; writes Audit_Log
CREATE TRIGGER trg_after_leave_update
AFTER UPDATE ON Leave_Requests FOR EACH ROW
BEGIN
    IF NEW.status = 'Approved' AND OLD.status = 'Pending' THEN
        UPDATE Leave_Balance
        SET    used_leaves = used_leaves + NEW.days_requested
        WHERE  emp_id = NEW.emp_id AND leave_type_id = NEW.leave_type_id
          AND  year   = YEAR(NEW.from_date);
    END IF;

    IF NEW.status = 'Rejected' AND OLD.status = 'Approved' THEN
        UPDATE Leave_Balance
        SET    used_leaves = GREATEST(0, used_leaves - OLD.days_requested)
        WHERE  emp_id = OLD.emp_id AND leave_type_id = OLD.leave_type_id
          AND  year   = YEAR(OLD.from_date);
    END IF;

    INSERT INTO Audit_Log (table_name, operation, record_id, emp_id, changed_by, old_values, new_values)
    VALUES (
        'Leave_Requests', 'UPDATE', NEW.request_id, NEW.emp_id, @current_user_id,
        JSON_OBJECT('status', OLD.status),
        JSON_OBJECT('status', NEW.status, 'reviewed_by', NEW.reviewed_by,
                    'review_note', NEW.review_note)
    );
END //


-- ── Payslip ──────────────────────────────────────────────────────────────────

-- Logs payroll status transitions (Processed -> Approved, etc.) to Audit_Log
CREATE TRIGGER trg_after_payslip_update
AFTER UPDATE ON Payslip FOR EACH ROW
BEGIN
    IF NEW.status != OLD.status THEN
        INSERT INTO Audit_Log (table_name, operation, record_id, emp_id, changed_by, old_values, new_values)
        VALUES (
            'Payslip', 'UPDATE', NEW.payslip_id, NEW.emp_id, @current_user_id,
            JSON_OBJECT('status', OLD.status),
            JSON_OBJECT('status', NEW.status, 'approved_by', NEW.approved_by,
                        'approved_on', NEW.approved_on)
        );
    END IF;
END //

DELIMITER ;


-- ============================================================================
-- SECTION 7 — VIEWS
-- ============================================================================

-- Employee full profile: Employees + Employee_Details + Employee_Salary + Users
CREATE OR REPLACE VIEW Employee_Profile_View AS
SELECT
    e.emp_id, e.name, e.department, e.designation, e.emp_type, e.status,
    ed.fname, ed.lname, ed.gender, ed.dob, ed.hire_date,
    TIMESTAMPDIFF(YEAR, ed.hire_date, CURDATE()) AS years_of_service,
    ed.email, ed.phone, ed.city, ed.state, ed.country,
    es.basic_pay, es.hra, es.da, es.medical_allowance, es.special_allowance,
    (es.basic_pay + es.hra + es.da + es.medical_allowance + es.special_allowance) AS ctc_monthly,
    es.effective_from AS salary_effective_from,
    u.username, u.role AS system_role, u.last_login,
    mgr.name AS manager_name
FROM  Employees       e
JOIN  Employee_Details ed  ON e.emp_id    = ed.emp_id
JOIN  Employee_Salary  es  ON e.emp_id    = es.emp_id
JOIN  Users            u   ON e.user_id   = u.user_id
LEFT JOIN Employees    mgr ON e.manager_id = mgr.emp_id;


-- Full payslip detail with employee name, department, and approver metadata
CREATE OR REPLACE VIEW Monthly_Payroll_View AS
SELECT
    p.payslip_id, p.emp_id,
    e.name AS employee_name, e.department, e.designation,
    CONCAT(p.year, '-', LPAD(p.month, 2, '0')) AS payroll_period,
    p.basic_pay, p.hra, p.da, p.medical_allowance, p.special_allowance,
    p.bonus, p.overtime_pay, p.gross_salary,
    p.pf_deduction, p.professional_tax, p.income_tax,
    p.loss_of_pay, p.other_deductions, p.total_deductions, p.net_salary,
    p.days_present, p.days_absent, p.days_late, p.overtime_hours_total,
    p.status AS payroll_status,
    gu.username AS generated_by, p.generated_on,
    au.username AS approved_by,  p.approved_on
FROM  Payslip    p
JOIN  Employees  e   ON p.emp_id       = e.emp_id
LEFT JOIN Users  gu  ON p.generated_by = gu.user_id
LEFT JOIN Users  au  ON p.approved_by  = au.user_id;


-- Monthly attendance counts and attendance percentage per employee
CREATE OR REPLACE VIEW Attendance_Summary_View AS
SELECT
    a.emp_id, e.name AS employee_name, e.department,
    YEAR(a.date) AS year, MONTH(a.date) AS month, MONTHNAME(a.date) AS month_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN a.status IN ('Present','Late','Half-Day') THEN 1 ELSE 0 END) AS days_present,
    SUM(CASE WHEN a.status = 'Absent'   THEN 1 ELSE 0 END) AS days_absent,
    SUM(CASE WHEN a.status = 'Late'     THEN 1 ELSE 0 END) AS days_late,
    SUM(CASE WHEN a.status = 'On-Leave' THEN 1 ELSE 0 END) AS days_on_leave,
    ROUND(SUM(IFNULL(a.working_hours,  0)), 2) AS total_working_hours,
    ROUND(SUM(IFNULL(a.overtime_hours, 0)), 2) AS total_overtime_hours,
    ROUND(SUM(CASE WHEN a.status IN ('Present','Late','Half-Day') THEN 1 ELSE 0 END)
          * 100.0 / NULLIF(COUNT(*), 0), 2)    AS attendance_pct
FROM  Attendance a
JOIN  Employees  e ON a.emp_id = e.emp_id
GROUP BY a.emp_id, e.name, e.department, YEAR(a.date), MONTH(a.date);


-- Department-level payroll cost aggregation for executive dashboards
CREATE OR REPLACE VIEW Department_Expense_View AS
SELECT
    e.department,
    CONCAT(p.year, '-', LPAD(p.month, 2, '0')) AS payroll_period,
    COUNT(DISTINCT p.emp_id)                    AS headcount,
    ROUND(SUM(p.gross_salary),     2)           AS total_gross,
    ROUND(SUM(p.total_deductions), 2)           AS total_deductions,
    ROUND(SUM(p.net_salary),       2)           AS total_net_salary,
    ROUND(AVG(p.net_salary),       2)           AS avg_net_salary,
    ROUND(MAX(p.net_salary),       2)           AS max_salary,
    ROUND(MIN(p.net_salary),       2)           AS min_salary
FROM  Payslip    p
JOIN  Employees  e ON p.emp_id = e.emp_id
WHERE p.status IN ('Processed', 'Approved')
GROUP BY e.department, p.year, p.month;


-- Employee leave balance: allocated vs consumed per type per year
CREATE OR REPLACE VIEW Leave_Balance_View AS
SELECT
    lb.emp_id, e.name AS employee_name, e.department,
    lt.leave_name, lt.is_paid, lt.carry_forward,
    lb.year, lb.total_leaves, lb.used_leaves,
    (lb.total_leaves - lb.used_leaves) AS remaining_leaves
FROM  Leave_Balance lb
JOIN  Employees     e  ON lb.emp_id        = e.emp_id
JOIN  Leave_Types   lt ON lb.leave_type_id = lt.leave_type_id;


-- Top earners in the most recent processed payroll period
-- Uses MySQL 8.0+ window functions: RANK() OVER (...)
CREATE OR REPLACE VIEW Top_Earners_View AS
SELECT
    p.emp_id, e.name AS employee_name, e.department, e.designation,
    p.gross_salary, p.net_salary,
    CONCAT(p.year, '-', LPAD(p.month, 2, '0'))         AS payroll_period,
    RANK() OVER (ORDER BY p.net_salary DESC)            AS overall_rank,
    RANK() OVER (PARTITION BY e.department ORDER BY p.net_salary DESC) AS dept_rank
FROM  Payslip    p
JOIN  Employees  e ON p.emp_id = e.emp_id
WHERE p.status IN ('Processed', 'Approved')
  AND (p.year, p.month) = (
      SELECT year, month FROM Payslip
      WHERE  status IN ('Processed','Approved')
      ORDER  BY year DESC, month DESC LIMIT 1
  );


-- ============================================================================
-- SECTION 8 — STORED PROCEDURES
-- ============================================================================

DELIMITER //

-- ── A. Authentication ────────────────────────────────────────────────────────

-- sp_authenticate_user
-- SHA-256 credential check; updates last_login on success; rejects inactive accounts
CREATE PROCEDURE sp_authenticate_user(
    IN  p_username VARCHAR(50),
    IN  p_password VARCHAR(255),
    OUT p_user_id  INT,
    OUT p_role     VARCHAR(20),
    OUT p_message  VARCHAR(255)
)
BEGIN
    DECLARE v_hash   VARCHAR(64);
    DECLARE v_active TINYINT(1);
    SET p_user_id = NULL; SET p_role = NULL;

    SELECT user_id, password_hash, role, is_active
    INTO   p_user_id, v_hash, p_role, v_active
    FROM   Users WHERE username = p_username LIMIT 1;

    IF p_user_id IS NULL THEN
        SET p_message = 'Authentication failed: Username not found';
        SET p_user_id = NULL; SET p_role = NULL;
    ELSEIF v_active = 0 THEN
        SET p_message = 'Authentication failed: Account deactivated';
        SET p_user_id = NULL; SET p_role = NULL;
    ELSEIF v_hash != SHA2(p_password, 256) THEN
        SET p_message = 'Authentication failed: Invalid password';
        SET p_user_id = NULL; SET p_role = NULL;
    ELSE
        UPDATE Users SET last_login = NOW() WHERE user_id = p_user_id;
        SET @current_user_id = p_user_id;
        SET p_message = 'Authentication successful';
    END IF;
END //


-- sp_register_user : creates a new user with hashed password
-- Only Admin can assign non-Employee roles
CREATE PROCEDURE sp_register_user(
    IN  p_calling_user_id INT,
    IN  p_username        VARCHAR(50),
    IN  p_password        VARCHAR(255),
    IN  p_role            VARCHAR(20),
    OUT p_new_user_id     INT,
    OUT p_message         VARCHAR(255)
)
BEGIN
    IF p_role != 'Employee' AND NOT fn_has_permission(p_calling_user_id, 'Admin') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Access Denied: Only Admin can create non-Employee accounts';
    END IF;
    IF EXISTS (SELECT 1 FROM Users WHERE username = p_username) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: Username already exists';
    END IF;
    INSERT INTO Users (username, password_hash, role)
    VALUES (p_username, SHA2(p_password, 256), p_role);
    SET p_new_user_id = LAST_INSERT_ID();
    SET p_message     = CONCAT('User registered. user_id = ', p_new_user_id);
END //


-- ── B. Employee Onboarding ───────────────────────────────────────────────────

-- sp_add_employee : atomic onboarding inside a single transaction
-- Creates: User, Employee, Employee_Details, Employee_Salary, Leave_Balance
-- RBAC: Admin or HR only
CREATE PROCEDURE sp_add_employee(
    IN  p_calling_user_id INT,
    IN  p_username        VARCHAR(50),
    IN  p_password        VARCHAR(255),
    IN  p_name            VARCHAR(100),
    IN  p_department      VARCHAR(50),
    IN  p_designation     VARCHAR(100),
    IN  p_emp_type        VARCHAR(20),
    IN  p_fname           VARCHAR(50),
    IN  p_lname           VARCHAR(50),
    IN  p_gender          VARCHAR(10),
    IN  p_dob             DATE,
    IN  p_hire_date       DATE,
    IN  p_email           VARCHAR(100),
    IN  p_phone           VARCHAR(15),
    IN  p_basic_pay       DECIMAL(10,2),
    IN  p_hra             DECIMAL(10,2),
    IN  p_da              DECIMAL(10,2),
    IN  p_medical         DECIMAL(10,2),
    IN  p_special         DECIMAL(10,2),
    IN  p_manager_id      INT,
    OUT p_new_emp_id      INT,
    OUT p_message         VARCHAR(255)
)
BEGIN
    DECLARE v_new_user_id INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 p_message = MESSAGE_TEXT;
        SET p_new_emp_id = NULL;
    END;

    IF NOT fn_has_permission(p_calling_user_id, 'HR') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Access Denied: Only Admin or HR can onboard employees';
    END IF;
    IF p_basic_pay IS NULL OR p_basic_pay <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Validation: basic_pay must be > 0';
    END IF;
    IF p_email IS NULL OR p_email = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Validation: Email is required';
    END IF;

    SET @current_user_id = p_calling_user_id;

    START TRANSACTION;
        INSERT INTO Users (username, password_hash, role)
        VALUES (p_username, SHA2(p_password, 256), 'Employee');
        SET v_new_user_id = LAST_INSERT_ID();

        INSERT INTO Employees (user_id, name, department, designation, emp_type, manager_id)
        VALUES (v_new_user_id, p_name, p_department, p_designation, p_emp_type, p_manager_id);
        SET p_new_emp_id = LAST_INSERT_ID();

        INSERT INTO Employee_Details (emp_id, fname, lname, gender, dob, hire_date, email, phone)
        VALUES (p_new_emp_id, p_fname, p_lname, p_gender, p_dob, p_hire_date, p_email, p_phone);

        -- trg_before_salary_insert validates basic_pay > 0
        INSERT INTO Employee_Salary (emp_id, basic_pay, hra, da, medical_allowance, special_allowance)
        VALUES (p_new_emp_id, p_basic_pay, p_hra, p_da, p_medical, p_special);

        -- Initialise leave balance for every defined leave type
        INSERT INTO Leave_Balance (emp_id, leave_type_id, year, total_leaves, used_leaves)
        SELECT p_new_emp_id, leave_type_id, YEAR(CURDATE()), max_days, 0 FROM Leave_Types;

        INSERT INTO Audit_Log (table_name, operation, record_id, emp_id, changed_by, new_values, remarks)
        VALUES ('Employees', 'INSERT', p_new_emp_id, p_new_emp_id, p_calling_user_id,
                JSON_OBJECT('name', p_name, 'department', p_department,
                            'designation', p_designation, 'email', p_email,
                            'hire_date', p_hire_date),
                'Onboarded via sp_add_employee');
    COMMIT;
    SET p_message = CONCAT('Employee onboarded successfully. emp_id = ', p_new_emp_id);
END //


-- ── C. Salary Management ─────────────────────────────────────────────────────

-- sp_update_salary : RBAC + transaction + trigger-based history logging
-- RBAC: Admin or HR
CREATE PROCEDURE sp_update_salary(
    IN  p_calling_user_id INT,
    IN  p_emp_id          INT,
    IN  p_basic_pay       DECIMAL(10,2),
    IN  p_hra             DECIMAL(10,2),
    IN  p_da              DECIMAL(10,2),
    IN  p_medical         DECIMAL(10,2),
    IN  p_special         DECIMAL(10,2),
    IN  p_reason          VARCHAR(255),
    OUT p_message         VARCHAR(255)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 p_message = MESSAGE_TEXT;
    END;

    IF NOT fn_has_permission(p_calling_user_id, 'HR') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Access Denied: Only Admin or HR can update salaries';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM Employees WHERE emp_id = p_emp_id AND status = 'Active') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Validation: Active employee not found';
    END IF;

    -- Session variables read by trg_after_salary_update
    SET @current_user_id      = p_calling_user_id;
    SET @salary_change_reason = p_reason;

    START TRANSACTION;
        -- trg_after_salary_update fires here -> inserts history + audit log
        UPDATE Employee_Salary
        SET basic_pay         = IFNULL(p_basic_pay, basic_pay),
            hra               = IFNULL(p_hra,       hra),
            da                = IFNULL(p_da,        da),
            medical_allowance = IFNULL(p_medical,   medical_allowance),
            special_allowance = IFNULL(p_special,   special_allowance),
            effective_from    = CURDATE()
        WHERE emp_id = p_emp_id;
    COMMIT;
    SET p_message = CONCAT('Salary updated for emp_id = ', p_emp_id);
END //


-- sp_increment_salary : percentage-based increment with RBAC + history
-- (v1.0 preserved and upgraded with RBAC and trigger-based history)
CREATE PROCEDURE sp_increment_salary(
    IN  p_calling_user_id INT,
    IN  p_emp_id          INT,
    IN  p_percent         DECIMAL(5,2),
    IN  p_reason          VARCHAR(255),
    OUT p_message         VARCHAR(255)
)
BEGIN
    DECLARE v_old_basic DECIMAL(10,2);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 p_message = MESSAGE_TEXT;
    END;

    IF NOT fn_has_permission(p_calling_user_id, 'HR') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Access Denied: Only Admin or HR can apply increments';
    END IF;
    IF p_percent <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Validation: Increment % must be positive';
    END IF;

    SELECT basic_pay INTO v_old_basic FROM Employee_Salary WHERE emp_id = p_emp_id;

    SET @current_user_id      = p_calling_user_id;
    SET @salary_change_reason = CONCAT(p_percent, '% increment — ', IFNULL(p_reason, 'Annual review'));

    START TRANSACTION;
        UPDATE Employee_Salary
        SET basic_pay      = ROUND(basic_pay * (1 + p_percent / 100), 2),
            increments     = increments + ROUND(basic_pay * p_percent / 100, 2),
            effective_from = CURDATE()
        WHERE emp_id = p_emp_id;
    COMMIT;
    SET p_message = CONCAT(p_percent, '% increment applied. emp_id=', p_emp_id,
                           ' | Old basic: ', v_old_basic);
END //


-- ── D. Attendance Management ─────────────────────────────────────────────────

-- sp_add_attendance : replaces legacy add_attendance with RBAC + friendly errors
CREATE PROCEDURE sp_add_attendance(
    IN  p_calling_user_id INT,
    IN  p_emp_id          INT,
    IN  p_date            DATE,
    IN  p_status          VARCHAR(20),
    IN  p_check_in        TIME,
    IN  p_check_out       TIME,
    IN  p_remarks         VARCHAR(255),
    OUT p_message         VARCHAR(255)
)
BEGIN
    DECLARE v_emp_user_id INT DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 p_message = MESSAGE_TEXT;
    END;

    IF NOT fn_has_permission(p_calling_user_id, 'HR') THEN
        SELECT user_id INTO v_emp_user_id FROM Employees WHERE emp_id = p_emp_id;
        IF v_emp_user_id IS NULL OR v_emp_user_id != p_calling_user_id THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Access Denied: You can only submit your own attendance';
        END IF;
    END IF;

    IF EXISTS (SELECT 1 FROM Attendance WHERE emp_id = p_emp_id AND date = p_date) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Duplicate Attendance: Record already exists for this date';
    END IF;

    SET @current_user_id = p_calling_user_id;

    -- trg_before_attendance_insert auto-sets Late status and computes hours
    INSERT INTO Attendance (emp_id, date, status, check_in, check_out, remarks)
    VALUES (p_emp_id, p_date, p_status, p_check_in, p_check_out, p_remarks);

    SET p_message = 'Attendance recorded successfully';
END //


-- sp_check_in : records check-in; trigger auto-marks Late if past threshold
CREATE PROCEDURE sp_check_in(
    IN  p_emp_id  INT,
    IN  p_remarks VARCHAR(255),
    OUT p_message VARCHAR(255)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 p_message = MESSAGE_TEXT;
    END;

    IF EXISTS (SELECT 1 FROM Attendance WHERE emp_id = p_emp_id AND date = CURDATE()) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Already checked in for today';
    END IF;

    INSERT INTO Attendance (emp_id, date, status, check_in, remarks)
    VALUES (p_emp_id, CURDATE(), 'Present', CURTIME(), p_remarks);

    SET p_message = CONCAT('Checked in at ', CURTIME());
END //


-- sp_check_out : records check-out; trigger auto-computes working hours
CREATE PROCEDURE sp_check_out(
    IN  p_emp_id  INT,
    OUT p_message VARCHAR(255)
)
BEGIN
    DECLARE v_check_in TIME DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 p_message = MESSAGE_TEXT;
    END;

    SELECT check_in INTO v_check_in
    FROM   Attendance WHERE emp_id = p_emp_id AND date = CURDATE();

    IF v_check_in IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Check-out Error: No check-in found for today';
    END IF;

    -- trg_before_attendance_update fires here and computes working_hours + overtime_hours
    UPDATE Attendance SET check_out = CURTIME()
    WHERE  emp_id = p_emp_id AND date = CURDATE();

    SET p_message = CONCAT('Checked out at ', CURTIME());
END //


-- ── E. Leave Management ──────────────────────────────────────────────────────

-- sp_apply_for_leave : validates balance then inserts leave request
CREATE PROCEDURE sp_apply_for_leave(
    IN  p_calling_user_id INT,
    IN  p_emp_id          INT,
    IN  p_leave_type_id   INT,
    IN  p_from_date       DATE,
    IN  p_to_date         DATE,
    IN  p_reason          VARCHAR(500),
    OUT p_request_id      INT,
    OUT p_message         VARCHAR(255)
)
BEGIN
    DECLARE v_emp_user_id INT DEFAULT NULL;
    DECLARE v_days        INT DEFAULT 0;
    DECLARE v_remaining   INT DEFAULT 0;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 p_message = MESSAGE_TEXT;
        SET p_request_id = NULL;
    END;

    SELECT user_id INTO v_emp_user_id FROM Employees WHERE emp_id = p_emp_id;
    IF v_emp_user_id != p_calling_user_id AND NOT fn_has_permission(p_calling_user_id, 'HR') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Access Denied: You can only apply for your own leave';
    END IF;
    IF p_to_date < p_from_date THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Validation: to_date cannot be before from_date';
    END IF;

    SET v_days = DATEDIFF(p_to_date, p_from_date) + 1;

    SELECT (total_leaves - used_leaves) INTO v_remaining
    FROM   Leave_Balance
    WHERE  emp_id = p_emp_id AND leave_type_id = p_leave_type_id
      AND  year   = YEAR(p_from_date) LIMIT 1;

    IF v_remaining IS NULL OR v_remaining < v_days THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient Leave Balance';
    END IF;

    SET @current_user_id = p_calling_user_id;

    INSERT INTO Leave_Requests (emp_id, leave_type_id, from_date, to_date, days_requested, reason)
    VALUES (p_emp_id, p_leave_type_id, p_from_date, p_to_date, v_days, p_reason);

    SET p_request_id = LAST_INSERT_ID();
    SET p_message    = CONCAT('Leave request submitted. id=', p_request_id, ' | Days: ', v_days);
END //


-- sp_approve_reject_leave : Manager/HR approves or rejects Pending requests
-- Triggers handle balance deduction and audit logging automatically
CREATE PROCEDURE sp_approve_reject_leave(
    IN  p_calling_user_id INT,
    IN  p_request_id      INT,
    IN  p_action          VARCHAR(10),   -- 'Approve' or 'Reject'
    IN  p_review_note     VARCHAR(255),
    OUT p_message         VARCHAR(255)
)
BEGIN
    DECLARE v_reviewer_emp INT DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 p_message = MESSAGE_TEXT;
    END;

    IF NOT fn_has_permission(p_calling_user_id, 'Manager') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Access Denied: Only Manager, HR, or Admin can review leave';
    END IF;
    IF p_action NOT IN ('Approve','Reject') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Validation: action must be Approve or Reject';
    END IF;

    SELECT emp_id INTO v_reviewer_emp FROM Employees
    WHERE  user_id = p_calling_user_id LIMIT 1;

    SET @current_user_id = p_calling_user_id;

    START TRANSACTION;
        UPDATE Leave_Requests
        SET    status      = IF(p_action = 'Approve', 'Approved', 'Rejected'),
               reviewed_by = v_reviewer_emp,
               review_note = p_review_note
        WHERE  request_id = p_request_id AND status = 'Pending';

        IF ROW_COUNT() = 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error: Request not found or not in Pending status';
        END IF;
    COMMIT;
    SET p_message = CONCAT('Leave request ', p_request_id, ' ', p_action, 'd');
END //


-- ── F. Payroll Engine ────────────────────────────────────────────────────────

-- sp_generate_payslip : CORE PAYROLL ENGINE
--
-- Formula (all % values read from Payroll_Config — no hardcoding):
--   Gross   = Basic + HRA + DA + Medical + Special + Bonus + OT_Pay
--   Bonus   = basic_pay × bonus_percentage%
--   OT_Pay  = overtime_hours × overtime_rate_per_hour
--   PF      = basic_pay × pf_percentage%
--   PT      = fn_calc_professional_tax(gross)   [slab-based]
--   IT      = gross × income_tax_percentage%
--   LOP     = absent_days × (basic_pay / working_days_per_month)
--   Net     = Gross − PF − PT − IT − LOP − Other
--
-- RBAC     : Admin or HR
-- Idempotent: Signals if payslip already exists for emp+month+year
CREATE PROCEDURE sp_generate_payslip(
    IN  p_calling_user_id INT,
    IN  p_emp_id          INT,
    IN  p_month           TINYINT,
    IN  p_year            YEAR,
    OUT p_payslip_id      INT,
    OUT p_message         VARCHAR(255)
)
BEGIN
    DECLARE v_basic    DECIMAL(10,2) DEFAULT 0;
    DECLARE v_hra      DECIMAL(10,2) DEFAULT 0;
    DECLARE v_da       DECIMAL(10,2) DEFAULT 0;
    DECLARE v_medical  DECIMAL(10,2) DEFAULT 0;
    DECLARE v_special  DECIMAL(10,2) DEFAULT 0;
    DECLARE v_bonus    DECIMAL(10,2) DEFAULT 0;
    DECLARE v_ot_pay   DECIMAL(10,2) DEFAULT 0;
    DECLARE v_gross    DECIMAL(10,2) DEFAULT 0;
    DECLARE v_pf       DECIMAL(10,2) DEFAULT 0;
    DECLARE v_pt       DECIMAL(10,2) DEFAULT 0;
    DECLARE v_it       DECIMAL(10,2) DEFAULT 0;
    DECLARE v_lop      DECIMAL(10,2) DEFAULT 0;
    DECLARE v_other    DECIMAL(10,2) DEFAULT 0;
    DECLARE v_tot_ded  DECIMAL(10,2) DEFAULT 0;
    DECLARE v_net      DECIMAL(10,2) DEFAULT 0;
    DECLARE v_present  INT           DEFAULT 0;
    DECLARE v_absent   INT           DEFAULT 0;
    DECLARE v_late     INT           DEFAULT 0;
    DECLARE v_ot_hrs   DECIMAL(6,2)  DEFAULT 0;
    DECLARE v_tot_days INT           DEFAULT 0;
    DECLARE v_pf_pct   DECIMAL(5,2)  DEFAULT 12;
    DECLARE v_bon_pct  DECIMAL(5,2)  DEFAULT 8.33;
    DECLARE v_ot_rate  DECIMAL(8,2)  DEFAULT 150;
    DECLARE v_it_pct   DECIMAL(5,2)  DEFAULT 10;
    DECLARE v_wk_days  INT           DEFAULT 26;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 p_message = MESSAGE_TEXT;
        SET p_payslip_id = NULL;
    END;

    IF NOT fn_has_permission(p_calling_user_id, 'HR') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Access Denied: Only Admin or HR can generate payslips';
    END IF;
    IF EXISTS (SELECT 1 FROM Payslip WHERE emp_id = p_emp_id AND month = p_month AND year = p_year) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Payslip already exists for this period';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM Employees WHERE emp_id = p_emp_id AND status = 'Active') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Payslip Error: Employee is not Active';
    END IF;

    SELECT basic_pay, hra, da, medical_allowance, special_allowance
    INTO   v_basic, v_hra, v_da, v_medical, v_special
    FROM   Employee_Salary WHERE emp_id = p_emp_id;

    SET v_pf_pct  = fn_get_config('pf_percentage');
    SET v_bon_pct = fn_get_config('bonus_percentage');
    SET v_ot_rate = fn_get_config('overtime_rate_per_hour');
    SET v_it_pct  = fn_get_config('income_tax_percentage');
    SET v_wk_days = fn_get_config('working_days_per_month');

    SELECT
        SUM(CASE WHEN status IN ('Present','Late','Half-Day') THEN 1 ELSE 0 END),
        SUM(CASE WHEN status = 'Absent' THEN 1 ELSE 0 END),
        SUM(CASE WHEN status = 'Late'   THEN 1 ELSE 0 END),
        ROUND(SUM(IFNULL(overtime_hours, 0)), 2),
        COUNT(*)
    INTO v_present, v_absent, v_late, v_ot_hrs, v_tot_days
    FROM Attendance
    WHERE emp_id = p_emp_id AND MONTH(date) = p_month AND YEAR(date) = p_year;

    -- Earnings
    SET v_bonus  = ROUND(v_basic * v_bon_pct / 100, 2);
    SET v_ot_pay = ROUND(IFNULL(v_ot_hrs, 0) * v_ot_rate, 2);
    SET v_gross  = v_basic + v_hra + v_da + v_medical + v_special + v_bonus + v_ot_pay;

    -- Deductions
    SET v_pf      = ROUND(v_basic * v_pf_pct / 100, 2);
    SET v_pt      = fn_calc_professional_tax(v_gross);
    SET v_it      = ROUND(v_gross * v_it_pct / 100, 2);
    SET v_lop     = ROUND(IFNULL(v_absent, 0) * (v_basic / v_wk_days), 2);
    SET v_other   = 0;
    SET v_tot_ded = v_pf + v_pt + v_it + v_lop + v_other;
    SET v_net     = GREATEST(0, ROUND(v_gross - v_tot_ded, 2));

    SET @current_user_id = p_calling_user_id;

    START TRANSACTION;
        INSERT INTO Payslip (
            emp_id, month, year,
            basic_pay, hra, da, medical_allowance, special_allowance,
            bonus, overtime_pay, gross_salary,
            pf_deduction, professional_tax, income_tax,
            loss_of_pay, other_deductions, total_deductions, net_salary,
            total_working_days, days_present, days_absent, days_late,
            overtime_hours_total, status, generated_by
        ) VALUES (
            p_emp_id, p_month, p_year,
            v_basic, v_hra, v_da, v_medical, v_special,
            v_bonus, v_ot_pay, v_gross,
            v_pf, v_pt, v_it,
            v_lop, v_other, v_tot_ded, v_net,
            IFNULL(v_tot_days, 0), IFNULL(v_present, 0),
            IFNULL(v_absent,  0), IFNULL(v_late, 0),
            IFNULL(v_ot_hrs,  0), 'Processed', p_calling_user_id
        );
        SET p_payslip_id = LAST_INSERT_ID();

        -- Upsert Salary_Report for v1.0 backward compatibility
        INSERT INTO Salary_Report (emp_id, month, total_salary, generated_on)
        VALUES (p_emp_id, CONCAT(p_year, '-', LPAD(p_month, 2, '0')), v_net, CURDATE())
        ON DUPLICATE KEY UPDATE total_salary = v_net, generated_on = CURDATE();
    COMMIT;

    SET p_message = CONCAT('Payslip id=', p_payslip_id,
                           ' | Gross=', v_gross, ' | Net=', v_net);
END //


-- sp_approve_payroll : promotes Processed -> Approved; RBAC: Admin or HR
CREATE PROCEDURE sp_approve_payroll(
    IN  p_calling_user_id INT,
    IN  p_payslip_id      INT,
    OUT p_message         VARCHAR(255)
)
BEGIN
    DECLARE v_cur_status VARCHAR(20);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 p_message = MESSAGE_TEXT;
    END;

    IF NOT fn_has_permission(p_calling_user_id, 'HR') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Access Denied: Only Admin or HR can approve payroll';
    END IF;

    SELECT status INTO v_cur_status FROM Payslip WHERE payslip_id = p_payslip_id;

    IF v_cur_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: Payslip not found';
    END IF;
    IF v_cur_status = 'Approved' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Validation: Payslip already Approved';
    END IF;
    IF v_cur_status != 'Processed' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Validation: Only Processed payslips can be approved';
    END IF;

    SET @current_user_id = p_calling_user_id;

    START TRANSACTION;
        -- trg_after_payslip_update logs the transition to Audit_Log
        UPDATE Payslip
        SET    status      = 'Approved',
               approved_by = p_calling_user_id,
               approved_on = NOW()
        WHERE  payslip_id  = p_payslip_id;
    COMMIT;
    SET p_message = CONCAT('Payslip ', p_payslip_id, ' approved');
END //


-- sp_generate_monthly_payroll : batch payroll via cursor loop
-- Calls sp_generate_payslip per active employee; tracks success/error counts
-- RBAC: Admin or HR; called by evt_monthly_payroll event
CREATE PROCEDURE sp_generate_monthly_payroll(
    IN  p_calling_user_id INT,
    IN  p_month           TINYINT,
    IN  p_year            YEAR,
    OUT p_generated       INT,
    OUT p_message         VARCHAR(255)
)
BEGIN
    DECLARE v_emp_id   INT;
    DECLARE v_done     INT DEFAULT 0;
    DECLARE v_ps_id    INT;
    DECLARE v_ps_msg   VARCHAR(255);
    DECLARE v_errors   INT DEFAULT 0;

    DECLARE emp_cur CURSOR FOR
        SELECT e.emp_id FROM Employees e JOIN Employee_Salary es ON e.emp_id = es.emp_id
        WHERE  e.status = 'Active'
          AND  NOT EXISTS (
              SELECT 1 FROM Payslip WHERE emp_id = e.emp_id AND month = p_month AND year = p_year
          );

    DECLARE CONTINUE HANDLER FOR NOT FOUND    SET v_done = 1;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_errors = v_errors + 1;

    IF NOT fn_has_permission(p_calling_user_id, 'HR') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Access Denied: Only Admin or HR can run batch payroll';
    END IF;

    SET p_generated      = 0;
    SET @current_user_id = p_calling_user_id;

    OPEN emp_cur;
    payroll_loop: LOOP
        FETCH emp_cur INTO v_emp_id;
        IF v_done THEN LEAVE payroll_loop; END IF;
        CALL sp_generate_payslip(p_calling_user_id, v_emp_id, p_month, p_year, v_ps_id, v_ps_msg);
        IF v_ps_id IS NOT NULL THEN SET p_generated = p_generated + 1;
        ELSE SET v_errors = v_errors + 1; END IF;
    END LOOP;
    CLOSE emp_cur;

    CALL sp_create_notification(NULL,
        CONCAT('Payroll Batch ', p_year, '-', LPAD(p_month, 2, '0')),
        CONCAT('Complete. Success: ', p_generated, ' | Errors: ', v_errors), 'INFO');

    SET p_message = CONCAT('Batch complete. Generated: ', p_generated, ' | Errors: ', v_errors);
END //


-- sp_apply_decrements : v1.0 legacy procedure preserved for backward compatibility
CREATE PROCEDURE sp_apply_decrements(IN p_emp_id INT, IN p_month VARCHAR(20))
BEGIN
    DECLARE v_absent_days INT DEFAULT 0;
    DECLARE v_late_days   INT DEFAULT 0;
    DECLARE v_decrement   DECIMAL(10,2) DEFAULT 0;

    SELECT COUNT(*) INTO v_absent_days FROM Attendance
    WHERE  emp_id = p_emp_id AND status = 'Absent' AND DATE_FORMAT(date, '%Y-%m') = p_month;

    SELECT COUNT(*) INTO v_late_days FROM Attendance
    WHERE  emp_id = p_emp_id AND status = 'Late' AND DATE_FORMAT(date, '%Y-%m') = p_month;

    SELECT (v_absent_days + (v_late_days * 0.5)) * (basic_pay / 30)
    INTO   v_decrement FROM Employee_Salary WHERE emp_id = p_emp_id;

    UPDATE Employee_Salary SET increments = increments - v_decrement WHERE emp_id = p_emp_id;
END //


-- sp_create_notification : inserts in-system notification
CREATE PROCEDURE sp_create_notification(IN p_user_id INT, IN p_title VARCHAR(100),
                                        IN p_message TEXT, IN p_type VARCHAR(10))
BEGIN
    INSERT INTO Notifications (user_id, title, message, type)
    VALUES (p_user_id, p_title, p_message, p_type);
END //

DELIMITER ;


-- ============================================================================
-- SECTION 9 — AUTOMATED EVENTS
-- ============================================================================

SET GLOBAL event_scheduler = ON;

DELIMITER //

-- Fires 1st of every month at 00:30 — auto-generates batch payroll
CREATE EVENT IF NOT EXISTS evt_monthly_payroll
ON SCHEDULE EVERY 1 MONTH
STARTS (DATE_ADD(DATE_FORMAT(CURRENT_DATE, '%Y-%m-01'), INTERVAL 1 MONTH) + INTERVAL 30 MINUTE)
COMMENT 'Auto-generates payroll for all active employees on the 1st of each month'
DO
BEGIN
    DECLARE v_gen INT; DECLARE v_msg VARCHAR(255);
    CALL sp_generate_monthly_payroll(1, MONTH(CURRENT_DATE), YEAR(CURRENT_DATE), v_gen, v_msg);
END //


-- Fires every week — notifies if payslips stuck in Processed status
CREATE EVENT IF NOT EXISTS evt_payroll_reminders
ON SCHEDULE EVERY 1 WEEK
STARTS (CURRENT_TIMESTAMP + INTERVAL 1 WEEK)
COMMENT 'Weekly reminder for pending payroll approvals'
DO
BEGIN
    DECLARE v_cnt INT DEFAULT 0;
    SELECT COUNT(*) INTO v_cnt FROM Payslip WHERE status = 'Processed';
    IF v_cnt > 0 THEN
        INSERT INTO Notifications (user_id, title, message, type)
        VALUES (NULL, 'Pending Payroll Approvals',
                CONCAT(v_cnt, ' payslips await approval. Review Monthly_Payroll_View.'), 'REMINDER');
    END IF;
END //


-- Fires 1st January every year — resets leave balances with carry-forward
CREATE EVENT IF NOT EXISTS evt_leave_balance_reset
ON SCHEDULE EVERY 1 YEAR STARTS '2026-01-01 00:01:00'
COMMENT 'Annual leave balance reset with carry-forward handling'
DO
BEGIN
    DECLARE v_new_year YEAR;
    SET v_new_year = YEAR(CURRENT_DATE);
    INSERT INTO Leave_Balance (emp_id, leave_type_id, year, total_leaves, used_leaves)
    SELECT lb.emp_id, lb.leave_type_id, v_new_year,
           lt.max_days + IF(lt.carry_forward = 1, GREATEST(0, lb.total_leaves - lb.used_leaves), 0), 0
    FROM  Leave_Balance lb JOIN Leave_Types lt ON lb.leave_type_id = lt.leave_type_id
    WHERE lb.year = v_new_year - 1
    ON DUPLICATE KEY UPDATE total_leaves = VALUES(total_leaves), used_leaves = 0;

    INSERT INTO Notifications (user_id, title, message, type) VALUES
    (NULL, 'Leave Balances Reset',
     CONCAT('Annual leave balances reset for ', v_new_year, '. Carry-forward applied.'), 'INFO');
END //


-- Fires every 3 months — notifies about old Salary_Reports eligible for archival
CREATE EVENT IF NOT EXISTS evt_archive_old_reports
ON SCHEDULE EVERY 3 MONTH STARTS (CURRENT_TIMESTAMP + INTERVAL 3 MONTH)
COMMENT 'Quarterly archival reminder for old Salary_Report records'
DO
BEGIN
    DECLARE v_cnt INT DEFAULT 0;
    SELECT COUNT(*) INTO v_cnt FROM Salary_Report
    WHERE generated_on < DATE_SUB(CURDATE(), INTERVAL 2 YEAR);
    IF v_cnt > 0 THEN
        INSERT INTO Notifications (user_id, title, message, type) VALUES
        (NULL, 'Archive Recommended',
         CONCAT(v_cnt, ' Salary_Report records > 2 years old. Consider archiving.'), 'WARNING');
    END IF;
END //

DELIMITER ;


-- ============================================================================
-- SECTION 10 — PAYROLL CONFIGURATION SEED DATA
-- All calculation parameters here — nothing hardcoded in procedures
-- ============================================================================

INSERT INTO Payroll_Config (config_key, config_value, data_type, description) VALUES
('pf_percentage',                 '12.00', 'DECIMAL', 'Employee PF: 12% of basic (EPF Act)'),
('pt_slab1_limit',                '10000', 'DECIMAL', 'PT Slab 1: gross <= limit -> slab1_tax'),
('pt_slab1_tax',                  '0',     'DECIMAL', 'PT for Slab 1 (INR/month)'),
('pt_slab2_limit',                '15000', 'DECIMAL', 'PT Slab 2: gross <= limit -> slab2_tax'),
('pt_slab2_tax',                  '150',   'DECIMAL', 'PT for Slab 2 (INR/month)'),
('pt_slab3_tax',                  '200',   'DECIMAL', 'PT for Slab 3: gross > slab2_limit'),
('income_tax_percentage',         '10.00', 'DECIMAL', 'Simplified TDS: 10% of gross salary'),
('bonus_percentage',              '8.33',  'DECIMAL', 'Statutory bonus: 8.33% of basic (Bonus Act)'),
('overtime_rate_per_hour',        '150.00','DECIMAL', 'Overtime pay rate in INR per hour'),
('standard_work_hours',           '8',     'INT',     'Standard daily hours for OT threshold'),
('working_days_per_month',        '26',    'INT',     'Working days per month for LOP calculation'),
('late_arrival_threshold_minutes','15',    'INT',     'Minutes past 09:00 to classify as Late');


-- ============================================================================
-- SECTION 11 — LEAVE TYPES SEED DATA
-- ============================================================================

INSERT INTO Leave_Types (leave_name, max_days, is_paid, carry_forward, description) VALUES
('Casual Leave',    12,  1, 0, 'General paid leave for personal matters. No carry-forward.'),
('Sick Leave',      12,  1, 0, 'Medical leave. Certificate required > 3 consecutive days.'),
('Earned Leave',    18,  1, 1, 'Earned through service. Unused days carry forward.'),
('Maternity Leave', 182, 1, 0, 'Per Maternity Benefit Act 1961 — 26 weeks.'),
('Paternity Leave', 15,  1, 0, 'Paid paternity leave — 15 working days.'),
('Comp-off Leave',  5,   1, 0, 'Compensatory leave for working on declared holidays.'),
('Loss of Pay',     0,   0, 0, 'Unpaid absence when all paid leave exhausted.');


-- ============================================================================
-- SECTION 12 — SAMPLE DATA GENERATOR
-- 500 employees, 20 departments, ~65,000 attendance records (Jan-Jun 2025)
-- 4 months of payslips, leave requests, salary history, audit log
-- ============================================================================

DELIMITER //

CREATE PROCEDURE sp_generate_sample_data()
BEGIN
    DECLARE v_i       INT DEFAULT 0;
    DECLARE v_emp_id  INT;
    DECLARE v_user_id INT;
    DECLARE v_dept    VARCHAR(50);
    DECLARE v_fname   VARCHAR(50);
    DECLARE v_lname   VARCHAR(50);
    DECLARE v_desig   VARCHAR(100);
    DECLARE v_basic   DECIMAL(10,2);
    DECLARE v_hra     DECIMAL(10,2);
    DECLARE v_da      DECIMAL(10,2);
    DECLARE v_medical DECIMAL(10,2);
    DECLARE v_special DECIMAL(10,2);
    DECLARE v_mgr_id  INT DEFAULT NULL;
    DECLARE v_gender  VARCHAR(10);
    DECLARE v_dob     DATE;
    DECLARE v_hire    DATE;
    DECLARE v_month   TINYINT;
    DECLARE v_city    VARCHAR(50);
    DECLARE v_state   VARCHAR(50);

    -- ── 1. System Admin (emp_id=1) ─────────────────────────────────────────
    INSERT INTO Users (username, password_hash, role)
    VALUES ('admin', SHA2('Admin@123', 256), 'Admin');
    SET v_user_id = LAST_INSERT_ID();
    INSERT INTO Employees (user_id, name, department, designation, emp_type, status)
    VALUES (v_user_id,'System Administrator','IT Infrastructure','System Admin','Full-Time','Active');
    SET v_emp_id = LAST_INSERT_ID();
    INSERT INTO Employee_Details (emp_id,fname,lname,gender,dob,hire_date,email,phone,city,state,country)
    VALUES (v_emp_id,'System','Admin','Male','1985-01-15','2018-01-01',
            'admin@corphrm.com','9000000001','Bengaluru','Karnataka','India');
    INSERT INTO Employee_Salary (emp_id,basic_pay,hra,da,medical_allowance,special_allowance,effective_from)
    VALUES (v_emp_id,200000,80000,40000,2500,20000,'2024-01-01');

    -- ── 2. HR Manager (emp_id=2) ───────────────────────────────────────────
    INSERT INTO Users (username,password_hash,role)
    VALUES ('hr.sharma',SHA2('Hr@Sharma1',256),'HR');
    SET v_user_id = LAST_INSERT_ID();
    INSERT INTO Employees (user_id,name,department,designation,emp_type,status,manager_id)
    VALUES (v_user_id,'Priya Sharma','Human Resources','HR Manager','Full-Time','Active',1);
    SET v_emp_id = LAST_INSERT_ID();
    INSERT INTO Employee_Details (emp_id,fname,lname,gender,dob,hire_date,email,phone,city,state,country)
    VALUES (v_emp_id,'Priya','Sharma','Female','1990-05-22','2019-03-01',
            'priya.sharma@corphrm.com','9000000002','Mumbai','Maharashtra','India');
    INSERT INTO Employee_Salary (emp_id,basic_pay,hra,da,medical_allowance,special_allowance,effective_from)
    VALUES (v_emp_id,120000,48000,24000,2000,10000,'2024-01-01');

    -- ── 3. HR Executive (emp_id=3) ─────────────────────────────────────────
    INSERT INTO Users (username,password_hash,role)
    VALUES ('hr.verma',SHA2('Hr@Verma2',256),'HR');
    SET v_user_id = LAST_INSERT_ID();
    INSERT INTO Employees (user_id,name,department,designation,emp_type,status,manager_id)
    VALUES (v_user_id,'Amit Verma','Human Resources','HR Executive','Full-Time','Active',2);
    SET v_emp_id = LAST_INSERT_ID();
    INSERT INTO Employee_Details (emp_id,fname,lname,gender,dob,hire_date,email,phone,city,state,country)
    VALUES (v_emp_id,'Amit','Verma','Male','1993-08-10','2021-06-01',
            'amit.verma@corphrm.com','9000000003','Delhi','Delhi','India');
    INSERT INTO Employee_Salary (emp_id,basic_pay,hra,da,medical_allowance,special_allowance,effective_from)
    VALUES (v_emp_id,70000,28000,14000,1500,5000,'2024-01-01');

    -- Init leave for first 3 employees
    INSERT IGNORE INTO Leave_Balance (emp_id,leave_type_id,year,total_leaves,used_leaves)
    SELECT e.emp_id,lt.leave_type_id,2025,lt.max_days,0
    FROM Employees e CROSS JOIN Leave_Types lt WHERE e.emp_id<=3;

    -- ── 4. 20 Department Managers (emp_id 4-23) ────────────────────────────
    SET v_i = 1;
    WHILE v_i <= 20 DO
        SET v_dept = ELT(v_i,
            'Engineering','Product Management','Data Science','DevOps',
            'Quality Assurance','Finance & Accounting','Marketing','Sales',
            'Customer Success','Legal & Compliance','IT Infrastructure',
            'Security','Business Intelligence','Research & Development',
            'Operations','Procurement','Administration',
            'Training & Development','Executive Office','Human Resources');
        SET v_fname = ELT(v_i,
            'Rajesh','Sunita','Vikram','Kavitha','Deepak',
            'Nandini','Suresh','Meena','Arjun','Pooja',
            'Rohan','Anita','Sandeep','Divya','Manoj',
            'Rekha','Anil','Sujata','Varun','Lalitha');
        SET v_lname = ELT(v_i,
            'Kumar','Gupta','Singh','Reddy','Patel',
            'Nair','Rao','Iyer','Joshi','Das',
            'Pillai','Menon','Chauhan','Shah','Mehta',
            'Bhat','Desai','Pandey','Sinha','Krishnan');
        SET v_basic   = 150000 + (CRC32(CONCAT('mgr',v_i)) MOD 100000);
        SET v_hra     = ROUND(v_basic*0.40,2);
        SET v_da      = ROUND(v_basic*0.12,2);
        SET v_medical = 2500;
        SET v_special = ROUND(v_basic*0.05,2);
        SET v_gender  = IF(v_i MOD 3=0,'Female','Male');
        SET v_dob     = DATE_SUB('1985-01-01',INTERVAL (CRC32(CONCAT('dob',v_i)) MOD 3650) DAY);
        SET v_hire    = DATE_SUB('2023-01-01',INTERVAL (CRC32(CONCAT('hir',v_i)) MOD 2190) DAY);
        SET v_city    = ELT(1+(v_i MOD 6),'Bengaluru','Mumbai','Delhi','Hyderabad','Chennai','Pune');
        SET v_state   = ELT(1+(v_i MOD 6),'Karnataka','Maharashtra','Delhi','Telangana','Tamil Nadu','Maharashtra');

        INSERT INTO Users (username,password_hash,role)
        VALUES (CONCAT('mgr.',LOWER(v_fname),v_i),SHA2(CONCAT('Mgr@',v_i,'Pass'),256),'Manager');
        SET v_user_id = LAST_INSERT_ID();

        INSERT INTO Employees (user_id,name,department,designation,emp_type,status,manager_id)
        VALUES (v_user_id,CONCAT(v_fname,' ',v_lname),v_dept,CONCAT('Head of ',v_dept),'Full-Time','Active',1);
        SET v_emp_id = LAST_INSERT_ID();

        INSERT INTO Employee_Details (emp_id,fname,lname,gender,dob,hire_date,email,phone,city,state,country)
        VALUES (v_emp_id,v_fname,v_lname,v_gender,v_dob,v_hire,
                CONCAT(LOWER(v_fname),'.',LOWER(v_lname),v_i,'@corphrm.com'),
                CONCAT('90',LPAD(v_i*7+1000000,8,'0')),v_city,v_state,'India');

        INSERT INTO Employee_Salary (emp_id,basic_pay,hra,da,medical_allowance,special_allowance,effective_from)
        VALUES (v_emp_id,v_basic,v_hra,v_da,v_medical,v_special,'2024-01-01');

        INSERT IGNORE INTO Leave_Balance (emp_id,leave_type_id,year,total_leaves,used_leaves)
        SELECT v_emp_id,leave_type_id,2025,max_days,0 FROM Leave_Types;

        SET v_i = v_i+1;
    END WHILE;

    -- ── 5. 477 Regular Employees (emp_id 24-500) ───────────────────────────
    SET v_i = 1;
    WHILE v_i <= 477 DO
        SET v_dept = ELT(1+(v_i MOD 20),
            'Engineering','Product Management','Data Science','DevOps',
            'Quality Assurance','Finance & Accounting','Marketing','Sales',
            'Customer Success','Legal & Compliance','IT Infrastructure',
            'Security','Business Intelligence','Research & Development',
            'Operations','Procurement','Administration',
            'Training & Development','Executive Office','Human Resources');
        SET v_mgr_id = 4+(v_i MOD 20);
        SET v_fname = ELT(1+(v_i MOD 30),
            'Aarav','Arjun','Vihaan','Sai','Rohan',
            'Priya','Ananya','Divya','Sneha','Nisha',
            'Rahul','Amit','Deepak','Suresh','Vikram',
            'Sunita','Kavitha','Meena','Pooja','Ritu',
            'Karthik','Lakshmi','Venkat','Bhavna','Nikhil',
            'Swati','Harsh','Pallavi','Gaurav','Shruti');
        SET v_lname = ELT(1+((v_i*7) MOD 30),
            'Kumar','Gupta','Singh','Reddy','Patel',
            'Nair','Rao','Iyer','Joshi','Das',
            'Pillai','Menon','Chauhan','Shah','Mehta',
            'Bhat','Desai','Pandey','Sinha','Krishnan',
            'Verma','Tiwari','Mishra','Dubey','Sharma',
            'Agarwal','Bansal','Kapoor','Malhotra','Saxena');

        IF v_i MOD 5=0 THEN
            SET v_desig=CONCAT('Senior ',ELT(1+(v_i MOD 4),'Engineer','Analyst','Developer','Consultant'));
            SET v_basic=80000+(CRC32(CONCAT('s',v_i)) MOD 50000);
        ELSEIF v_i MOD 5=1 THEN
            SET v_desig=CONCAT('Lead ',ELT(1+(v_i MOD 3),'Engineer','Analyst','Designer'));
            SET v_basic=110000+(CRC32(CONCAT('l',v_i)) MOD 40000);
        ELSEIF v_i MOD 5=2 THEN
            SET v_desig=ELT(1+(v_i MOD 4),'Software Engineer','Data Analyst','QA Engineer','DevOps Engineer');
            SET v_basic=50000+(CRC32(CONCAT('e',v_i)) MOD 30000);
        ELSEIF v_i MOD 5=3 THEN
            SET v_desig=CONCAT('Junior ',ELT(1+(v_i MOD 3),'Engineer','Associate','Executive'));
            SET v_basic=35000+(CRC32(CONCAT('j',v_i)) MOD 15000);
        ELSE
            SET v_desig=ELT(1+(v_i MOD 3),'Principal Engineer','Staff Engineer','Technical Lead');
            SET v_basic=130000+(CRC32(CONCAT('p',v_i)) MOD 70000);
        END IF;

        SET v_hra     = ROUND(v_basic*0.40,2);
        SET v_da      = ROUND(v_basic*0.10,2);
        SET v_medical = 1250;
        SET v_special = ROUND(v_basic*0.05,2);
        SET v_gender  = ELT(1+(v_i MOD 3),'Male','Female','Male');
        SET v_dob     = DATE_SUB('1995-06-15',INTERVAL (CRC32(CONCAT('d',v_i)) MOD 3650) DAY);
        SET v_hire    = DATE_SUB('2024-06-01',INTERVAL (CRC32(CONCAT('h',v_i)) MOD 1825) DAY);
        SET v_city    = ELT(1+(v_i MOD 8),'Bengaluru','Mumbai','Delhi','Hyderabad','Chennai','Pune','Kolkata','Ahmedabad');
        SET v_state   = ELT(1+(v_i MOD 8),'Karnataka','Maharashtra','Delhi','Telangana','Tamil Nadu','Maharashtra','West Bengal','Gujarat');

        INSERT INTO Users (username,password_hash,role)
        VALUES (CONCAT('emp.',LOWER(SUBSTRING(v_fname,1,3)),LOWER(SUBSTRING(v_lname,1,3)),v_i),
                SHA2(CONCAT('Emp@',v_i,'Pass'),256),'Employee');
        SET v_user_id = LAST_INSERT_ID();

        INSERT INTO Employees (user_id,name,department,designation,emp_type,status,manager_id)
        VALUES (v_user_id,CONCAT(v_fname,' ',v_lname),v_dept,v_desig,'Full-Time','Active',v_mgr_id);
        SET v_emp_id = LAST_INSERT_ID();

        INSERT INTO Employee_Details (emp_id,fname,lname,gender,dob,hire_date,email,phone,city,state,country)
        VALUES (v_emp_id,v_fname,v_lname,v_gender,v_dob,v_hire,
                CONCAT(LOWER(v_fname),'.',LOWER(v_lname),v_i,'@corphrm.com'),
                CONCAT('98',LPAD(v_i+1000000,8,'0')),v_city,v_state,'India');

        INSERT INTO Employee_Salary (emp_id,basic_pay,hra,da,medical_allowance,special_allowance,effective_from)
        VALUES (v_emp_id,v_basic,v_hra,v_da,v_medical,v_special,
                DATE_SUB(CURDATE(),INTERVAL (CRC32(CONCAT('ef',v_i)) MOD 365) DAY));

        INSERT IGNORE INTO Leave_Balance (emp_id,leave_type_id,year,total_leaves,used_leaves)
        SELECT v_emp_id,leave_type_id,2025,max_days,0 FROM Leave_Types;

        SET v_i = v_i+1;
    END WHILE;

    -- ── 6. Bulk Attendance: Jan-Jun 2025 (~65,000 rows) ────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_cal;
    CREATE TEMPORARY TABLE tmp_cal (cal_date DATE, PRIMARY KEY (cal_date));

    INSERT INTO tmp_cal (cal_date)
    SELECT DATE_ADD('2025-01-01', INTERVAL n DAY)
    FROM (
        SELECT a.n+b.n*10+c.n*100 AS n
        FROM (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
              UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) a
        CROSS JOIN
             (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
              UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) b
        CROSS JOIN (SELECT 0 n UNION ALL SELECT 1) c
    ) nums
    WHERE DATE_ADD('2025-01-01', INTERVAL n DAY) <= '2025-06-30'
      AND DAYOFWEEK(DATE_ADD('2025-01-01', INTERVAL n DAY)) NOT IN (1,7);

    -- CRC32 gives deterministic pseudo-random status per emp+date combination
    INSERT IGNORE INTO Attendance (emp_id,date,status,check_in,check_out,working_hours,overtime_hours)
    SELECT
        e.emp_id, c.cal_date,
        CASE
            WHEN (CRC32(CONCAT(e.emp_id,'|',c.cal_date)) MOD 100) <  8 THEN 'Absent'
            WHEN (CRC32(CONCAT(e.emp_id,'|',c.cal_date)) MOD 100) < 20 THEN 'Late'
            ELSE 'Present'
        END,
        CASE
            WHEN (CRC32(CONCAT(e.emp_id,'|',c.cal_date)) MOD 100) <  8 THEN NULL
            WHEN (CRC32(CONCAT(e.emp_id,'|',c.cal_date)) MOD 100) < 20
                 THEN ADDTIME('09:16:00', SEC_TO_TIME((CRC32(CONCAT(e.emp_id,'ci',c.cal_date)) MOD 60)*60))
            ELSE ADDTIME('08:30:00', SEC_TO_TIME((CRC32(CONCAT(e.emp_id,'ci',c.cal_date)) MOD 60)*60))
        END,
        CASE
            WHEN (CRC32(CONCAT(e.emp_id,'|',c.cal_date)) MOD 100) < 8 THEN NULL
            ELSE ADDTIME('17:00:00', SEC_TO_TIME((CRC32(CONCAT(e.emp_id,'co',c.cal_date)) MOD 180)*60))
        END,
        CASE
            WHEN (CRC32(CONCAT(e.emp_id,'|',c.cal_date)) MOD 100) < 8 THEN 0
            ELSE ROUND(8.0+(CRC32(CONCAT(e.emp_id,'wh',c.cal_date)) MOD 300)/120.0,2)
        END,
        CASE
            WHEN (CRC32(CONCAT(e.emp_id,'|',c.cal_date)) MOD 100) < 8 THEN 0
            WHEN (CRC32(CONCAT(e.emp_id,'ot',c.cal_date)) MOD 10) >= 7
                 THEN ROUND(0.5+(CRC32(CONCAT(e.emp_id,'ot2',c.cal_date)) MOD 200)/100.0,2)
            ELSE 0
        END
    FROM Employees e CROSS JOIN tmp_cal c WHERE e.status='Active';

    DROP TEMPORARY TABLE IF EXISTS tmp_cal;

    -- ── 7. Bulk Payslips: Jan-Apr 2025 (~2,000 rows) ───────────────────────
    SET v_month = 1;
    WHILE v_month <= 4 DO
        INSERT IGNORE INTO Payslip (
            emp_id,month,year,
            basic_pay,hra,da,medical_allowance,special_allowance,
            bonus,overtime_pay,gross_salary,
            pf_deduction,professional_tax,income_tax,
            loss_of_pay,other_deductions,total_deductions,net_salary,
            total_working_days,days_present,days_absent,days_late,
            overtime_hours_total,status,generated_by,approved_by,approved_on
        )
        WITH att AS (
            SELECT emp_id,
                COUNT(*) AS tot_days,
                SUM(CASE WHEN status IN('Present','Late','Half-Day') THEN 1 ELSE 0 END) AS pres,
                SUM(CASE WHEN status='Absent' THEN 1 ELSE 0 END) AS abs,
                SUM(CASE WHEN status='Late'   THEN 1 ELSE 0 END) AS late,
                ROUND(SUM(IFNULL(overtime_hours,0)),2) AS ot
            FROM Attendance WHERE MONTH(date)=v_month AND YEAR(date)=2025
            GROUP BY emp_id
        )
        SELECT
            e.emp_id,v_month,2025,
            es.basic_pay,es.hra,es.da,es.medical_allowance,es.special_allowance,
            ROUND(es.basic_pay*0.0833,2),
            ROUND(IFNULL(a.ot,0)*150.0,2),
            ROUND(es.basic_pay+es.hra+es.da+es.medical_allowance+es.special_allowance
                  +es.basic_pay*0.0833+IFNULL(a.ot,0)*150.0,2),
            ROUND(es.basic_pay*0.12,2),
            CASE WHEN (es.basic_pay+es.hra+es.da)<=10000 THEN 0
                 WHEN (es.basic_pay+es.hra+es.da)<=15000 THEN 150
                 ELSE 200 END,
            ROUND((es.basic_pay+es.hra+es.da+es.medical_allowance+es.special_allowance
                   +es.basic_pay*0.0833+IFNULL(a.ot,0)*150.0)*0.10,2),
            ROUND(IFNULL(a.abs,0)*es.basic_pay/26.0,2),
            0,
            ROUND(es.basic_pay*0.12
                  +CASE WHEN(es.basic_pay+es.hra+es.da)<=10000 THEN 0
                        WHEN(es.basic_pay+es.hra+es.da)<=15000 THEN 150 ELSE 200 END
                  +(es.basic_pay+es.hra+es.da+es.medical_allowance+es.special_allowance
                    +es.basic_pay*0.0833+IFNULL(a.ot,0)*150.0)*0.10
                  +IFNULL(a.abs,0)*es.basic_pay/26.0,2),
            GREATEST(0,ROUND(
                es.basic_pay+es.hra+es.da+es.medical_allowance+es.special_allowance
                +es.basic_pay*0.0833+IFNULL(a.ot,0)*150.0
                -es.basic_pay*0.12
                -CASE WHEN(es.basic_pay+es.hra+es.da)<=10000 THEN 0
                      WHEN(es.basic_pay+es.hra+es.da)<=15000 THEN 150 ELSE 200 END
                -(es.basic_pay+es.hra+es.da+es.medical_allowance+es.special_allowance
                  +es.basic_pay*0.0833+IFNULL(a.ot,0)*150.0)*0.10
                -IFNULL(a.abs,0)*es.basic_pay/26.0,2)),
            IFNULL(a.tot_days,0),IFNULL(a.pres,0),IFNULL(a.abs,0),IFNULL(a.late,0),IFNULL(a.ot,0),
            IF(v_month<=3,'Approved','Processed'),
            1,
            IF(v_month<=3,1,NULL),
            IF(v_month<=3,DATE_ADD(CONCAT('2025-',LPAD(v_month,2,'0'),'-28'),INTERVAL 2 DAY),NULL)
        FROM Employees e
        JOIN Employee_Salary es ON e.emp_id=es.emp_id
        LEFT JOIN att a ON e.emp_id=a.emp_id
        WHERE e.status='Active';

        INSERT IGNORE INTO Salary_Report (emp_id,month,total_salary,generated_on)
        SELECT emp_id,CONCAT('2025-',LPAD(v_month,2,'0')),net_salary,CURDATE()
        FROM   Payslip WHERE month=v_month AND year=2025
        ON DUPLICATE KEY UPDATE total_salary=VALUES(total_salary);

        SET v_month=v_month+1;
    END WHILE;

    -- ── 8. Leave Requests (150 employees × 3 types = 450 requests) ─────────
    INSERT INTO Leave_Requests
        (emp_id,leave_type_id,from_date,to_date,days_requested,reason,status,reviewed_by)
    SELECT
        e.emp_id, lt.leave_type_id,
        DATE_ADD('2025-01-01',INTERVAL (CRC32(CONCAT(e.emp_id,'fd',lt.leave_type_id)) MOD 150) DAY),
        DATE_ADD('2025-01-01',INTERVAL (CRC32(CONCAT(e.emp_id,'fd',lt.leave_type_id)) MOD 150)+3 DAY),
        1+(CRC32(CONCAT(e.emp_id,'days',lt.leave_type_id)) MOD 4),
        ELT(1+(CRC32(CONCAT(e.emp_id,'rsn',lt.leave_type_id)) MOD 5),
            'Medical appointment','Family function','Personal work','Travel','Health recovery'),
        ELT(1+(CRC32(CONCAT(e.emp_id,'st',lt.leave_type_id)) MOD 3),'Approved','Pending','Rejected'),
        IF(CRC32(CONCAT(e.emp_id,'rv',lt.leave_type_id)) MOD 3!=0, 4+(e.emp_id MOD 20), NULL)
    FROM (SELECT emp_id FROM Employees WHERE status='Active' AND emp_id<=150) e
    CROSS JOIN (SELECT leave_type_id FROM Leave_Types WHERE leave_type_id<=3) lt;

    -- Sync leave balances for approved requests
    UPDATE Leave_Balance lb
    JOIN (
        SELECT emp_id,leave_type_id,SUM(days_requested) AS used
        FROM   Leave_Requests WHERE status='Approved' AND YEAR(from_date)=2025
        GROUP  BY emp_id,leave_type_id
    ) lr ON lb.emp_id=lr.emp_id AND lb.leave_type_id=lr.leave_type_id AND lb.year=2025
    SET lb.used_leaves=LEAST(lb.total_leaves,lr.used);

    -- ── 9. Salary History for 20 managers (10% simulated increment) ─────────
    INSERT INTO Employee_Salary_History
        (emp_id,old_basic_pay,new_basic_pay,old_hra,new_hra,old_da,new_da,
         old_medical,new_medical,old_special,new_special,effective_date,changed_by,reason)
    SELECT emp_id,
        ROUND(basic_pay/1.10,2),basic_pay,ROUND(hra/1.10,2),hra,
        ROUND(da/1.10,2),da,medical_allowance,medical_allowance,
        ROUND(special_allowance/1.10,2),special_allowance,
        DATE_SUB(CURDATE(),INTERVAL 6 MONTH),1,
        '10% annual increment — performance review 2024'
    FROM Employee_Salary WHERE emp_id BETWEEN 4 AND 23;

    -- ── 10. Sample Audit Log ────────────────────────────────────────────────
    INSERT INTO Audit_Log (table_name,operation,record_id,emp_id,changed_by,old_values,new_values,remarks)
    VALUES
    ('Employees','UPDATE',5,5,1,
     JSON_OBJECT('department','Engineering','status','Active'),
     JSON_OBJECT('department','DevOps','status','Active'),
     'Department transfer — employee requested DevOps move'),
    ('Employee_Salary','UPDATE',5,5,2,
     JSON_OBJECT('basic_pay',160000.00),JSON_OBJECT('basic_pay',176000.00),
     '10% annual review increment'),
    ('Payslip','UPDATE',1,1,2,
     JSON_OBJECT('status','Processed'),JSON_OBJECT('status','Approved'),
     'January 2025 payroll approved');

    -- ── 11. Notifications ───────────────────────────────────────────────────
    INSERT INTO Notifications (user_id,title,message,type) VALUES
    (1,'System Initialised',
     'Enterprise Payroll System v2.0 started. 500 employees, 65000+ attendance records.','INFO'),
    (2,'Payroll Generated','Jan-Apr 2025 payroll generated for all active employees.','INFO'),
    (1,'Pending Approvals','April 2025 payslips await approval.','REMINDER'),
    (NULL,'Compliance Reminder','Professional Tax due by 15th of each month.','ALERT');

    -- ── Summary ─────────────────────────────────────────────────────────────
    SELECT
        (SELECT COUNT(*) FROM Employees)      AS total_employees,
        (SELECT COUNT(*) FROM Attendance)     AS attendance_records,
        (SELECT COUNT(*) FROM Payslip)        AS payslips,
        (SELECT COUNT(*) FROM Leave_Requests) AS leave_requests,
        (SELECT COUNT(*) FROM Audit_Log)      AS audit_entries,
        (SELECT COUNT(*) FROM Notifications)  AS notifications;
END //

DELIMITER ;

-- Execute sample data generation
CALL sp_generate_sample_data();


-- ============================================================================
-- SECTION 13 — DASHBOARD ANALYTICS (uncomment to run)
-- ============================================================================

-- 1. Department payroll expense for April 2025
-- SELECT * FROM Department_Expense_View WHERE payroll_period='2025-04' ORDER BY total_net_salary DESC;

-- 2. Top 10 earners (most recent payroll period)
-- SELECT * FROM Top_Earners_View LIMIT 10;

-- 3. Worst attendance Jan-Jun 2025
-- SELECT emp_id,employee_name,department,SUM(days_absent) AS total_absents
-- FROM Attendance_Summary_View WHERE year=2025
-- GROUP BY emp_id,employee_name,department ORDER BY total_absents DESC LIMIT 20;

-- 4. Monthly payroll cost trend
-- SELECT year,month,ROUND(SUM(net_salary),2) AS monthly_cost,COUNT(*) AS headcount
-- FROM Payslip WHERE status IN('Processed','Approved') GROUP BY year,month ORDER BY year,month;

-- 5. Average salary by department
-- SELECT department,ROUND(AVG(basic_pay),2) AS avg_basic,ROUND(AVG(ctc_monthly),2) AS avg_ctc
-- FROM Employee_Profile_View WHERE status='Active' GROUP BY department ORDER BY avg_ctc DESC;

-- 6. Pending leave requests
-- SELECT lr.request_id,e.name,e.department,lt.leave_name,lr.from_date,lr.to_date,lr.applied_on
-- FROM Leave_Requests lr JOIN Employees e ON lr.emp_id=e.emp_id
-- JOIN Leave_Types lt ON lr.leave_type_id=lt.leave_type_id
-- WHERE lr.status='Pending' ORDER BY lr.applied_on DESC;

-- 7. Leave utilisation by employee
-- SELECT * FROM Leave_Balance_View WHERE year=2025 ORDER BY remaining_leaves;

-- 8. Payroll approval status summary
-- SELECT status,COUNT(*) AS payslips,ROUND(SUM(net_salary),2) AS total_net FROM Payslip GROUP BY status;

-- 9. Top overtime earners
-- SELECT emp_id,employee_name,department,SUM(overtime_hours_total) AS ot_hours,
--        ROUND(SUM(overtime_pay),2) AS ot_pay
-- FROM Monthly_Payroll_View GROUP BY emp_id,employee_name,department
-- ORDER BY ot_hours DESC LIMIT 20;

-- 10. Audit trail for a specific employee (emp_id=5)
-- SELECT log_id,table_name,operation,old_values,new_values,changed_at
-- FROM Audit_Log WHERE emp_id=5 ORDER BY changed_at;

-- 11. Salary increment history
-- SELECT h.emp_id,e.name,h.old_basic_pay,h.new_basic_pay,
--        ROUND(((h.new_basic_pay-h.old_basic_pay)/h.old_basic_pay)*100,2) AS pct_change,
--        h.effective_date,h.reason
-- FROM Employee_Salary_History h JOIN Employees e ON h.emp_id=e.emp_id ORDER BY h.changed_at DESC;

-- 12. EXPLAIN — index verification on hot attendance query
-- EXPLAIN SELECT * FROM Attendance WHERE emp_id=50 AND date BETWEEN '2025-01-01' AND '2025-06-30';
-- Expected: type=range, key=idx_att_emp_date

-- 13. Security audit — recent salary changes
-- SELECT al.log_id,e.name,al.old_values,al.new_values,u.username,al.changed_at
-- FROM Audit_Log al JOIN Employees e ON al.emp_id=e.emp_id
-- LEFT JOIN Users u ON al.changed_by=u.user_id
-- WHERE al.table_name='Employee_Salary' ORDER BY al.changed_at DESC LIMIT 20;

-- 14. Unread admin notifications
-- SELECT * FROM Notifications WHERE (user_id=1 OR user_id IS NULL) AND is_read=0 ORDER BY created_at DESC;

-- ============================================================================
-- HOW TO EXECUTE
-- ============================================================================
-- From terminal  : mysql -u root -p < payroll_enterprise.sql
-- From MySQL CLI : source /path/to/Employee\ Payroll\ System/payroll_enterprise.sql
--
-- Test login (admin):
--   CALL sp_authenticate_user('admin','Admin@123',@uid,@role,@msg);
--   SELECT @uid AS user_id, @role AS role, @msg AS message;
--
-- Test RBAC rejection (employee trying salary update):
--   CALL sp_update_salary(500,50,60000,24000,6000,1250,3000,'Test',@msg);
--   SELECT @msg;   -- Should return: Access Denied
--
-- Generate May 2025 payslip for employee 50:
--   CALL sp_generate_payslip(1,50,5,2025,@psid,@msg);
--   SELECT @psid AS payslip_id, @msg AS message;
--
-- Approve the payslip:
--   CALL sp_approve_payroll(1,@psid,@msg);
--   SELECT @msg;
--
-- View payslip breakdown:
--   SELECT * FROM Monthly_Payroll_View WHERE emp_id=50 AND payroll_period='2025-05';
--
-- Apply for leave (employee 50, Casual Leave, 3 days):
--   CALL sp_apply_for_leave(@uid,50,1,'2025-07-14','2025-07-16','Vacation',@rid,@msg);
--   SELECT @rid AS request_id, @msg;
-- ============================================================================
