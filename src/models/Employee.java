package models;

/**
 * Employee.java — Model class for data returned from Employee_Profile_View.
 *
 * Interview talking points:
 *  - Separation of concerns: this class only carries data; business logic
 *    lives in EmployeeDAO, not here.
 *  - Matches columns from the Employee_Profile_View database view so that
 *    the DAO maps ResultSet columns directly to this object.
 */
public class Employee {

    private int    empId;
    private String name;
    private String department;
    private String designation;
    private String empType;
    private String status;
    private String fname;
    private String lname;
    private String gender;
    private String email;
    private String phone;
    private double basicPay;
    private double hra;
    private double da;
    private double medicalAllowance;
    private double specialAllowance;
    private double ctcMonthly;
    private String username;
    private String systemRole;

    /** Full-field constructor for mapping from Employee_Profile_View. */
    public Employee(int empId, String name, String department, String designation,
                    String empType, String status, String fname, String lname,
                    String gender, String email, String phone,
                    double basicPay, double hra, double da,
                    double medicalAllowance, double specialAllowance,
                    double ctcMonthly, String username, String systemRole) {
        this.empId             = empId;
        this.name              = name;
        this.department        = department;
        this.designation       = designation;
        this.empType           = empType;
        this.status            = status;
        this.fname             = fname;
        this.lname             = lname;
        this.gender            = gender;
        this.email             = email;
        this.phone             = phone;
        this.basicPay          = basicPay;
        this.hra               = hra;
        this.da                = da;
        this.medicalAllowance  = medicalAllowance;
        this.specialAllowance  = specialAllowance;
        this.ctcMonthly        = ctcMonthly;
        this.username          = username;
        this.systemRole        = systemRole;
    }

    // ─── Getters ──────────────────────────────────────────────────────────────

    public int    getEmpId()            { return empId;            }
    public String getName()             { return name;             }
    public String getDepartment()       { return department;       }
    public String getDesignation()      { return designation;      }
    public String getEmpType()          { return empType;          }
    public String getStatus()           { return status;           }
    public String getFname()            { return fname;            }
    public String getLname()            { return lname;            }
    public String getGender()           { return gender;           }
    public String getEmail()            { return email;            }
    public String getPhone()            { return phone;            }
    public double getBasicPay()         { return basicPay;         }
    public double getHra()              { return hra;              }
    public double getDa()               { return da;               }
    public double getMedicalAllowance() { return medicalAllowance; }
    public double getSpecialAllowance() { return specialAllowance; }
    public double getCtcMonthly()       { return ctcMonthly;       }
    public String getUsername()         { return username;         }
    public String getSystemRole()       { return systemRole;       }

    @Override
    public String toString() {
        return "Employee{empId=" + empId + ", name='" + name + "', dept='" + department + "'}";
    }
}
