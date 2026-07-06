package dao;

import models.Payslip;
import util.DBConnection;

import java.sql.*;
import java.util.ArrayList;
import java.util.List;

/**
 * ReportDAO.java
 *
 * Data Access Object for payslip generation, approval, and retrieval.
 * Uses existing stored procedures:
 *   - sp_generate_payslip  — computes monthly payslip (earnings + deductions)
 *   - sp_approve_payroll   — transitions Processed → Approved
 *
 * Interview talking points:
 *  - Monthly_Payroll_View is a database VIEW that joins Payslip + Employees
 *    + Users, so the Java code gets a flat ResultSet with no extra joins.
 *  - Stored procedure out-parameters (payslip_id, message) carry results
 *    back to Java via registerOutParameter().
 */
public class ReportDAO {

    // ─── Payslip Generation ───────────────────────────────────────────────────

    /**
     * Generates a payslip for one employee by calling sp_generate_payslip.
     *
     * The stored procedure:
     *   1. Reads salary components from Employee_Salary.
     *   2. Reads configuration (PF%, IT%, bonus%, OT rate) from Payroll_Config.
     *   3. Aggregates attendance (present, absent, overtime) from Attendance.
     *   4. Computes gross, deductions, and net salary.
     *   5. Inserts a row into Payslip and upserts Salary_Report (v1.0 compat).
     *
     * @param callingUserId Admin/HR user_id initiating the generation
     * @param empId         employee for whom the payslip is generated
     * @param month         month (1-12)
     * @param year          four-digit year
     * @return newly created payslip_id
     * @throws SQLException containing reason message on failure
     */
    public int generatePayslip(int callingUserId, int empId,
                               int month, int year) throws SQLException {

        String sql = "{CALL sp_generate_payslip(?,?,?,?,?,?)}";

        try (Connection con = DBConnection.getConnection();
             CallableStatement cs = con.prepareCall(sql)) {

            cs.setInt(1, callingUserId);
            cs.setInt(2, empId);
            cs.setInt(3, month);
            cs.setInt(4, year);
            cs.registerOutParameter(5, Types.INTEGER);   // OUT p_payslip_id
            cs.registerOutParameter(6, Types.VARCHAR);   // OUT p_message

            cs.execute();

            int    payslipId = cs.getInt(5);
            String message   = cs.getString(6);

            if (payslipId == 0) {
                throw new SQLException(message != null ? message : "Payslip generation failed");
            }
            return payslipId;
        }
    }

    /**
     * Runs sp_generate_monthly_payroll to batch-generate payslips for all
     * active employees who do not yet have a payslip for the given month.
     *
     * @param callingUserId Admin/HR user_id running the batch
     * @param month         month (1-12)
     * @param year          four-digit year
     * @return number of payslips successfully generated
     * @throws SQLException on access denied or DB error
     */
    public int generateMonthlyPayroll(int callingUserId,
                                      int month, int year) throws SQLException {

        String sql = "{CALL sp_generate_monthly_payroll(?,?,?,?,?)}";

        try (Connection con = DBConnection.getConnection();
             CallableStatement cs = con.prepareCall(sql)) {

            cs.setInt(1, callingUserId);
            cs.setInt(2, month);
            cs.setInt(3, year);
            cs.registerOutParameter(4, Types.INTEGER);   // OUT p_generated
            cs.registerOutParameter(5, Types.VARCHAR);   // OUT p_message

            cs.execute();

            int generated = cs.getInt(4);
            return generated;
        }
    }

    // ─── Payslip Approval ─────────────────────────────────────────────────────

    /**
     * Approves a payslip by calling sp_approve_payroll (Processed → Approved).
     *
     * @param callingUserId Admin/HR user_id approving the payslip
     * @param payslipId     payslip primary key
     * @throws SQLException if not found, already approved, or access denied
     */
    public void approvePayslip(int callingUserId, int payslipId) throws SQLException {
        String sql = "{CALL sp_approve_payroll(?,?,?)}";

        try (Connection con = DBConnection.getConnection();
             CallableStatement cs = con.prepareCall(sql)) {

            cs.setInt(1, callingUserId);
            cs.setInt(2, payslipId);
            cs.registerOutParameter(3, Types.VARCHAR);   // OUT p_message

            cs.execute();

            String message = cs.getString(3);
            if (message != null && (message.toLowerCase().contains("denied")
                                 || message.toLowerCase().contains("error"))) {
                throw new SQLException(message);
            }
        }
    }

    // ─── Payslip Retrieval ────────────────────────────────────────────────────

    /**
     * Returns all payslips visible through Monthly_Payroll_View.
     * For use in Admin Reports panel.
     *
     * @return list of Payslip objects; empty list if none found
     * @throws SQLException on database error
     */
    public List<Payslip> getAllPayslips() throws SQLException {
        List<Payslip> list = new ArrayList<>();
        String sql = "SELECT payslip_id, emp_id, employee_name, department, "
                   + "payroll_period, basic_pay, hra, da, bonus, overtime_pay, gross_salary, "
                   + "pf_deduction, professional_tax, income_tax, loss_of_pay, "
                   + "total_deductions, net_salary, days_present, days_absent, "
                   + "payroll_status, generated_by, approved_by "
                   + "FROM Monthly_Payroll_View "
                   + "ORDER BY payroll_period DESC, employee_name";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                list.add(mapPayslip(rs));
            }
        }
        return list;
    }

    /**
     * Returns all payslips for a specific employee (used in Employee Dashboard).
     *
     * @param empId the employee's primary key
     * @return list of Payslip objects for this employee
     * @throws SQLException on database error
     */
    public List<Payslip> getPayslipsByEmployee(int empId) throws SQLException {
        List<Payslip> list = new ArrayList<>();
        String sql = "SELECT payslip_id, emp_id, employee_name, department, "
                   + "payroll_period, basic_pay, hra, da, bonus, overtime_pay, gross_salary, "
                   + "pf_deduction, professional_tax, income_tax, loss_of_pay, "
                   + "total_deductions, net_salary, days_present, days_absent, "
                   + "payroll_status, generated_by, approved_by "
                   + "FROM Monthly_Payroll_View "
                   + "WHERE emp_id = ? ORDER BY payroll_period DESC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, empId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    list.add(mapPayslip(rs));
                }
            }
        }
        return list;
    }

    /**
     * Returns rows for the Admin payslip table.
     * Columns: ID | Employee | Department | Period | Gross | Net | Status
     *
     * @return list of Object arrays for JTable
     * @throws SQLException on database error
     */
    public List<Object[]> getPayslipTableData() throws SQLException {
        List<Object[]> rows = new ArrayList<>();
        String sql = "SELECT payslip_id, employee_name, department, payroll_period, "
                   + "gross_salary, net_salary, payroll_status "
                   + "FROM Monthly_Payroll_View ORDER BY payroll_period DESC, employee_name";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                rows.add(new Object[]{
                    rs.getInt("payslip_id"),
                    rs.getString("employee_name"),
                    rs.getString("department"),
                    rs.getString("payroll_period"),
                    String.format("₹%,.2f", rs.getDouble("gross_salary")),
                    String.format("₹%,.2f", rs.getDouble("net_salary")),
                    rs.getString("payroll_status")
                });
            }
        }
        return rows;
    }

    // ─── Private Helper ───────────────────────────────────────────────────────

    private Payslip mapPayslip(ResultSet rs) throws SQLException {
        return new Payslip(
            rs.getInt("payslip_id"),
            rs.getInt("emp_id"),
            rs.getString("employee_name"),
            rs.getString("department"),
            rs.getString("payroll_period"),
            rs.getDouble("basic_pay"),
            rs.getDouble("hra"),
            rs.getDouble("da"),
            rs.getDouble("bonus"),
            rs.getDouble("overtime_pay"),
            rs.getDouble("gross_salary"),
            rs.getDouble("pf_deduction"),
            rs.getDouble("professional_tax"),
            rs.getDouble("income_tax"),
            rs.getDouble("loss_of_pay"),
            rs.getDouble("total_deductions"),
            rs.getDouble("net_salary"),
            rs.getInt("days_present"),
            rs.getInt("days_absent"),
            rs.getString("payroll_status"),
            rs.getString("generated_by"),
            rs.getString("approved_by")
        );
    }
}
