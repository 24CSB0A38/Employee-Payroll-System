package models;

/**
 * Payslip.java — Model class representing one row from Monthly_Payroll_View.
 *
 * Interview talking points:
 *  - Maps exactly to the columns returned by the Payslip / Monthly_Payroll_View.
 *  - Kept flat (no nested objects) for easy JTable rendering.
 */
public class Payslip {

    private int    payslipId;
    private int    empId;
    private String employeeName;
    private String department;
    private String payrollPeriod;   // e.g. "2025-04"
    private double basicPay;
    private double hra;
    private double da;
    private double bonus;
    private double overtimePay;
    private double grossSalary;
    private double pfDeduction;
    private double professionalTax;
    private double incomeTax;
    private double lossOfPay;
    private double totalDeductions;
    private double netSalary;
    private int    daysPresent;
    private int    daysAbsent;
    private String payrollStatus;   // Pending | Processed | Approved | Rejected
    private String generatedBy;
    private String approvedBy;

    /** Full constructor used when mapping a ResultSet row. */
    public Payslip(int payslipId, int empId, String employeeName, String department,
                   String payrollPeriod, double basicPay, double hra, double da,
                   double bonus, double overtimePay, double grossSalary,
                   double pfDeduction, double professionalTax, double incomeTax,
                   double lossOfPay, double totalDeductions, double netSalary,
                   int daysPresent, int daysAbsent,
                   String payrollStatus, String generatedBy, String approvedBy) {
        this.payslipId       = payslipId;
        this.empId           = empId;
        this.employeeName    = employeeName;
        this.department      = department;
        this.payrollPeriod   = payrollPeriod;
        this.basicPay        = basicPay;
        this.hra             = hra;
        this.da              = da;
        this.bonus           = bonus;
        this.overtimePay     = overtimePay;
        this.grossSalary     = grossSalary;
        this.pfDeduction     = pfDeduction;
        this.professionalTax = professionalTax;
        this.incomeTax       = incomeTax;
        this.lossOfPay       = lossOfPay;
        this.totalDeductions = totalDeductions;
        this.netSalary       = netSalary;
        this.daysPresent     = daysPresent;
        this.daysAbsent      = daysAbsent;
        this.payrollStatus   = payrollStatus;
        this.generatedBy     = generatedBy;
        this.approvedBy      = approvedBy;
    }

    // ─── Getters ──────────────────────────────────────────────────────────────

    public int    getPayslipId()       { return payslipId;       }
    public int    getEmpId()           { return empId;           }
    public String getEmployeeName()    { return employeeName;    }
    public String getDepartment()      { return department;      }
    public String getPayrollPeriod()   { return payrollPeriod;   }
    public double getBasicPay()        { return basicPay;        }
    public double getHra()             { return hra;             }
    public double getDa()              { return da;              }
    public double getBonus()           { return bonus;           }
    public double getOvertimePay()     { return overtimePay;     }
    public double getGrossSalary()     { return grossSalary;     }
    public double getPfDeduction()     { return pfDeduction;     }
    public double getProfessionalTax() { return professionalTax; }
    public double getIncomeTax()       { return incomeTax;       }
    public double getLossOfPay()       { return lossOfPay;       }
    public double getTotalDeductions() { return totalDeductions; }
    public double getNetSalary()       { return netSalary;       }
    public int    getDaysPresent()     { return daysPresent;     }
    public int    getDaysAbsent()      { return daysAbsent;      }
    public String getPayrollStatus()   { return payrollStatus;   }
    public String getGeneratedBy()     { return generatedBy;     }
    public String getApprovedBy()      { return approvedBy;      }
}
