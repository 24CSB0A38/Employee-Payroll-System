import gui.LoginFrame;
import util.DBConnection;

import javax.swing.*;

/**
 * Main.java — Application Entry Point
 *
 * Responsibilities:
 *  1. Set the system look-and-feel for a native OS appearance.
 *  2. Test the database connection before opening any window.
 *  3. Launch LoginFrame on the Event Dispatch Thread (EDT).
 *
 * How to run (from the project root directory):
 *
 *   Compile:
 *     javac -cp "lib/mysql-connector-j.jar" -d out \
 *           src/util/*.java src/models/*.java src/dao/*.java src/gui/*.java src/Main.java
 *
 *   Run:
 *     java -cp "out:lib/mysql-connector-j.jar" Main
 *
 *   On Windows (use semicolons):
 *     java -cp "out;lib/mysql-connector-j.jar" Main
 *
 * Interview talking points:
 *  - SwingUtilities.invokeLater() ensures all Swing code runs on the EDT.
 *  - UIManager.setLookAndFeel() applies the platform's native styling.
 *  - A DB connectivity check at startup gives a friendly error
 *    rather than a cryptic NullPointerException inside a DAO.
 */
public class Main {

    public static void main(String[] args) {

        // ── 1. Apply System Look-and-Feel ─────────────────────────────────────
        try {
            UIManager.setLookAndFeel(UIManager.getSystemLookAndFeelClassName());
        } catch (Exception e) {
            // Silently fall back to cross-platform L&F
        }

        // ── 2. Validate Database Connectivity ─────────────────────────────────
        if (!DBConnection.testConnection()) {
            // Show error dialog before any window opens
            JOptionPane.showMessageDialog(null,
                "⚠  Cannot connect to the database!\n\n"
              + "Please verify the following:\n"
              + "  1. MySQL server is running on localhost:3306\n"
              + "  2. Database 'payroll_db' exists and is populated\n"
              + "     (run payroll_enterprise.sql if not done yet)\n"
              + "  3. Credentials in src/util/DBConnection.java are correct\n\n"
              + "The application will open in limited mode (UI preview only).",
                "Database Connection Failed",
                JOptionPane.WARNING_MESSAGE);
        }

        // ── 3. Launch Login Window on EDT ─────────────────────────────────────
        SwingUtilities.invokeLater(() -> {
            LoginFrame loginFrame = new LoginFrame();
            loginFrame.setVisible(true);
        });
    }
}
