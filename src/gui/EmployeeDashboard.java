package gui;

import dao.AttendanceDAO;
import dao.EmployeeDAO;
import dao.ReportDAO;
import models.Employee;
import models.Payslip;
import models.User;

import javax.swing.*;
import javax.swing.border.EmptyBorder;
import javax.swing.table.DefaultTableModel;
import java.awt.*;
import java.sql.SQLException;
import java.util.List;

import static gui.AdminDashboard.buildStyledTable;
import static gui.LoginFrame.*;

/**
 * EmployeeDashboard.java
 *
 * Self-service window displayed to employees after login.
 *
 * Features:
 *  - View personal profile (basic fields read from Employee_Profile_View)
 *  - Attendance History  (JTable from Attendance, descending by date)
 *  - Salary Reports      (JTable from Monthly_Payroll_View for this employee)
 *  - Check-In / Check-Out buttons (use sp_check_in / sp_check_out)
 *
 * Interview talking points:
 *  - Employee can only see their own data — empId is bound at construction.
 *  - All DB calls are on SwingWorker threads (never block the EDT).
 *  - JTabbedPane provides a clean, minimal multi-view layout.
 */
public class EmployeeDashboard extends JFrame {

    private final User          currentUser;
    private final int           empId;
    private final EmployeeDAO   empDAO    = new EmployeeDAO();
    private final AttendanceDAO attDAO    = new AttendanceDAO();
    private final ReportDAO     reportDAO = new ReportDAO();

    public EmployeeDashboard(User user, int empId) {
        this.currentUser = user;
        this.empId       = empId;

        setTitle("Payroll Manager — " + user.getUsername() + " (Employee)");
        setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        setSize(900, 620);
        setLocationRelativeTo(null);
        setLayout(new BorderLayout());

        add(buildHeader(), BorderLayout.NORTH);

        JTabbedPane tabs = new JTabbedPane();
        tabs.setFont(new Font("Segoe UI", Font.BOLD, 13));
        tabs.setBackground(BG_LIGHT);

        tabs.addTab("👤  My Profile",        buildProfilePanel());
        tabs.addTab("📋  Attendance History", buildAttendancePanel());
        tabs.addTab("💰  Salary Reports",     buildSalaryPanel());

        add(tabs, BorderLayout.CENTER);
        add(buildFooterBar(), BorderLayout.SOUTH);
    }

    // ─── Header ───────────────────────────────────────────────────────────────

    private JPanel buildHeader() {
        JPanel header = new JPanel(new BorderLayout());
        header.setBackground(PRIMARY_BLUE);
        header.setBorder(new EmptyBorder(12, 20, 12, 20));
        header.setPreferredSize(new Dimension(0, 56));

        JLabel logo = new JLabel("💼  Employee Payroll Management System");
        logo.setFont(new Font("Segoe UI", Font.BOLD, 16));
        logo.setForeground(WHITE);
        header.add(logo, BorderLayout.WEST);

        JLabel userInfo = new JLabel("Employee — " + currentUser.getUsername() + "  ");
        userInfo.setFont(new Font("Segoe UI", Font.PLAIN, 13));
        userInfo.setForeground(new Color(190, 220, 255));
        header.add(userInfo, BorderLayout.EAST);

        return header;
    }

    // ─── Footer Bar (Check-In / Check-Out / Logout) ───────────────────────────

    private JPanel buildFooterBar() {
        JPanel footer = new JPanel(new FlowLayout(FlowLayout.RIGHT, 14, 10));
        footer.setBackground(new Color(240, 245, 250));
        footer.setBorder(BorderFactory.createMatteBorder(1, 0, 0, 0, BORDER_COLOR));

        JButton checkInBtn = new RoundedButton("✅  Check In", SUCCESS_GREEN, WHITE);
        checkInBtn.addActionListener(e -> performCheckIn());
        footer.add(checkInBtn);

        JButton checkOutBtn = new RoundedButton("🚪  Check Out", ACCENT_BLUE, WHITE);
        checkOutBtn.addActionListener(e -> performCheckOut());
        footer.add(checkOutBtn);

        JButton logoutBtn = new RoundedButton("Logout", new Color(240, 240, 240), TEXT_DARK);
        logoutBtn.addActionListener(e -> {
            dispose();
            SwingUtilities.invokeLater(() -> new LoginFrame().setVisible(true));
        });
        footer.add(logoutBtn);

        return footer;
    }

    // ─── Profile Panel ────────────────────────────────────────────────────────

    private JPanel profilePanel;
    private JLabel[] profileValues;

    private JPanel buildProfilePanel() {
        profilePanel = new JPanel(new BorderLayout());
        profilePanel.setBackground(BG_LIGHT);
        profilePanel.setBorder(new EmptyBorder(24, 24, 24, 24));

        JPanel card = new JPanel(new GridBagLayout());
        card.setBackground(WHITE);
        card.setBorder(BorderFactory.createCompoundBorder(
            BorderFactory.createLineBorder(BORDER_COLOR),
            new EmptyBorder(24, 32, 24, 32)));

        GridBagConstraints gbc = new GridBagConstraints();
        gbc.anchor = GridBagConstraints.WEST;
        gbc.insets = new Insets(8, 10, 8, 10);

        String[] labels = {
            "Employee ID", "Full Name", "Department", "Designation", "Type",
            "Status", "Email", "Phone", "Basic Pay", "CTC / Month", "Username", "Role"
        };

        profileValues = new JLabel[labels.length];

        for (int i = 0; i < labels.length; i++) {
            gbc.gridx = 0; gbc.gridy = i; gbc.weightx = 0;
            JLabel lbl = new JLabel(labels[i] + ":");
            lbl.setFont(FONT_LABEL);
            lbl.setForeground(TEXT_MUTED);
            lbl.setPreferredSize(new Dimension(140, 24));
            card.add(lbl, gbc);

            gbc.gridx = 1; gbc.weightx = 1;
            profileValues[i] = new JLabel("Loading…");
            profileValues[i].setFont(FONT_INPUT);
            profileValues[i].setForeground(TEXT_DARK);
            card.add(profileValues[i], gbc);
        }

        profilePanel.add(card, BorderLayout.CENTER);

        // Load on EDT-safe background thread
        loadProfile();
        return profilePanel;
    }

    private void loadProfile() {
        SwingWorker<Employee, Void> w = new SwingWorker<>() {
            @Override protected Employee doInBackground() throws Exception {
                return empDAO.getEmployeeById(empId);
            }
            @Override protected void done() {
                try {
                    Employee emp = get();
                    if (emp == null) { populateProfile(null); return; }
                    populateProfile(emp);
                } catch (Exception ex) {
                    for (JLabel v : profileValues) v.setText("Error loading profile");
                }
            }
        };
        w.execute();
    }

    private void populateProfile(Employee emp) {
        if (emp == null) {
            for (JLabel v : profileValues) v.setText("—");
            return;
        }
        String[] values = {
            String.valueOf(emp.getEmpId()),
            emp.getName(),
            emp.getDepartment(),
            emp.getDesignation() != null ? emp.getDesignation() : "—",
            emp.getEmpType(),
            emp.getStatus(),
            emp.getEmail(),
            emp.getPhone() != null ? emp.getPhone() : "—",
            String.format("₹%,.2f", emp.getBasicPay()),
            String.format("₹%,.2f", emp.getCtcMonthly()),
            emp.getUsername(),
            emp.getSystemRole()
        };
        for (int i = 0; i < profileValues.length; i++) {
            profileValues[i].setText(values[i]);
        }
    }

    // ─── Attendance History Panel ─────────────────────────────────────────────

    private DefaultTableModel attendanceModel;

    private JPanel buildAttendancePanel() {
        JPanel panel = new JPanel(new BorderLayout());
        panel.setBackground(BG_LIGHT);
        panel.setBorder(new EmptyBorder(20, 20, 20, 20));

        JLabel title = new JLabel("My Attendance History");
        title.setFont(new Font("Segoe UI", Font.BOLD, 18));
        title.setForeground(TEXT_DARK);

        JButton refreshBtn = new RoundedButton("🔄 Refresh", ACCENT_BLUE, WHITE);
        refreshBtn.addActionListener(e -> loadAttendanceHistory());

        JPanel topBar = new JPanel(new BorderLayout());
        topBar.setOpaque(false);
        topBar.add(title, BorderLayout.WEST);
        JPanel bp = new JPanel(new FlowLayout(FlowLayout.RIGHT)); bp.setOpaque(false);
        bp.add(refreshBtn); topBar.add(bp, BorderLayout.EAST);
        panel.add(topBar, BorderLayout.NORTH);

        String[] cols = {"Date", "Status", "Check-In", "Check-Out", "Hours Worked", "Overtime", "Remarks"};
        attendanceModel = new DefaultTableModel(cols, 0) {
            @Override public boolean isCellEditable(int r, int c) { return false; }
        };
        JTable table = buildStyledTable(attendanceModel);
        panel.add(new JScrollPane(table), BorderLayout.CENTER);

        loadAttendanceHistory();
        return panel;
    }

    private void loadAttendanceHistory() {
        SwingWorker<List<Object[]>, Void> w = new SwingWorker<>() {
            @Override protected List<Object[]> doInBackground() throws Exception {
                return attDAO.getAttendanceHistory(empId);
            }
            @Override protected void done() {
                try {
                    attendanceModel.setRowCount(0);
                    for (Object[] row : get()) attendanceModel.addRow(row);
                } catch (Exception ex) {
                    JOptionPane.showMessageDialog(EmployeeDashboard.this,
                        "Could not load attendance: " + ex.getMessage(),
                        "Error", JOptionPane.ERROR_MESSAGE);
                }
            }
        };
        w.execute();
    }

    // ─── Salary Reports Panel ─────────────────────────────────────────────────

    private DefaultTableModel salaryModel;

    private JPanel buildSalaryPanel() {
        JPanel panel = new JPanel(new BorderLayout());
        panel.setBackground(BG_LIGHT);
        panel.setBorder(new EmptyBorder(20, 20, 20, 20));

        JLabel title = new JLabel("My Salary Reports");
        title.setFont(new Font("Segoe UI", Font.BOLD, 18));
        title.setForeground(TEXT_DARK);

        JButton refreshBtn = new RoundedButton("🔄 Refresh", ACCENT_BLUE, WHITE);
        refreshBtn.addActionListener(e -> loadSalaryReports());

        JButton detailBtn = new RoundedButton("📋 View Details", SUCCESS_GREEN, WHITE);
        detailBtn.addActionListener(e -> showPayslipDetail());

        JPanel topBar = new JPanel(new BorderLayout());
        topBar.setOpaque(false);
        JPanel bp = new JPanel(new FlowLayout(FlowLayout.RIGHT, 8, 0));
        bp.setOpaque(false);
        bp.add(refreshBtn); bp.add(detailBtn);
        topBar.add(title, BorderLayout.WEST);
        topBar.add(bp, BorderLayout.EAST);
        panel.add(topBar, BorderLayout.NORTH);

        String[] cols = {"Payslip ID", "Period", "Gross Salary", "Net Salary",
                         "Days Present", "Days Absent", "Status"};
        salaryModel = new DefaultTableModel(cols, 0) {
            @Override public boolean isCellEditable(int r, int c) { return false; }
        };
        JTable table = buildStyledTable(salaryModel);
        panel.add(new JScrollPane(table), BorderLayout.CENTER);

        // Hint label
        JLabel hint = new JLabel("  Select a row and click 'View Details' for a full breakdown.");
        hint.setFont(FONT_SMALL);
        hint.setForeground(TEXT_MUTED);
        panel.add(hint, BorderLayout.SOUTH);

        loadSalaryReports();
        return panel;
    }

    private List<Payslip> cachedPayslips;

    private void loadSalaryReports() {
        SwingWorker<List<Payslip>, Void> w = new SwingWorker<>() {
            @Override protected List<Payslip> doInBackground() throws Exception {
                return reportDAO.getPayslipsByEmployee(empId);
            }
            @Override protected void done() {
                try {
                    cachedPayslips = get();
                    salaryModel.setRowCount(0);
                    for (Payslip p : cachedPayslips) {
                        salaryModel.addRow(new Object[]{
                            p.getPayslipId(),
                            p.getPayrollPeriod(),
                            String.format("₹%,.2f", p.getGrossSalary()),
                            String.format("₹%,.2f", p.getNetSalary()),
                            p.getDaysPresent(),
                            p.getDaysAbsent(),
                            p.getPayrollStatus()
                        });
                    }
                } catch (Exception ex) {
                    JOptionPane.showMessageDialog(EmployeeDashboard.this,
                        "Could not load payslips: " + ex.getMessage(),
                        "Error", JOptionPane.ERROR_MESSAGE);
                }
            }
        };
        w.execute();
    }

    private void showPayslipDetail() {
        if (cachedPayslips == null || cachedPayslips.isEmpty()) {
            JOptionPane.showMessageDialog(this, "No payslips to display.", "Info",
                    JOptionPane.INFORMATION_MESSAGE);
            return;
        }

        // Use the most recent payslip (index 0, ordered DESC)
        Payslip p = cachedPayslips.get(0);

        String detail = String.format(
            "═══════════════════════════════════════\n"
          + "     PAYSLIP — %s\n"
          + "═══════════════════════════════════════\n"
          + "Employee   : %s\n"
          + "Department : %s\n"
          + "Period     : %s\n"
          + "Status     : %s\n"
          + "───────────────────────────────────────\n"
          + "EARNINGS\n"
          + "  Basic Pay          : ₹%,.2f\n"
          + "  HRA                : ₹%,.2f\n"
          + "  DA                 : ₹%,.2f\n"
          + "  Bonus              : ₹%,.2f\n"
          + "  Overtime Pay       : ₹%,.2f\n"
          + "  ─────────────────────────────\n"
          + "  Gross Salary       : ₹%,.2f\n"
          + "───────────────────────────────────────\n"
          + "DEDUCTIONS\n"
          + "  PF (12%%)          : ₹%,.2f\n"
          + "  Professional Tax   : ₹%,.2f\n"
          + "  Income Tax (TDS)   : ₹%,.2f\n"
          + "  Loss of Pay (LOP)  : ₹%,.2f\n"
          + "  ─────────────────────────────\n"
          + "  Total Deductions   : ₹%,.2f\n"
          + "───────────────────────────────────────\n"
          + "  NET SALARY         : ₹%,.2f\n"
          + "───────────────────────────────────────\n"
          + "ATTENDANCE\n"
          + "  Days Present : %d   Days Absent : %d\n"
          + "═══════════════════════════════════════",
            p.getEmployeeName(),
            p.getEmployeeName(), p.getDepartment(), p.getPayrollPeriod(), p.getPayrollStatus(),
            p.getBasicPay(), p.getHra(), p.getDa(), p.getBonus(), p.getOvertimePay(),
            p.getGrossSalary(),
            p.getPfDeduction(), p.getProfessionalTax(), p.getIncomeTax(), p.getLossOfPay(),
            p.getTotalDeductions(),
            p.getNetSalary(),
            p.getDaysPresent(), p.getDaysAbsent()
        );

        JTextArea ta = new JTextArea(detail);
        ta.setFont(new Font("Monospaced", Font.PLAIN, 12));
        ta.setEditable(false);
        ta.setBackground(BG_LIGHT);
        JScrollPane sp = new JScrollPane(ta);
        sp.setPreferredSize(new Dimension(480, 480));

        JOptionPane.showMessageDialog(this, sp, "Payslip Detail — " + p.getPayrollPeriod(),
                JOptionPane.PLAIN_MESSAGE);
    }

    // ─── Check-In / Check-Out ─────────────────────────────────────────────────

    private void performCheckIn() {
        try {
            attDAO.checkIn(empId, "Self check-in");
            JOptionPane.showMessageDialog(this, "✅ Checked in successfully!",
                    "Check-In", JOptionPane.INFORMATION_MESSAGE);
        } catch (SQLException ex) {
            JOptionPane.showMessageDialog(this, ex.getMessage(),
                    "Check-In Error", JOptionPane.ERROR_MESSAGE);
        }
    }

    private void performCheckOut() {
        try {
            attDAO.checkOut(empId);
            JOptionPane.showMessageDialog(this, "🚪 Checked out successfully!",
                    "Check-Out", JOptionPane.INFORMATION_MESSAGE);
            loadAttendanceHistory();
        } catch (SQLException ex) {
            JOptionPane.showMessageDialog(this, ex.getMessage(),
                    "Check-Out Error", JOptionPane.ERROR_MESSAGE);
        }
    }
}
