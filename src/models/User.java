package models;

/**
 * User.java — Model class representing a row in the Users table.
 *
 * Interview talking points:
 *  - Encapsulation: all fields are private; exposed via getters.
 *  - Constructor sets all fields at creation time (immutable-friendly).
 *  - password is never stored in plain-text here; only used transiently.
 */
public class User {

    private int    userId;
    private String username;
    private String role;     // Admin | HR | Manager | Employee
    private int    isActive;

    /** Full constructor used when reading a row from the database. */
    public User(int userId, String username, String role, int isActive) {
        this.userId   = userId;
        this.username = username;
        this.role     = role;
        this.isActive = isActive;
    }

    // ─── Getters ─────────────────────────────────────────────────────────────

    public int    getUserId()   { return userId;   }
    public String getUsername() { return username; }
    public String getRole()     { return role;     }
    public int    getIsActive() { return isActive; }

    /**
     * Convenience: returns true when the user holds a privileged role
     * (Admin, HR, or Manager) that grants access to the Admin Dashboard.
     */
    public boolean isPrivileged() {
        return "Admin".equalsIgnoreCase(role)
            || "HR".equalsIgnoreCase(role)
            || "Manager".equalsIgnoreCase(role);
    }

    @Override
    public String toString() {
        return "User{userId=" + userId + ", username='" + username + "', role='" + role + "'}";
    }
}
