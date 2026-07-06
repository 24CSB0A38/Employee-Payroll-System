package gui;

import dao.EmployeeDAO;
import models.User;
import util.DBConnection;

import javax.swing.*;
import javax.swing.border.EmptyBorder;
import java.awt.*;
import java.awt.event.*;
import java.sql.SQLException;

/**
 * LoginFrame.java
 *
 * Entry-point GUI window for the Employee Payroll Management System.
 *
 * Design decisions:
 *  - Uses a two-panel layout: left branding panel + right form panel.
 *  - JPasswordField.getPassword() is used (safer than getText()).
 *  - Role-based redirect: Admin/HR/Manager → AdminDashboard,
 *                         Employee → EmployeeDashboard.
 *  - DB connectivity is checked once at startup with a friendly error dialog.
 *
 * Interview talking points:
 *  - Event-driven programming via ActionListener.
 *  - SwingUtilities.invokeLater() ensures GUI runs on Event Dispatch Thread.
 *  - new String(passwordField.getPassword()) converts char[] to String for
 *    handing to DAO (which passes it to the stored procedure for SHA-256 hashing).
 */
public class LoginFrame extends JFrame {

    // ─── UI Theme Constants ───────────────────────────────────────────────────
    static final Color PRIMARY_BLUE   = new Color(26, 54, 93);   // #1A365D
    static final Color ACCENT_BLUE    = new Color(49, 130, 206); // #3182CE
    static final Color LIGHT_BLUE     = new Color(235, 248, 255);// #EBF8FF
    static final Color WHITE          = Color.WHITE;
    static final Color TEXT_DARK      = new Color(45, 55, 72);   // #2D3748
    static final Color TEXT_MUTED     = new Color(113, 128, 150);// #718096
    static final Color BORDER_COLOR   = new Color(226, 232, 240);// #E2E8F0
    static final Color SUCCESS_GREEN  = new Color(56, 161, 105); // #38A169
    static final Color ERROR_RED      = new Color(229, 62, 62);  // #E53E3E
    static final Color BG_LIGHT       = new Color(247, 250, 252);// #F7FAFC

    static final Font FONT_TITLE  = new Font("Segoe UI", Font.BOLD,  24);
    static final Font FONT_LABEL  = new Font("Segoe UI", Font.BOLD,  13);
    static final Font FONT_INPUT  = new Font("Segoe UI", Font.PLAIN, 13);
    static final Font FONT_BUTTON = new Font("Segoe UI", Font.BOLD,  14);
    static final Font FONT_SMALL  = new Font("Segoe UI", Font.PLAIN, 11);

    // ─── DAO ──────────────────────────────────────────────────────────────────
    private final EmployeeDAO employeeDAO = new EmployeeDAO();

    // ─── Form Components ──────────────────────────────────────────────────────
    private JTextField     usernameField;
    private JPasswordField passwordField;
    private JButton        loginButton;
    private JLabel         statusLabel;

    // ─── Constructor ──────────────────────────────────────────────────────────

    public LoginFrame() {
        setTitle("Employee Payroll System — Login");
        setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        setSize(820, 500);
        setLocationRelativeTo(null);            // Center on screen
        setResizable(false);
        setLayout(new GridLayout(1, 2));

        add(buildBrandingPanel());
        add(buildFormPanel());

        // Check DB connectivity on startup
        if (!DBConnection.testConnection()) {
            SwingUtilities.invokeLater(() ->
                JOptionPane.showMessageDialog(this,
                    "Cannot connect to the database.\n\n"
                  + "Please check:\n"
                  + "  1. MySQL server is running.\n"
                  + "  2. Credentials in DBConnection.java are correct.\n"
                  + "  3. payroll_db schema is loaded.",
                    "Database Connection Failed",
                    JOptionPane.ERROR_MESSAGE)
            );
        }
    }

    // ─── Left Branding Panel ──────────────────────────────────────────────────

    private JPanel buildBrandingPanel() {
        JPanel panel = new JPanel(new GridBagLayout()) {
            @Override
            protected void paintComponent(Graphics g) {
                super.paintComponent(g);
                // Gradient background: dark blue → medium blue
                Graphics2D g2 = (Graphics2D) g;
                g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING,
                                    RenderingHints.VALUE_ANTIALIAS_ON);
                GradientPaint gp = new GradientPaint(
                    0, 0, PRIMARY_BLUE,
                    0, getHeight(), ACCENT_BLUE);
                g2.setPaint(gp);
                g2.fillRect(0, 0, getWidth(), getHeight());
            }
        };

        GridBagConstraints gbc = new GridBagConstraints();
        gbc.gridx = 0; gbc.gridy = GridBagConstraints.RELATIVE;
        gbc.anchor = GridBagConstraints.CENTER;
        gbc.insets = new Insets(8, 20, 8, 20);

        // Logo icon (Unicode fallback)
        JLabel iconLabel = new JLabel("💼");
        iconLabel.setFont(new Font("Segoe UI Emoji", Font.PLAIN, 56));
        iconLabel.setHorizontalAlignment(SwingConstants.CENTER);
        panel.add(iconLabel, gbc);

        JLabel titleLabel = new JLabel("Payroll Manager");
        titleLabel.setFont(new Font("Segoe UI", Font.BOLD, 22));
        titleLabel.setForeground(WHITE);
        panel.add(titleLabel, gbc);

        JLabel subLabel = new JLabel("Enterprise HR System");
        subLabel.setFont(new Font("Segoe UI", Font.PLAIN, 13));
        subLabel.setForeground(new Color(190, 220, 255));
        panel.add(subLabel, gbc);

        JSeparator sep = new JSeparator();
        sep.setForeground(new Color(255, 255, 255, 60));
        sep.setPreferredSize(new Dimension(180, 1));
        panel.add(sep, gbc);

        // Feature bullets
        String[] features = {"🔐 Role-Based Access Control",
                             "📊 Attendance Tracking",
                             "💰 Automated Payroll",
                             "📈 Salary Reports"};
        for (String f : features) {
            JLabel feat = new JLabel(f);
            feat.setFont(new Font("Segoe UI", Font.PLAIN, 12));
            feat.setForeground(new Color(200, 230, 255));
            panel.add(feat, gbc);
        }

        return panel;
    }

    // ─── Right Login Form Panel ───────────────────────────────────────────────

    private JPanel buildFormPanel() {
        JPanel outer = new JPanel(new GridBagLayout());
        outer.setBackground(BG_LIGHT);

        JPanel card = new JPanel();
        card.setLayout(new BoxLayout(card, BoxLayout.Y_AXIS));
        card.setBackground(WHITE);
        card.setBorder(BorderFactory.createCompoundBorder(
            BorderFactory.createLineBorder(BORDER_COLOR, 1),
            new EmptyBorder(36, 40, 36, 40)
        ));
        card.setMaximumSize(new Dimension(340, 420));

        // ── Title ──
        JLabel heading = new JLabel("Welcome Back");
        heading.setFont(FONT_TITLE);
        heading.setForeground(TEXT_DARK);
        heading.setAlignmentX(Component.LEFT_ALIGNMENT);
        card.add(heading);
        card.add(Box.createVerticalStrut(4));

        JLabel sub = new JLabel("Sign in to your account");
        sub.setFont(FONT_SMALL);
        sub.setForeground(TEXT_MUTED);
        sub.setAlignmentX(Component.LEFT_ALIGNMENT);
        card.add(sub);
        card.add(Box.createVerticalStrut(28));

        // ── Username ──
        card.add(makeLabel("Username"));
        card.add(Box.createVerticalStrut(6));
        usernameField = makeTextField("Enter your username");
        card.add(usernameField);
        card.add(Box.createVerticalStrut(18));

        // ── Password ──
        card.add(makeLabel("Password"));
        card.add(Box.createVerticalStrut(6));
        passwordField = new JPasswordField();
        passwordField.setFont(FONT_INPUT);
        passwordField.setBorder(BorderFactory.createCompoundBorder(
            BorderFactory.createLineBorder(BORDER_COLOR, 1),
            new EmptyBorder(10, 12, 10, 12)));
        passwordField.setMaximumSize(new Dimension(Integer.MAX_VALUE, 42));
        passwordField.setAlignmentX(Component.LEFT_ALIGNMENT);
        card.add(passwordField);
        card.add(Box.createVerticalStrut(26));

        // ── Login Button ──
        loginButton = new RoundedButton("Login", ACCENT_BLUE, WHITE);
        loginButton.setMaximumSize(new Dimension(Integer.MAX_VALUE, 44));
        loginButton.setAlignmentX(Component.LEFT_ALIGNMENT);
        loginButton.addActionListener(e -> performLogin());
        card.add(loginButton);
        card.add(Box.createVerticalStrut(12));

        // ── Exit Button ──
        JButton exitButton = new RoundedButton("Exit", new Color(245, 245, 245), TEXT_DARK);
        exitButton.setMaximumSize(new Dimension(Integer.MAX_VALUE, 44));
        exitButton.setAlignmentX(Component.LEFT_ALIGNMENT);
        exitButton.addActionListener(e -> System.exit(0));
        card.add(exitButton);
        card.add(Box.createVerticalStrut(16));

        // ── Status label (shows errors inline) ──
        statusLabel = new JLabel(" ");
        statusLabel.setFont(FONT_SMALL);
        statusLabel.setForeground(ERROR_RED);
        statusLabel.setAlignmentX(Component.LEFT_ALIGNMENT);
        card.add(statusLabel);

        // Allow Enter key to trigger login
        getRootPane().setDefaultButton(loginButton);
        passwordField.addKeyListener(new KeyAdapter() {
            @Override public void keyPressed(KeyEvent e) {
                if (e.getKeyCode() == KeyEvent.VK_ENTER) performLogin();
            }
        });

        outer.add(card);
        return outer;
    }

    // ─── Login Action ─────────────────────────────────────────────────────────

    private void performLogin() {
        String username = usernameField.getText().trim();
        String password = new String(passwordField.getPassword());

        if (username.isEmpty() || password.isEmpty()) {
            statusLabel.setText("⚠ Username and password are required.");
            return;
        }

        loginButton.setText("Authenticating…");
        loginButton.setEnabled(false);
        statusLabel.setText(" ");

        // Run DB call on a background thread to keep the UI responsive
        SwingWorker<User, Void> worker = new SwingWorker<>() {
            @Override
            protected User doInBackground() throws Exception {
                return employeeDAO.authenticate(username, password);
            }

            @Override
            protected void done() {
                loginButton.setText("Login");
                loginButton.setEnabled(true);
                try {
                    User user = get();
                    openDashboard(user);
                } catch (Exception ex) {
                    Throwable cause = ex.getCause() != null ? ex.getCause() : ex;
                    statusLabel.setText("⚠ " + cause.getMessage());
                }
            }
        };
        worker.execute();
    }

    /** Opens the appropriate dashboard and disposes the Login window. */
    private void openDashboard(User user) {
        dispose();
        if (user.isPrivileged()) {
            SwingUtilities.invokeLater(() -> new AdminDashboard(user).setVisible(true));
        } else {
            try {
                int empId = new EmployeeDAO().getEmpIdByUserId(user.getUserId());
                SwingUtilities.invokeLater(() ->
                    new EmployeeDashboard(user, empId).setVisible(true));
            } catch (SQLException ex) {
                JOptionPane.showMessageDialog(null,
                    "Could not locate employee record: " + ex.getMessage(),
                    "Error", JOptionPane.ERROR_MESSAGE);
                new LoginFrame().setVisible(true);
            }
        }
    }

    // ─── UI Factory Helpers ───────────────────────────────────────────────────

    static JLabel makeLabel(String text) {
        JLabel label = new JLabel(text);
        label.setFont(FONT_LABEL);
        label.setForeground(TEXT_DARK);
        label.setAlignmentX(Component.LEFT_ALIGNMENT);
        return label;
    }

    static JTextField makeTextField(String placeholder) {
        JTextField field = new JTextField() {
            @Override
            protected void paintComponent(Graphics g) {
                super.paintComponent(g);
                if (getText().isEmpty() && !hasFocus()) {
                    g.setColor(TEXT_MUTED);
                    g.setFont(getFont().deriveFont(Font.ITALIC));
                    g.drawString(placeholder, 12, getHeight() / 2 + 5);
                }
            }
        };
        field.setFont(FONT_INPUT);
        field.setBorder(BorderFactory.createCompoundBorder(
            BorderFactory.createLineBorder(BORDER_COLOR, 1),
            new EmptyBorder(10, 12, 10, 12)));
        field.setMaximumSize(new Dimension(Integer.MAX_VALUE, 42));
        field.setAlignmentX(Component.LEFT_ALIGNMENT);
        return field;
    }

    // ─── Custom Rounded Button ────────────────────────────────────────────────

    /**
     * RoundedButton — a JButton subclass with rounded corners and hover effects.
     * Demonstrates custom painting and inner classes in Swing.
     */
    static class RoundedButton extends JButton {
        private final Color normalBg;
        private final Color hoverBg;
        private final Color fg;

        RoundedButton(String text, Color bg, Color fg) {
            super(text);
            this.normalBg = bg;
            this.hoverBg  = bg.darker();
            this.fg       = fg;
            setFont(FONT_BUTTON);
            setForeground(fg);
            setBackground(bg);
            setFocusPainted(false);
            setBorderPainted(false);
            setContentAreaFilled(false);
            setCursor(Cursor.getPredefinedCursor(Cursor.HAND_CURSOR));

            addMouseListener(new MouseAdapter() {
                @Override public void mouseEntered(MouseEvent e) {
                    setBackground(hoverBg); repaint();
                }
                @Override public void mouseExited(MouseEvent e) {
                    setBackground(normalBg); repaint();
                }
            });
        }

        @Override
        protected void paintComponent(Graphics g) {
            Graphics2D g2 = (Graphics2D) g.create();
            g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING,
                                RenderingHints.VALUE_ANTIALIAS_ON);
            g2.setColor(getBackground());
            g2.fillRoundRect(0, 0, getWidth(), getHeight(), 10, 10);
            g2.dispose();
            super.paintComponent(g);
        }
    }
}
