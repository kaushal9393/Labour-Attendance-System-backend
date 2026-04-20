from pydantic import BaseModel, EmailStr, field_validator
from typing import Optional, List
from datetime import date, datetime, time
from decimal import Decimal


# ─────────────────────────────────────────
# AUTH
# ─────────────────────────────────────────
class LoginRequest(BaseModel):
    company_code: str
    email: EmailStr
    password: str

class LoginResponse(BaseModel):
    token: str
    admin_name: str
    company_name: str
    company_id: int


# ─────────────────────────────────────────
# EMPLOYEE
# ─────────────────────────────────────────
class EmployeeCreate(BaseModel):
    name: str
    phone: Optional[str] = None
    monthly_salary: Decimal
    joining_date: date
    photos: List[str]  # 25 base64 images

    @field_validator('photos')
    @classmethod
    def must_have_25_photos(cls, v):
        if len(v) != 25:
            raise ValueError('Exactly 25 photos required for face registration')
        return v

class EmployeeUpdate(BaseModel):
    name: Optional[str] = None
    phone: Optional[str] = None
    monthly_salary: Optional[Decimal] = None
    joining_date: Optional[date] = None
    status: Optional[str] = None

class EmployeeResponse(BaseModel):
    id: int
    company_id: int
    name: str
    phone: Optional[str]
    monthly_salary: Decimal
    joining_date: date
    profile_photo_url: Optional[str]
    status: str
    created_at: datetime

    class Config:
        from_attributes = True


# ─────────────────────────────────────────
# ATTENDANCE
# ─────────────────────────────────────────
class ScanRequest(BaseModel):
    image: str         # base64 encoded image
    company_code: str  # sent by kiosk (no JWT in kiosk mode)

class ScanResponse(BaseModel):
    success: bool
    employee_name: Optional[str] = None
    time: Optional[str] = None
    action: Optional[str] = None       # "check_in" | "check_out"
    match_score: Optional[float] = None
    reason: Optional[str] = None       # error reason if success=False

class AttendanceRecord(BaseModel):
    id: int
    employee_id: int
    employee_name: str
    profile_photo_url: Optional[str]
    attendance_date: date
    check_in: Optional[datetime]
    check_out: Optional[datetime]
    status: str
    match_score: Optional[Decimal]

    class Config:
        from_attributes = True

class TodayAttendanceResponse(BaseModel):
    date: date
    total_present: int
    total_absent: int
    total_late: int
    records: List[AttendanceRecord]

class MonthlyAttendanceRecord(BaseModel):
    attendance_date: date
    check_in: Optional[datetime]
    check_out: Optional[datetime]
    status: str
    match_score: Optional[Decimal]


# ─────────────────────────────────────────
# SALARY
# ─────────────────────────────────────────
class SalaryResponse(BaseModel):
    employee_id: int
    employee_name: str
    month: int
    year: int
    monthly_salary: Decimal
    working_days: int
    present_days: int
    late_days: int
    absent_days: int
    per_day_salary: Decimal
    deduction_amount: Decimal
    net_pay: Decimal

class MonthlySummaryEmployee(BaseModel):
    employee_id: int
    employee_name: str
    present_days: int
    absent_days: int
    late_days: int
    net_pay: Decimal

class MonthlySummaryResponse(BaseModel):
    month: int
    year: int
    employees: List[MonthlySummaryEmployee]


# ─────────────────────────────────────────
# SETTINGS
# ─────────────────────────────────────────
class SettingsResponse(BaseModel):
    id: int
    company_id: int
    work_start_time: time
    work_end_time: time
    late_threshold_minutes: int
    working_days_per_week: int

    class Config:
        from_attributes = True

class SettingsUpdate(BaseModel):
    work_start_time: Optional[time] = None
    work_end_time: Optional[time] = None
    late_threshold_minutes: Optional[int] = None
    working_days_per_week: Optional[int] = None


# ─────────────────────────────────────────
# GENERIC
# ─────────────────────────────────────────
class MessageResponse(BaseModel):
    message: str

class ErrorResponse(BaseModel):
    detail: str
