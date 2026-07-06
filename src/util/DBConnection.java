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
 * MySQL instance : /Users/apple/Documents/nodejs-express-mysql/.local/mysql-8.4.10-macos15-arm64
 * Data directory : .local/mysql-data
 * Socket         : .local/mysql-run/mysql.sock
 * TCP port       : 3306 (bound to all interfaces)
 *
 * Interview talking points:
 *  - DriverManager.getConnection() establishes a JDBC connection.
 *  - We use 127.0.0.1 (loopback IP) instead of "localhost" so JDBC uses
 *    TCP instead of a Unix socket — works reliably on all platforms.
 *  - Credentials are stored as constants for easy configuration.
 *  - Every caller is responsible for closing its own Connection.
 */
public class DBConnection {

    // ─── Database Configuration ───────────────────────────────────────────────
    // Using 127.0.0.1 forces TCP/IP connection (avoids Unix socket lookup)
    private static final String URL      = "jdbc:mysql://127.0.0.1:3306/payroll_db"
                                           + "?useSSL=false"
                                           + "&serverTimezone=Asia/Kolkata"
                                           + "&allowPublicKeyRetrieval=true"
                                           + "&autoReconnect=true";
    private static final String USERNAME = "root";
    private static final String PASSWORD = "123456";
    // ──────────────────────────────────────────────────────────────────────────

    static {
        try {
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
     *
     * @return true if a connection was successfully obtained and closed
     */
    public static boolean testConnection() {
        try (Connection con = getConnection()) {
            return con != null && !con.isClosed();
        } catch (SQLException e) {
            System.err.println("[DBConnection] Test failed: " + e.getMessage());
            return false;
        }
    }
}
