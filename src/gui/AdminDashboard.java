package gui;

import dao.AttendanceDAO;
import dao.EmployeeDAO;
import dao.ReportDAO;
import dao.SalaryDAO;
import models.User;

import javax.swing.*;
import javax.swing.border.EmptyBorder;
import javax.swing.table.DefaultTableCellRenderer;
import javax.swing.table.DefaultTableModel;
import java.awt.*;
import java.awt.event.*;
import java.sql.Date;
import java.sql.SQLException;
import java.sql.Time;
import java.time.LocalDate;
import java.util.List;

import static gui.LoginFrame.*;

/**
 * AdminDashboard.java
 *
 * Main window for Admin, HR, and Manager roles.
 *
 * Layout:
 *   ┌──────────────┬─────────────────────────────────────────┐
 *   │  Sidebar     │  Main Content Area (CardLayout)         │
 *   │  - Dashboard │  ┌─────────────────────────────────────┐│
 *   │  - Employees │  │ Dashboard  / Employees / Attendance ││
 *   │  - Attendance│  │ / Payroll  / Reports                ││
 *   │  - Payroll   │  └─────────────────────────────────────┘│
 *   │  - Reports   │                                         │
 *   │  - Logout    │                                         │
 *   └──────────────┴─────────────────────────────────────────┘
 *
 * Interview talking points:
 *  - CardLayout swaps content panels without creating new windows.
 *  - DefaultTableModel is created fresh each time data is loaded.
 *  - SwingWorker keeps DB calls off the Event Dispatch Thread.
 */
public class AdminDashboard extends JFrame {

    private final User         currentUser;
    private final EmployeeDAO  empDAO     = new EmployeeDAO();
    private final AttendanceDAO attDAO    = new AttendanceDAO();
    private final SalaryDAO    salDAO     = new SalaryDAO();
    private final ReportDAO    reportDAO  = new ReportDAO();

    // Content panels managed by CardLayout
    private final CardLayout  cardLayout   = new CardLayout();
    private final JPanel      contentPanel = new JPanel(cardLayout);

    // Live stat labels for dashboard cards
    private JLabel totalEmpLabel;
    private JLabel todayAttLabel;
    private JLabel payslipLabel;

    public AdminDashboard(User user) {
        this.currentUser = user;
        setTitle("Payroll Manager — " + user.getRole() + " Dashboard | " + user.getUsername());
        setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        setSize(1100, 680);
        setLocationRelativeTo(null);
        setLayout(new BorderLayout());

        // Top header bar
        add(buildHeader(), BorderLayout.NORTH);

        // Left sidebar
        add(buildSidebar(), BorderLayout.WEST);

        // Build all content panels
        contentPanel.add(buildDashboardPanel(),  "Dashboard");
        contentPanel.add(buildEmployeesPanel(),  "Employees");
        contentPanel.add(buildAttendancePanel(), "Attendance");
        contentPanel.add(buildPayrollPanel(),    "Payroll");
        contentPanel.add(buildReportsPanel(),    "Reports");
        add(contentPanel, BorderLayout.CENTER);

        // Load dashboard stats asynchronously
        refreshDashboardStats();
    }

    // ─── Header Bar ───────────────────────────────────────────────────────────

    private JPanel buildHeader() {
        JPanel header = new JPanel(new BorderLayout());
        header.setBackground(PRIMARY_BLUE);
        header.setBorder(new EmptyBorder(12, 20, 12, 20));
        header.setPreferredSize(new Dimension(0, 56));

        JLabel logo = new JLabel("💼  Employee Payroll Management System");
        logo.setFont(new Font("Segoe UI", Font.BOLD, 16));
        logo.setForeground(WHITE);
        header.add(logo, BorderLayout.WEST);

        JLabel userInfo = new JLabel(currentUser.getRole() + " — " + currentUser.getUsername() + "  ");
        userInfo.setFont(new Font("Segoe UI", Font.PLAIN, 13));
        userInfo.setForeground(new Color(190, 220, 255));
        header.add(userInfo, BorderLayout.EAST);

        return header;
    }

    // ─── Left Sidebar ─────────────────────────────────────────────────────────

    private JPanel buildSidebar() {
        JPanel sidebar = new JPanel();
        sidebar.setLayout(new BoxLayout(sidebar, BoxLayout.Y_AXIS));
        sidebar.setBackground(new Color(30, 64, 110));
        sidebar.setBorder(new EmptyBorder(20, 0, 20, 0));
        sidebar.setPreferredSize(new Dimension(190, 0));

        String[][] navItems = {
            {"📊", "Dashboard"},
            {"👥", "Employees"},
            {"📋", "Attendance"},
            {"💰", "Payroll"},
            {"📄", "Reports"}
        };

        for (String[] item : navItems) {
            sidebar.add(makeSidebarButton(item[0] + "  " + item[1], item[1]));
            sidebar.add(Box.createVerticalStrut(4));
        }

        sidebar.add(Box.createVerticalGlue());

        JButton logoutBtn = new JButton("  🚪  Logout");
        logoutBtn.setFont(new Font("Segoe UI", Font.BOLD, 13));
        logoutBtn.setForeground(new Color(252, 129, 129));
        logoutBtn.setBackground(new Color(30, 64, 110));
        logoutBtn.setBorderPainted(false);
        logoutBtn.setFocusPainted(false);
        logoutBtn.setHorizontalAlignment(SwingConstants.LEFT);
        logoutBtn.setMaximumSize(new Dimension(Integer.MAX_VALUE, 44));
        logoutBtn.setCursor(Cursor.getPredefinedCursor(Cursor.HAND_CURSOR));
        logoutBtn.addActionListener(e -> confirmLogout());
        sidebar.add(logoutBtn);

        return sidebar;
    }

    private JButton makeSidebarButton(String label, String panelName) {
        JButton btn = new JButton(label);
        btn.setFont(new Font("Segoe UI", Font.PLAIN, 13));
        btn.setForeground(new Color(200, 225, 255));
        btn.setBackground(new Color(30, 64, 110));
        btn.setBorderPainted(false);
        btn.setFocusPainted(false);
        btn.setHorizontalAlignment(SwingConstants.LEFT);
        btn.setMaximumSize(new Dimension(Integer.MAX_VALUE, 44));
        btn.setBorder(new EmptyBorder(8, 20, 8, 12));
        btn.setCursor(Cursor.getPredefinedCursor(Cursor.HAND_CURSOR));
        btn.addMouseListener(new MouseAdapter() {
            @Override public void mouseEntered(MouseEvent e) {
                btn.setBackground(new Color(49, 130, 206, 80));
                btn.setForeground(WHITE);
            }
            @Override public void mouseExited(MouseEvent e) {
                btn.setBackground(new Color(30, 64, 110));
                btn.setForeground(new Color(200, 225, 255));
            }
        });
        btn.addActionListener(e -> {
            cardLayout.show(contentPanel, panelName);
            if ("Reports".equals(panelName))    loadReportsTable();
            if ("Employees".equals(panelName))  loadEmployeesTable();
            if ("Attendance".equals(panelName)) loadAttendanceTable();
        });
        return btn;
    }

    // ─── Dashboard Panel ──────────────────────────────────────────────────────

    private JPanel buildDashboardPanel() {
        JPanel panel = new JPanel(new BorderLayout());
        panel.setBackground(BG_LIGHT);
        panel.setBorder(new EmptyBorder(28, 28, 28, 28));

        JLabel title = new JLabel("Dashboard Overview");
        title.setFont(new Font("Segoe UI", Font.BOLD, 22));
        title.setForeground(TEXT_DARK);
        panel.add(title, BorderLayout.NORTH);

        // ── Stat cards ──
        JPanel cardsPanel = new JPanel(new GridLayout(1, 3, 20, 0));
        cardsPanel.setOpaque(false);
        cardsPanel.setBorder(new EmptyBorder(24, 0, 28, 0));

        totalEmpLabel = new JLabel("…");
        todayAttLabel = new JLabel("…");
        payslipLabel  = new JLabel("…");

        cardsPanel.add(makeStatCard("👥 Total Employees",    totalEmpLabel, ACCENT_BLUE));
        cardsPanel.add(makeStatCard("📋 Today's Attendance", todayAttLabel, SUCCESS_GREEN));
        cardsPanel.add(makeStatCard("📄 Payslips Generated", payslipLabel,  new Color(128, 90, 213)));
        panel.add(cardsPanel, BorderLayout.CENTER);

        // ── Quick action buttons ──
        JPanel actionsPanel = new JPanel(new GridLayout(2, 3, 16, 16));
        actionsPanel.setOpaque(false);
        actionsPanel.setBorder(BorderFactory.createTitledBorder(
            BorderFactory.createLineBorder(BORDER_COLOR),
            "  Quick Actions  ", 0, 0,
            new Font("Segoe UI", Font.BOLD, 12), TEXT_MUTED));

        actionsPanel.add(makeActionButton("➕  Add Employee",        e -> showAddEmployeeDialog()));
        actionsPanel.add(makeActionButton("👥  View Employees",       e -> { cardLayout.show(contentPanel, "Employees"); loadEmployeesTable(); }));
        actionsPanel.add(makeActionButton("📋  Mark Attendance",      e -> showMarkAttendanceDialog()));
        actionsPanel.add(makeActionButton("💰  Increment Salary",     e -> showIncrementSalaryDialog()));
        actionsPanel.add(makeActionButton("💼  Generate Payroll",     e -> showGeneratePayrollDialog()));
        actionsPanel.add(makeActionButton("📄  View Reports",         e -> { cardLayout.show(contentPanel, "Reports"); loadReportsTable(); }));

        panel.add(actionsPanel, BorderLayout.SOUTH);
        return panel;
    }

    private JPanel makeStatCard(String titleText, JLabel valueLabel, Color accentColor) {
        JPanel card = new JPanel(new BorderLayout());
        card.setBackground(WHITE);
        card.setBorder(BorderFactory.createCompoundBorder(
            BorderFactory.createMatteBorder(0, 4, 0, 0, accentColor),
            new EmptyBorder(20, 20, 20, 20)));

        JLabel titleLabel = new JLabel(titleText);
        titleLabel.setFont(new Font("Segoe UI", Font.BOLD, 13));
        titleLabel.setForeground(TEXT_MUTED);
        card.add(titleLabel, BorderLayout.NORTH);

        valueLabel.setFont(new Font("Segoe UI", Font.BOLD, 36));
        valueLabel.setForeground(accentColor);
        card.add(valueLabel, BorderLayout.CENTER);

        return card;
    }

    private JButton makeActionButton(String text, ActionListener al) {
        JButton btn = new RoundedButton(text, WHITE, TEXT_DARK);
        btn.setFont(new Font("Segoe UI", Font.BOLD, 13));
        btn.setBorder(BorderFactory.createCompoundBorder(
            BorderFactory.createLineBorder(BORDER_COLOR, 1),
            new EmptyBorder(14, 16, 14, 16)));
        btn.setBackground(WHITE);
        btn.setForeground(TEXT_DARK);
        btn.addActionListener(al);
        return btn;
    }

    // ─── Employees Panel ──────────────────────────────────────────────────────

    private JTable employeesTable;
    private DefaultTableModel employeesModel;

    private JPanel buildEmployeesPanel() {
        JPanel panel = new JPanel(new BorderLayout());
        panel.setBackground(BG_LIGHT);
        panel.setBorder(new EmptyBorder(24, 24, 24, 24));

        JLabel title = new JLabel("Employee Directory");
        title.setFont(new Font("Segoe UI", Font.BOLD, 20));
        title.setForeground(TEXT_DARK);

        JButton refreshBtn = new RoundedButton("🔄 Refresh", ACCENT_BLUE, WHITE);
        refreshBtn.addActionListener(e -> loadEmployeesTable());

        JButton addBtn = new RoundedButton("➕ Add Employee", SUCCESS_GREEN, WHITE);
        addBtn.addActionListener(e -> showAddEmployeeDialog());

        JPanel topBar = new JPanel(new BorderLayout());
        topBar.setOpaque(false);
        JPanel btnPanel = new JPanel(new FlowLayout(FlowLayout.RIGHT, 8, 0));
        btnPanel.setOpaque(false);
        btnPanel.add(refreshBtn);
        btnPanel.add(addBtn);
        topBar.add(title, BorderLayout.WEST);
        topBar.add(btnPanel, BorderLayout.EAST);
        panel.add(topBar, BorderLayout.NORTH);

        String[] cols = {"ID", "Name", "Department", "Designation", "Type",
                         "Status", "Email", "Basic Pay (₹)", "CTC/Month (₹)", "Role"};
        employeesModel = new DefaultTableModel(cols, 0) {
            @Override public boolean isCellEditable(int r, int c) { return false; }
        };
        employeesTable = buildStyledTable(employeesModel);
        panel.add(new JScrollPane(employeesTable), BorderLayout.CENTER);

        return panel;
    }

    private void loadEmployeesTable() {
        SwingWorker<List<Object[]>, Void> w = new SwingWorker<>() {
            @Override
            protected List<Object[]> doInBackground() throws Exception {
                return empDAO.getAllEmployees().stream().map(e -> new Object[]{
                    e.getEmpId(), e.getName(), e.getDepartment(), e.getDesignation(),
                    e.getEmpType(), e.getStatus(), e.getEmail(),
                    String.format("₹%,.2f", e.getBasicPay()),
                    String.format("₹%,.2f", e.getCtcMonthly()),
                    e.getSystemRole()
                }).toList();
            }
            @Override protected void done() {
                try {
                    employeesModel.setRowCount(0);
                    for (Object[] row : get()) employeesModel.addRow(row);
                } catch (Exception ex) { showError("Load Employees", ex); }
            }
        };
        w.execute();
    }

    // ─── Attendance Panel ─────────────────────────────────────────────────────

    private JTable attendanceTable;
    private DefaultTableModel attendanceModel;

    private JPanel buildAttendancePanel() {
        JPanel panel = new JPanel(new BorderLayout());
        panel.setBackground(BG_LIGHT);
        panel.setBorder(new EmptyBorder(24, 24, 24, 24));

        JLabel title = new JLabel("Today's Attendance");
        title.setFont(new Font("Segoe UI", Font.BOLD, 20));
        title.setForeground(TEXT_DARK);

        JButton markBtn = new RoundedButton("📋 Mark Attendance", ACCENT_BLUE, WHITE);
        markBtn.addActionListener(e -> showMarkAttendanceDialog());

        JButton refreshBtn = new RoundedButton("🔄 Refresh", new Color(200, 200, 200), TEXT_DARK);
        refreshBtn.addActionListener(e -> loadAttendanceTable());

        JPanel topBar = new JPanel(new BorderLayout());
        topBar.setOpaque(false);
        JPanel btnPanel = new JPanel(new FlowLayout(FlowLayout.RIGHT, 8, 0));
        btnPanel.setOpaque(false);
        btnPanel.add(refreshBtn);
        btnPanel.add(markBtn);
        topBar.add(title, BorderLayout.WEST);
        topBar.add(btnPanel, BorderLayout.EAST);
        panel.add(topBar, BorderLayout.NORTH);

        String[] cols = {"Emp ID", "Name", "Department", "Status", "Check-In", "Check-Out", "Hours"};
        attendanceModel = new DefaultTableModel(cols, 0) {
            @Override public boolean isCellEditable(int r, int c) { return false; }
        };
        attendanceTable = buildStyledTable(attendanceModel);
        panel.add(new JScrollPane(attendanceTable), BorderLayout.CENTER);

        return panel;
    }

    private void loadAttendanceTable() {
        SwingWorker<List<Object[]>, Void> w = new SwingWorker<>() {
            @Override protected List<Object[]> doInBackground() throws Exception {
                return attDAO.getTodayAttendance();
            }
            @Override protected void done() {
                try {
                    attendanceModel.setRowCount(0);
                    for (Object[] row : get()) attendanceModel.addRow(row);
                } catch (Exception ex) { showError("Load Attendance", ex); }
            }
        };
        w.execute();
    }

    // ─── Payroll Panel ────────────────────────────────────────────────────────

    private JPanel buildPayrollPanel() {
        JPanel panel = new JPanel(new BorderLayout());
        panel.setBackground(BG_LIGHT);
        panel.setBorder(new EmptyBorder(24, 24, 24, 24));

        JLabel title = new JLabel("Payroll Management");
        title.setFont(new Font("Segoe UI", Font.BOLD, 20));
        title.setForeground(TEXT_DARK);
        panel.add(title, BorderLayout.NORTH);

        JPanel centerPanel = new JPanel(new GridBagLayout());
        centerPanel.setBackground(BG_LIGHT);
        GridBagConstraints gbc = new GridBagConstraints();
        gbc.insets = new Insets(10, 10, 10, 10);
        gbc.fill = GridBagConstraints.HORIZONTAL;
        gbc.weightx = 1;

        JPanel card = new JPanel();
        card.setLayout(new BoxLayout(card, BoxLayout.Y_AXIS));
        card.setBackground(WHITE);
        card.setBorder(BorderFactory.createCompoundBorder(
            BorderFactory.createLineBorder(BORDER_COLOR),
            new EmptyBorder(30, 40, 30, 40)));

        JLabel info = new JLabel("<html><center>"
            + "<b style='font-size:14px'>Payroll Operations</b><br><br>"
            + "Use the buttons below to manage monthly payroll cycles.<br>"
            + "Payslips are generated using the payroll configuration<br>"
            + "stored in the database (PF, PT, Bonus, Overtime rates)."
            + "</center></html>");
        info.setFont(FONT_INPUT);
        info.setForeground(TEXT_MUTED);
        info.setAlignmentX(Component.CENTER_ALIGNMENT);
        card.add(info);
        card.add(Box.createVerticalStrut(24));

        JButton genBtn = new RoundedButton("💼  Generate Monthly Payroll (All Active Employees)",
                                           ACCENT_BLUE, WHITE);
        genBtn.setFont(new Font("Segoe UI", Font.BOLD, 13));
        genBtn.setAlignmentX(Component.CENTER_ALIGNMENT);
        genBtn.addActionListener(e -> showGeneratePayrollDialog());
        card.add(genBtn);
        card.add(Box.createVerticalStrut(16));

        JButton incBtn = new RoundedButton("💰  Apply Salary Increment for Employee",
                                           SUCCESS_GREEN, WHITE);
        incBtn.setFont(new Font("Segoe UI", Font.BOLD, 13));
        incBtn.setAlignmentX(Component.CENTER_ALIGNMENT);
        incBtn.addActionListener(e -> showIncrementSalaryDialog());
        card.add(incBtn);
        card.add(Box.createVerticalStrut(16));

        JButton rptBtn = new RoundedButton("📄  View All Payslip Reports",
                                           new Color(128, 90, 213), WHITE);
        rptBtn.setFont(new Font("Segoe UI", Font.BOLD, 13));
        rptBtn.setAlignmentX(Component.CENTER_ALIGNMENT);
        rptBtn.addActionListener(e -> { cardLayout.show(contentPanel, "Reports"); loadReportsTable(); });
        card.add(rptBtn);

        gbc.gridx = 0; gbc.gridy = 0;
        centerPanel.add(card, gbc);
        panel.add(centerPanel, BorderLayout.CENTER);

        return panel;
    }

    // ─── Reports Panel ────────────────────────────────────────────────────────

    private JTable reportsTable;
    private DefaultTableModel reportsModel;

    private JPanel buildReportsPanel() {
        JPanel panel = new JPanel(new BorderLayout());
        panel.setBackground(BG_LIGHT);
        panel.setBorder(new EmptyBorder(24, 24, 24, 24));

        JLabel title = new JLabel("Salary Reports");
        title.setFont(new Font("Segoe UI", Font.BOLD, 20));
        title.setForeground(TEXT_DARK);

        JButton refreshBtn = new RoundedButton("🔄 Refresh", ACCENT_BLUE, WHITE);
        refreshBtn.addActionListener(e -> loadReportsTable());

        JPanel topBar = new JPanel(new BorderLayout());
        topBar.setOpaque(false);
        topBar.add(title, BorderLayout.WEST);
        JPanel bp = new JPanel(new FlowLayout(FlowLayout.RIGHT)); bp.setOpaque(false);
        bp.add(refreshBtn); topBar.add(bp, BorderLayout.EAST);
        panel.add(topBar, BorderLayout.NORTH);

        String[] cols = {"Payslip ID", "Employee", "Department", "Period",
                         "Gross Salary", "Net Salary", "Status"};
        reportsModel = new DefaultTableModel(cols, 0) {
            @Override public boolean isCellEditable(int r, int c) { return false; }
        };
        reportsTable = buildStyledTable(reportsModel);

        // Color-code payroll status column
        reportsTable.getColumnModel().getColumn(6).setCellRenderer(new DefaultTableCellRenderer() {
            @Override
            public Component getTableCellRendererComponent(JTable t, Object val,
                    boolean sel, boolean foc, int row, int col) {
                super.getTableCellRendererComponent(t, val, sel, foc, row, col);
                String status = String.valueOf(val);
                setForeground(switch (status) {
                    case "Approved"  -> SUCCESS_GREEN;
                    case "Processed" -> ACCENT_BLUE;
                    case "Rejected"  -> ERROR_RED;
                    default          -> TEXT_MUTED;
                });
                setFont(getFont().deriveFont(Font.BOLD));
                return this;
            }
        });

        panel.add(new JScrollPane(reportsTable), BorderLayout.CENTER);
        return panel;
    }

    private void loadReportsTable() {
        SwingWorker<List<Object[]>, Void> w = new SwingWorker<>() {
            @Override protected List<Object[]> doInBackground() throws Exception {
                return reportDAO.getPayslipTableData();
            }
            @Override protected void done() {
                try {
                    reportsModel.setRowCount(0);
                    for (Object[] row : get()) reportsModel.addRow(row);
                } catch (Exception ex) { showError("Load Reports", ex); }
            }
        };
        w.execute();
    }

    // ─── Dashboard Stats Refresh ──────────────────────────────────────────────

    private void refreshDashboardStats() {
        SwingWorker<int[], Void> w = new SwingWorker<>() {
            @Override protected int[] doInBackground() throws Exception {
                return new int[]{
                    empDAO.getTotalActiveEmployees(),
                    empDAO.getTodayAttendanceCount(),
                    empDAO.getTotalPayslipCount()
                };
            }
            @Override protected void done() {
                try {
                    int[] stats = get();
                    totalEmpLabel.setText(String.valueOf(stats[0]));
                    todayAttLabel.setText(String.valueOf(stats[1]));
                    payslipLabel.setText(String.valueOf(stats[2]));
                } catch (Exception ex) { /* stat refresh is non-critical */ }
            }
        };
        w.execute();
    }

    // ─── Dialog: Add Employee ─────────────────────────────────────────────────

    private void showAddEmployeeDialog() {
        JDialog dialog = new JDialog(this, "Add New Employee", true);
        dialog.setSize(560, 620);
        dialog.setLocationRelativeTo(this);
        dialog.setLayout(new BorderLayout());

        JPanel form = new JPanel(new GridLayout(0, 2, 12, 10));
        form.setBorder(new EmptyBorder(20, 24, 10, 24));
        form.setBackground(WHITE);

        JTextField usernameF   = addFormRow(form, "Username *");
        JPasswordField passF   = new JPasswordField(); addLabelAndField(form, "Password *", passF);
        JTextField nameF       = addFormRow(form, "Full Name *");
        JTextField fnameF      = addFormRow(form, "First Name *");
        JTextField lnameF      = addFormRow(form, "Last Name *");
        JTextField deptF       = addFormRow(form, "Department *");
        JTextField desigF      = addFormRow(form, "Designation");
        JTextField emailF      = addFormRow(form, "Email *");
        JTextField phoneF      = addFormRow(form, "Phone");
        JComboBox<String> genderCb = new JComboBox<>(new String[]{"Male","Female","Other"});
        addLabelAndField(form, "Gender", genderCb);
        JComboBox<String> typeCb   = new JComboBox<>(new String[]{"Full-Time","Part-Time","Contract"});
        addLabelAndField(form, "Emp Type", typeCb);
        JTextField basicF      = addFormRow(form, "Basic Pay (₹) *");
        JTextField hraF        = addFormRow(form, "HRA (₹)");
        JTextField daF         = addFormRow(form, "DA (₹)");
        JTextField medF        = addFormRow(form, "Medical (₹)");
        JTextField specF       = addFormRow(form, "Special (₹)");

        dialog.add(new JScrollPane(form), BorderLayout.CENTER);

        JButton saveBtn = new RoundedButton("✔ Save Employee", SUCCESS_GREEN, WHITE);
        saveBtn.addActionListener(e -> {
            try {
                String username  = usernameF.getText().trim();
                String password  = new String(passF.getPassword());
                String name      = nameF.getText().trim();
                String fname     = fnameF.getText().trim();
                String lname     = lnameF.getText().trim();
                String dept      = deptF.getText().trim();
                String desig     = desigF.getText().trim();
                String email     = emailF.getText().trim();
                String phone     = phoneF.getText().trim();
                String gender    = (String) genderCb.getSelectedItem();
                String empType   = (String) typeCb.getSelectedItem();
                double basicPay  = Double.parseDouble(basicF.getText().trim());
                double hra       = hraF.getText().trim().isEmpty() ? 0 : Double.parseDouble(hraF.getText().trim());
                double da        = daF.getText().trim().isEmpty() ? 0 : Double.parseDouble(daF.getText().trim());
                double medical   = medF.getText().trim().isEmpty() ? 0 : Double.parseDouble(medF.getText().trim());
                double special   = specF.getText().trim().isEmpty() ? 0 : Double.parseDouble(specF.getText().trim());

                if (username.isEmpty() || password.isEmpty() || name.isEmpty()
                        || fname.isEmpty() || lname.isEmpty() || dept.isEmpty() || email.isEmpty()) {
                    JOptionPane.showMessageDialog(dialog, "Please fill all required fields (*).",
                            "Validation", JOptionPane.WARNING_MESSAGE);
                    return;
                }

                LocalDate today = LocalDate.now();
                int newId = empDAO.addEmployee(
                    currentUser.getUserId(), username, password, name, dept, desig, empType,
                    fname, lname, gender,
                    Date.valueOf(today.minusYears(25)),  // placeholder DOB
                    Date.valueOf(today),                  // hire_date = today
                    email, phone,
                    basicPay, hra, da, medical, special);

                JOptionPane.showMessageDialog(dialog,
                    "Employee added successfully!\nEmp ID: " + newId,
                    "Success", JOptionPane.INFORMATION_MESSAGE);
                dialog.dispose();
                refreshDashboardStats();
                loadEmployeesTable();

            } catch (NumberFormatException nfe) {
                JOptionPane.showMessageDialog(dialog, "Salary fields must be numeric.",
                        "Validation Error", JOptionPane.ERROR_MESSAGE);
            } catch (SQLException ex) {
                JOptionPane.showMessageDialog(dialog, ex.getMessage(),
                        "Database Error", JOptionPane.ERROR_MESSAGE);
            }
        });

        JButton cancelBtn = new RoundedButton("Cancel", new Color(240,240,240), TEXT_DARK);
        cancelBtn.addActionListener(e -> dialog.dispose());

        JPanel btnPanel = new JPanel(new FlowLayout(FlowLayout.RIGHT, 12, 12));
        btnPanel.setBackground(WHITE);
        btnPanel.add(cancelBtn); btnPanel.add(saveBtn);
        dialog.add(btnPanel, BorderLayout.SOUTH);
        dialog.setVisible(true);
    }

    // ─── Dialog: Mark Attendance ──────────────────────────────────────────────

    private void showMarkAttendanceDialog() {
        JDialog dialog = new JDialog(this, "Mark Attendance", true);
        dialog.setSize(400, 360);
        dialog.setLocationRelativeTo(this);
        dialog.setLayout(new BorderLayout());

        JPanel form = new JPanel(new GridLayout(0, 2, 12, 12));
        form.setBorder(new EmptyBorder(20, 24, 10, 24));
        form.setBackground(WHITE);

        JTextField empIdF  = addFormRow(form, "Employee ID *");
        JTextField dateF   = addFormRow(form, "Date (YYYY-MM-DD) *");
        dateF.setText(LocalDate.now().toString());

        JComboBox<String> statusCb = new JComboBox<>(
            new String[]{"Present","Absent","Late","Half-Day","Holiday","On-Leave"});
        addLabelAndField(form, "Status *", statusCb);

        JTextField checkInF  = addFormRow(form, "Check-In (HH:mm)");
        checkInF.setText("09:00");
        JTextField checkOutF = addFormRow(form, "Check-Out (HH:mm)");
        checkOutF.setText("18:00");
        JTextField remarksF  = addFormRow(form, "Remarks");

        dialog.add(form, BorderLayout.CENTER);

        JButton saveBtn = new RoundedButton("✔ Mark", ACCENT_BLUE, WHITE);
        saveBtn.addActionListener(e -> {
            try {
                int    empId   = Integer.parseInt(empIdF.getText().trim());
                Date   date    = Date.valueOf(dateF.getText().trim());
                String status  = (String) statusCb.getSelectedItem();
                String ciText  = checkInF.getText().trim();
                String coText  = checkOutF.getText().trim();
                Time   checkIn = ciText.isEmpty() ? null : Time.valueOf(ciText + ":00");
                Time checkOut  = coText.isEmpty() ? null : Time.valueOf(coText + ":00");

                attDAO.addAttendance(currentUser.getUserId(), empId, date,
                        status, checkIn, checkOut, remarksF.getText().trim());

                JOptionPane.showMessageDialog(dialog, "Attendance recorded successfully.",
                        "Success", JOptionPane.INFORMATION_MESSAGE);
                dialog.dispose();
                refreshDashboardStats();
            } catch (NumberFormatException nfe) {
                JOptionPane.showMessageDialog(dialog, "Employee ID must be a number.",
                        "Validation", JOptionPane.WARNING_MESSAGE);
            } catch (IllegalArgumentException iae) {
                JOptionPane.showMessageDialog(dialog,
                        "Invalid date or time format.\nUse YYYY-MM-DD and HH:mm.",
                        "Validation", JOptionPane.WARNING_MESSAGE);
            } catch (SQLException ex) {
                JOptionPane.showMessageDialog(dialog, ex.getMessage(),
                        "Database Error", JOptionPane.ERROR_MESSAGE);
            }
        });

        JButton cancelBtn = new RoundedButton("Cancel", new Color(240,240,240), TEXT_DARK);
        cancelBtn.addActionListener(e -> dialog.dispose());

        JPanel btnPanel = new JPanel(new FlowLayout(FlowLayout.RIGHT, 12, 12));
        btnPanel.setBackground(WHITE);
        btnPanel.add(cancelBtn); btnPanel.add(saveBtn);
        dialog.add(btnPanel, BorderLayout.SOUTH);
        dialog.setVisible(true);
    }

    // ─── Dialog: Increment Salary ─────────────────────────────────────────────

    private void showIncrementSalaryDialog() {
        JDialog dialog = new JDialog(this, "Apply Salary Increment", true);
        dialog.setSize(380, 280);
        dialog.setLocationRelativeTo(this);
        dialog.setLayout(new BorderLayout());

        JPanel form = new JPanel(new GridLayout(0, 2, 12, 12));
        form.setBorder(new EmptyBorder(20, 24, 10, 24));
        form.setBackground(WHITE);

        JTextField empIdF   = addFormRow(form, "Employee ID *");
        JTextField percentF = addFormRow(form, "Increment % *");
        JTextField reasonF  = addFormRow(form, "Reason *");
        reasonF.setText("Annual Review");

        dialog.add(form, BorderLayout.CENTER);

        JButton applyBtn = new RoundedButton("✔ Apply Increment", SUCCESS_GREEN, WHITE);
        applyBtn.addActionListener(e -> {
            try {
                int    empId   = Integer.parseInt(empIdF.getText().trim());
                double percent = Double.parseDouble(percentF.getText().trim());
                String reason  = reasonF.getText().trim();

                if (percent <= 0) {
                    JOptionPane.showMessageDialog(dialog, "Increment % must be greater than 0.",
                            "Validation", JOptionPane.WARNING_MESSAGE);
                    return;
                }
                salDAO.incrementSalary(currentUser.getUserId(), empId, percent, reason);
                double newBasic = salDAO.getCurrentBasicPay(empId);
                JOptionPane.showMessageDialog(dialog,
                    String.format("%.1f%% increment applied!\nNew Basic Pay: ₹%,.2f", percent, newBasic),
                    "Success", JOptionPane.INFORMATION_MESSAGE);
                dialog.dispose();
            } catch (NumberFormatException nfe) {
                JOptionPane.showMessageDialog(dialog, "Enter valid numeric values.",
                        "Validation", JOptionPane.WARNING_MESSAGE);
            } catch (SQLException ex) {
                JOptionPane.showMessageDialog(dialog, ex.getMessage(),
                        "Database Error", JOptionPane.ERROR_MESSAGE);
            }
        });

        JButton cancelBtn = new RoundedButton("Cancel", new Color(240,240,240), TEXT_DARK);
        cancelBtn.addActionListener(e -> dialog.dispose());

        JPanel btnPanel = new JPanel(new FlowLayout(FlowLayout.RIGHT, 12, 12));
        btnPanel.setBackground(WHITE);
        btnPanel.add(cancelBtn); btnPanel.add(applyBtn);
        dialog.add(btnPanel, BorderLayout.SOUTH);
        dialog.setVisible(true);
    }

    // ─── Dialog: Generate Payroll ─────────────────────────────────────────────

    private void showGeneratePayrollDialog() {
        JDialog dialog = new JDialog(this, "Generate Monthly Payroll", true);
        dialog.setSize(380, 240);
        dialog.setLocationRelativeTo(this);
        dialog.setLayout(new BorderLayout());

        JPanel form = new JPanel(new GridLayout(0, 2, 12, 12));
        form.setBorder(new EmptyBorder(20, 24, 10, 24));
        form.setBackground(WHITE);

        LocalDate now = LocalDate.now().minusMonths(1);
        JTextField monthF = addFormRow(form, "Month (1-12) *");
        monthF.setText(String.valueOf(now.getMonthValue()));
        JTextField yearF  = addFormRow(form, "Year *");
        yearF.setText(String.valueOf(now.getYear()));

        dialog.add(form, BorderLayout.CENTER);

        JButton genBtn = new RoundedButton("💼 Generate", ACCENT_BLUE, WHITE);
        genBtn.addActionListener(e -> {
            try {
                int month = Integer.parseInt(monthF.getText().trim());
                int year  = Integer.parseInt(yearF.getText().trim());

                if (month < 1 || month > 12) {
                    JOptionPane.showMessageDialog(dialog, "Month must be 1-12.",
                            "Validation", JOptionPane.WARNING_MESSAGE);
                    return;
                }

                int count = reportDAO.generateMonthlyPayroll(currentUser.getUserId(), month, year);
                JOptionPane.showMessageDialog(dialog,
                    "Payroll generated for " + count + " employees.",
                    "Payroll Complete", JOptionPane.INFORMATION_MESSAGE);
                dialog.dispose();
                refreshDashboardStats();
                loadReportsTable();
            } catch (NumberFormatException nfe) {
                JOptionPane.showMessageDialog(dialog, "Month and Year must be numbers.",
                        "Validation", JOptionPane.WARNING_MESSAGE);
            } catch (SQLException ex) {
                JOptionPane.showMessageDialog(dialog, ex.getMessage(),
                        "Database Error", JOptionPane.ERROR_MESSAGE);
            }
        });

        JButton cancelBtn = new RoundedButton("Cancel", new Color(240,240,240), TEXT_DARK);
        cancelBtn.addActionListener(e -> dialog.dispose());

        JPanel btnPanel = new JPanel(new FlowLayout(FlowLayout.RIGHT, 12, 12));
        btnPanel.setBackground(WHITE);
        btnPanel.add(cancelBtn); btnPanel.add(genBtn);
        dialog.add(btnPanel, BorderLayout.SOUTH);
        dialog.setVisible(true);
    }

    // ─── Logout ───────────────────────────────────────────────────────────────

    private void confirmLogout() {
        int choice = JOptionPane.showConfirmDialog(this,
            "Are you sure you want to logout?", "Confirm Logout",
            JOptionPane.YES_NO_OPTION, JOptionPane.QUESTION_MESSAGE);
        if (choice == JOptionPane.YES_OPTION) {
            dispose();
            SwingUtilities.invokeLater(() -> new LoginFrame().setVisible(true));
        }
    }

    // ─── Shared Table Builder ─────────────────────────────────────────────────

    static JTable buildStyledTable(DefaultTableModel model) {
        JTable table = new JTable(model);
        table.setFont(FONT_INPUT);
        table.setRowHeight(30);
        table.setGridColor(BORDER_COLOR);
        table.setIntercellSpacing(new Dimension(1, 1));
        table.setSelectionBackground(new Color(235, 244, 255));
        table.setSelectionForeground(TEXT_DARK);
        table.getTableHeader().setFont(FONT_LABEL);
        table.getTableHeader().setBackground(PRIMARY_BLUE);
        table.getTableHeader().setForeground(WHITE);
        table.getTableHeader().setBorder(BorderFactory.createEmptyBorder());
        table.setFillsViewportHeight(true);
        return table;
    }

    // ─── Form Helpers ─────────────────────────────────────────────────────────

    private JTextField addFormRow(JPanel panel, String labelText) {
        panel.add(makeLabel(labelText));
        JTextField field = makeTextField("");
        panel.add(field);
        return field;
    }

    private void addLabelAndField(JPanel panel, String labelText, JComponent comp) {
        panel.add(makeLabel(labelText));
        comp.setFont(FONT_INPUT);
        panel.add(comp);
    }

    private void showError(String ctx, Exception ex) {
        Throwable cause = ex.getCause() != null ? ex.getCause() : ex;
        JOptionPane.showMessageDialog(this, ctx + ": " + cause.getMessage(),
                "Error", JOptionPane.ERROR_MESSAGE);
    }
}
