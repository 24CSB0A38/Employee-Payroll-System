package dao;

import models.Employee;
import models.User;
import util.DBConnection;

import java.sql.*;
import java.util.ArrayList;
import java.util.List;

/**
 * EmployeeDAO.java
 *
 * Data Access Object for all employee-related database operations.
 *
 * Interview talking points:
 *  - DAO pattern: separates database logic from UI code.
 *  - PreparedStatement prevents SQL injection.
 *  - CallableStatement invokes MySQL stored procedures.
 *  - try-with-resources guarantees Connection/Statement closing.
 */
public class EmployeeDAO {

    // ─── Authentication ───────────────────────────────────────────────────────

    /**
     * Authenticates a user by comparing SHA2(password,256) against the stored hash.
     * Uses the existing sp_authenticate_user stored procedure.
     *
     * @param username plain-text username
     * @param password plain-text password (hashed inside the stored procedure)
     * @return logged-in User object on success, null on failure
     * @throws SQLException on database errors
     */
    public User authenticate(String username, String password) throws SQLException {
        // sp_authenticate_user hashes the password internally using SHA2()
        String sql = "{CALL sp_authenticate_user(?, ?, ?, ?, ?)}";

        try (Connection con = DBConnection.getConnection();
             CallableStatement cs = con.prepareCall(sql)) {

            cs.setString(1, username);
            cs.setString(2, password);
            cs.registerOutParameter(3, Types.INTEGER);   // p_user_id
            cs.registerOutParameter(4, Types.VARCHAR);   // p_role
            cs.registerOutParameter(5, Types.VARCHAR);   // p_message

            cs.execute();

            int    userId  = cs.getInt(3);
            String role    = cs.getString(4);
            String message = cs.getString(5);

            if (userId == 0 || role == null) {
                // Authentication failed — message holds the reason
                throw new SQLException(message != null ? message : "Authentication failed");
            }

            // Fetch is_active flag for the User model
            return new User(userId, username, role, 1);
        }
    }

    // ─── Employee Listing ─────────────────────────────────────────────────────

    /**
     * Returns all active employees by querying the Employee_Profile_View.
     * Uses PreparedStatement (parameterized query) for clean data access.
     *
     * @return list of Employee objects; empty list if none found
     * @throws SQLException on database errors
     */
    public List<Employee> getAllEmployees() throws SQLException {
        List<Employee> list = new ArrayList<>();
        String sql = "SELECT emp_id, name, department, designation, emp_type, status, "
                   + "fname, lname, gender, email, phone, "
                   + "basic_pay, hra, da, medical_allowance, special_allowance, "
                   + "ctc_monthly, username, system_role "
                   + "FROM Employee_Profile_View "
                   + "ORDER BY emp_id";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                list.add(mapEmployee(rs));
            }
        }
        return list;
    }

    /**
     * Returns a single employee profile by emp_id.
     *
     * @param empId the employee's primary key
     * @return Employee object, or null if not found
     * @throws SQLException on database errors
     */
    public Employee getEmployeeById(int empId) throws SQLException {
        String sql = "SELECT emp_id, name, department, designation, emp_type, status, "
                   + "fname, lname, gender, email, phone, "
                   + "basic_pay, hra, da, medical_allowance, special_allowance, "
                   + "ctc_monthly, username, system_role "
                   + "FROM Employee_Profile_View WHERE emp_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, empId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) return mapEmployee(rs);
            }
        }
        return null;
    }

    /**
     * Finds the emp_id corresponding to a given user_id.
     * Used after login to identify which employee the logged-in user is.
     *
     * @param userId the Users.user_id of the logged-in account
     * @return emp_id, or -1 if no employee record exists
     * @throws SQLException on database errors
     */
    public int getEmpIdByUserId(int userId) throws SQLException {
        String sql = "SELECT emp_id FROM Employees WHERE user_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, userId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) return rs.getInt("emp_id");
            }
        }
        return -1;
    }

    // ─── Dashboard Statistics ─────────────────────────────────────────────────

    /**
     * Returns the count of active employees for the dashboard card.
     *
     * @return count of active employees
     * @throws SQLException on database errors
     */
    public int getTotalActiveEmployees() throws SQLException {
        String sql = "SELECT COUNT(*) FROM Employees WHERE status = 'Active'";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            return rs.next() ? rs.getInt(1) : 0;
        }
    }

    /**
     * Returns the count of attendance records marked today.
     *
     * @return today's attendance count
     * @throws SQLException on database errors
     */
    public int getTodayAttendanceCount() throws SQLException {
        String sql = "SELECT COUNT(*) FROM Attendance WHERE date = CURDATE()";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            return rs.next() ? rs.getInt(1) : 0;
        }
    }

    /**
     * Returns the count of payslips generated (Processed + Approved).
     *
     * @return total payslip count
     * @throws SQLException on database errors
     */
    public int getTotalPayslipCount() throws SQLException {
        String sql = "SELECT COUNT(*) FROM Payslip WHERE status IN ('Processed','Approved')";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            return rs.next() ? rs.getInt(1) : 0;
        }
    }

    // ─── Add Employee ─────────────────────────────────────────────────────────

    /**
     * Onboards a new employee by calling sp_add_employee stored procedure.
     * The procedure atomically creates the User, Employee, Employee_Details,
     * Employee_Salary, and Leave_Balance records inside a single transaction.
     *
     * @return new emp_id on success
     * @throws SQLException containing a user-friendly message on failure
     */
    public int addEmployee(int callingUserId, String username, String password,
                           String name, String department, String designation,
                           String empType, String fname, String lname,
                           String gender, java.sql.Date dob, java.sql.Date hireDate,
                           String email, String phone,
                           double basicPay, double hra, double da,
                           double medical, double special) throws SQLException {

        String sql = "{CALL sp_add_employee(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)}";

        try (Connection con = DBConnection.getConnection();
             CallableStatement cs = con.prepareCall(sql)) {

            cs.setInt(1,     callingUserId);
            cs.setString(2,  username);
            cs.setString(3,  password);
            cs.setString(4,  name);
            cs.setString(5,  department);
            cs.setString(6,  designation);
            cs.setString(7,  empType);
            cs.setString(8,  fname);
            cs.setString(9,  lname);
            cs.setString(10, gender);
            cs.setDate(11,   dob);
            cs.setDate(12,   hireDate);
            cs.setString(13, email);
            cs.setString(14, phone);
            cs.setDouble(15, basicPay);
            cs.setDouble(16, hra);
            cs.setDouble(17, da);
            cs.setDouble(18, medical);
            cs.setDouble(19, special);
            cs.setNull(20,   Types.INTEGER);        // manager_id (optional)
            cs.registerOutParameter(21, Types.INTEGER); // OUT p_new_emp_id
            cs.registerOutParameter(22, Types.VARCHAR); // OUT p_message

            cs.execute();

            int    newEmpId = cs.getInt(21);
            String message  = cs.getString(22);

            if (newEmpId == 0) {
                throw new SQLException(message != null ? message : "Failed to add employee");
            }
            return newEmpId;
        }
    }

    // ─── Private Helpers ──────────────────────────────────────────────────────

    /** Maps the current row of a ResultSet to an Employee object. */
    private Employee mapEmployee(ResultSet rs) throws SQLException {
        return new Employee(
            rs.getInt("emp_id"),
            rs.getString("name"),
            rs.getString("department"),
            rs.getString("designation"),
            rs.getString("emp_type"),
            rs.getString("status"),
            rs.getString("fname"),
            rs.getString("lname"),
            rs.getString("gender"),
            rs.getString("email"),
            rs.getString("phone"),
            rs.getDouble("basic_pay"),
            rs.getDouble("hra"),
            rs.getDouble("da"),
            rs.getDouble("medical_allowance"),
            rs.getDouble("special_allowance"),
            rs.getDouble("ctc_monthly"),
            rs.getString("username"),
            rs.getString("system_role")
        );
    }
}
