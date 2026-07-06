package dao;

import util.DBConnection;

import java.sql.*;
import java.util.ArrayList;
import java.util.List;

/**
 * AttendanceDAO.java
 *
 * Data Access Object for all attendance-related database operations.
 * Uses existing stored procedures:
 *   - sp_add_attendance  — manual attendance (Admin / HR)
 *   - sp_check_in        — employee self check-in
 *   - sp_check_out       — employee self check-out
 *
 * Interview talking points:
 *  - CallableStatement maps Java types to MySQL IN/OUT parameters.
 *  - Stored procedures encapsulate business rules (Late detection,
 *    duplicate prevention) inside the database.
 */
public class AttendanceDAO {

    // ─── Manual Attendance Entry (Admin / HR) ─────────────────────────────────

    /**
     * Records attendance via sp_add_attendance stored procedure.
     *
     * @param callingUserId user_id of the Admin/HR performing the action
     * @param empId         employee whose attendance is being recorded
     * @param date          attendance date (SQL Date)
     * @param status        Present | Absent | Late | Half-Day | Holiday | On-Leave
     * @param checkIn       check-in time (may be null for Absent)
     * @param checkOut      check-out time (may be null)
     * @param remarks       optional notes
     * @throws SQLException with a readable message on failure
     */
    public void addAttendance(int callingUserId, int empId, java.sql.Date date,
                              String status, java.sql.Time checkIn,
                              java.sql.Time checkOut, String remarks) throws SQLException {

        String sql = "{CALL sp_add_attendance(?,?,?,?,?,?,?,?)}";

        try (Connection con = DBConnection.getConnection();
             CallableStatement cs = con.prepareCall(sql)) {

            cs.setInt(1,    callingUserId);
            cs.setInt(2,    empId);
            cs.setDate(3,   date);
            cs.setString(4, status);

            if (checkIn != null) cs.setTime(5, checkIn);
            else                 cs.setNull(5, Types.TIME);

            if (checkOut != null) cs.setTime(6, checkOut);
            else                  cs.setNull(6, Types.TIME);

            if (remarks != null && !remarks.isEmpty()) cs.setString(7, remarks);
            else                                        cs.setNull(7, Types.VARCHAR);

            cs.registerOutParameter(8, Types.VARCHAR);   // OUT p_message

            cs.execute();

            String message = cs.getString(8);
            if (message != null && message.toLowerCase().contains("error")) {
                throw new SQLException(message);
            }
        }
    }

    // ─── Self Check-In / Check-Out ────────────────────────────────────────────

    /**
     * Records an employee's check-in via sp_check_in.
     * The trigger in the database auto-marks the record as "Late"
     * if check-in time exceeds the configured threshold (09:15 by default).
     *
     * @param empId   the employee checking in
     * @param remarks optional notes
     * @throws SQLException if already checked-in today or DB error
     */
    public void checkIn(int empId, String remarks) throws SQLException {
        String sql = "{CALL sp_check_in(?,?,?)}";

        try (Connection con = DBConnection.getConnection();
             CallableStatement cs = con.prepareCall(sql)) {

            cs.setInt(1,    empId);
            cs.setString(2, remarks != null ? remarks : "");
            cs.registerOutParameter(3, Types.VARCHAR);   // OUT p_message

            cs.execute();
            String message = cs.getString(3);
            if (message != null && message.toLowerCase().contains("error")) {
                throw new SQLException(message);
            }
        }
    }

    /**
     * Records an employee's check-out via sp_check_out.
     * The trigger auto-computes working_hours and overtime_hours.
     *
     * @param empId the employee checking out
     * @throws SQLException if not checked-in today or DB error
     */
    public void checkOut(int empId) throws SQLException {
        String sql = "{CALL sp_check_out(?,?)}";

        try (Connection con = DBConnection.getConnection();
             CallableStatement cs = con.prepareCall(sql)) {

            cs.setInt(1, empId);
            cs.registerOutParameter(2, Types.VARCHAR);   // OUT p_message

            cs.execute();
            String message = cs.getString(2);
            if (message != null && message.toLowerCase().contains("error")) {
                throw new SQLException(message);
            }
        }
    }

    // ─── Attendance History ───────────────────────────────────────────────────

    /**
     * Returns attendance records for one employee.
     * Each Object[] row maps directly to JTable column order:
     * Date | Status | Check-In | Check-Out | Working Hours | Overtime | Remarks
     *
     * @param empId employee whose history is requested
     * @return list of Object arrays for JTable rendering
     * @throws SQLException on database errors
     */
    public List<Object[]> getAttendanceHistory(int empId) throws SQLException {
        List<Object[]> rows = new ArrayList<>();
        String sql = "SELECT date, status, check_in, check_out, working_hours, "
                   + "overtime_hours, remarks "
                   + "FROM Attendance WHERE emp_id = ? ORDER BY date DESC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, empId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    rows.add(new Object[]{
                        rs.getDate("date"),
                        rs.getString("status"),
                        rs.getTime("check_in"),
                        rs.getTime("check_out"),
                        rs.getDouble("working_hours"),
                        rs.getDouble("overtime_hours"),
                        rs.getString("remarks")
                    });
                }
            }
        }
        return rows;
    }

    /**
     * Returns all attendance records for today (admin-level overview).
     * Columns: Emp ID | Name | Department | Status | Check-In | Check-Out
     *
     * @return list of Object arrays for JTable rendering
     * @throws SQLException on database errors
     */
    public List<Object[]> getTodayAttendance() throws SQLException {
        List<Object[]> rows = new ArrayList<>();
        String sql = "SELECT a.emp_id, e.name, e.department, a.status, "
                   + "a.check_in, a.check_out, a.working_hours "
                   + "FROM Attendance a JOIN Employees e ON a.emp_id = e.emp_id "
                   + "WHERE a.date = CURDATE() ORDER BY e.department, e.name";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                rows.add(new Object[]{
                    rs.getInt("emp_id"),
                    rs.getString("name"),
                    rs.getString("department"),
                    rs.getString("status"),
                    rs.getTime("check_in"),
                    rs.getTime("check_out"),
                    rs.getDouble("working_hours")
                });
            }
        }
        return rows;
    }
}
