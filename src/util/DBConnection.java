package util;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;

/**
 * DBConnection.java
 * 
 * Centralized JDBC connection manager for the Payroll Management System.
 * All DAO classes obtain a Connection from this class.
 * 
 * Interview talking points:
 *  - DriverManager.getConnection() establishes a JDBC connection.
 *  - Connection strings carry host, port, and database info.
 *  - Credentials are stored as constants for easy configuration.
 *  - Every caller is responsible for closing its own Connection.
 */
public class DBConnection {

    // ─── Configure these constants to match your MySQL installation ───────────
    private static final String URL      = "jdbc:mysql://localhost:3306/payroll_db"
                                           + "?useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true";
    private static final String USERNAME = "root";
    private static final String PASSWORD = "root"; // ← change to your MySQL password
    // ──────────────────────────────────────────────────────────────────────────

    static {
        try {
            // Explicitly load the MySQL JDBC driver (good practice for Java 8 and below;
            // optional in Java 9+ but shows understanding in interviews)
            Class.forName("com.mysql.cj.jdbc.Driver");
        } catch (ClassNotFoundException e) {
            System.err.println("[DBConnection] MySQL JDBC Driver not found: " + e.getMessage());
        }
    }

    /**
     * Returns a new Connection to payroll_db.
     * Caller must close() the connection after use (try-with-resources recommended).
     *
     * @return live Connection, never null
     * @throws SQLException if the database is unreachable or credentials are wrong
     */
    public static Connection getConnection() throws SQLException {
        return DriverManager.getConnection(URL, USERNAME, PASSWORD);
    }

    /**
     * Quick connectivity test used on application startup.
     * Displays a friendly error dialog and returns false when the DB is down.
     *
     * @return true if a connection was successfully obtained and closed
     */
    public static boolean testConnection() {
        try (Connection con = getConnection()) {
            return con != null && !con.isClosed();
        } catch (SQLException e) {
            return false;
        }
    }
}
