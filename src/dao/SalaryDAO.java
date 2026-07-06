package dao;

import util.DBConnection;

import java.sql.*;

/**
 * SalaryDAO.java
 *
 * Data Access Object for salary update and increment operations.
 * Uses existing stored procedures:
 *   - sp_update_salary     — sets absolute salary components
 *   - sp_increment_salary  — applies a percentage-based increment
 *
 * Interview talking points:
 *  - OUT parameters from MySQL stored procedures are registered with
 *    registerOutParameter() before execution.
 *  - Session variables (@current_user_id, @salary_change_reason) are
 *    set inside the stored procedures via the p_calling_user_id parameter.
 *    This triggers the AFTER UPDATE trigger to log history automatically.
 */
public class SalaryDAO {

    /**
     * Calls sp_update_salary to set absolute salary components for an employee.
     * The AFTER UPDATE trigger on Employee_Salary automatically logs
     * the change to Employee_Salary_History and Audit_Log.
     *
     * @param callingUserId user_id of the Admin/HR making the change
     * @param empId         employee whose salary is being updated
     * @param basicPay      new basic pay (must be > 0)
     * @param hra           new HRA component
     * @param da            new DA component
     * @param medical       new medical allowance
     * @param special       new special allowance
     * @param reason        brief note logged into salary history
     * @throws SQLException containing a user-friendly message on failure
     */
    public void updateSalary(int callingUserId, int empId,
                             double basicPay, double hra, double da,
                             double medical, double special,
                             String reason) throws SQLException {

        String sql = "{CALL sp_update_salary(?,?,?,?,?,?,?,?,?)}";

        try (Connection con = DBConnection.getConnection();
             CallableStatement cs = con.prepareCall(sql)) {

            cs.setInt(1,    callingUserId);
            cs.setInt(2,    empId);
            cs.setDouble(3, basicPay);
            cs.setDouble(4, hra);
            cs.setDouble(5, da);
            cs.setDouble(6, medical);
            cs.setDouble(7, special);
            cs.setString(8, reason != null ? reason : "Manual update");
            cs.registerOutParameter(9, Types.VARCHAR);   // OUT p_message

            cs.execute();

            String message = cs.getString(9);
            if (message != null && (message.toLowerCase().contains("denied")
                                 || message.toLowerCase().contains("error"))) {
                throw new SQLException(message);
            }
        }
    }

    /**
     * Calls sp_increment_salary to apply a percentage-based raise.
     * Example: passing 10.0 increases basic_pay by 10%.
     *
     * @param callingUserId user_id of the Admin/HR initiating the increment
     * @param empId         employee receiving the increment
     * @param percent       increment percentage (must be > 0)
     * @param reason        reason logged in history (e.g. "Annual Review 2025")
     * @throws SQLException on access denied, validation failure, or DB error
     */
    public void incrementSalary(int callingUserId, int empId,
                                double percent, String reason) throws SQLException {

        String sql = "{CALL sp_increment_salary(?,?,?,?,?)}";

        try (Connection con = DBConnection.getConnection();
             CallableStatement cs = con.prepareCall(sql)) {

            cs.setInt(1,    callingUserId);
            cs.setInt(2,    empId);
            cs.setDouble(3, percent);
            cs.setString(4, reason != null ? reason : "Increment");
            cs.registerOutParameter(5, Types.VARCHAR);   // OUT p_message

            cs.execute();

            String message = cs.getString(5);
            if (message != null && (message.toLowerCase().contains("denied")
                                 || message.toLowerCase().contains("error"))) {
                throw new SQLException(message);
            }
        }
    }

    /**
     * Returns the current basic salary of an employee for pre-filling forms.
     *
     * @param empId the employee's primary key
     * @return current basic_pay, or 0 if no record found
     * @throws SQLException on database error
     */
    public double getCurrentBasicPay(int empId) throws SQLException {
        String sql = "SELECT basic_pay FROM Employee_Salary WHERE emp_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, empId);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() ? rs.getDouble("basic_pay") : 0.0;
            }
        }
    }
}
