-- MediCore Hospital: schema (DDL). SQLite dialect, portable to MySQL/PostgreSQL with minor type changes.
PRAGMA foreign_keys = ON;

CREATE TABLE departments (
    dept_id    INTEGER PRIMARY KEY,
    dept_name  TEXT NOT NULL UNIQUE,
    floor_no   INTEGER NOT NULL CHECK (floor_no BETWEEN 0 AND 12)
);

CREATE TABLE doctors (
    doctor_id     INTEGER PRIMARY KEY,
    full_name     TEXT NOT NULL,
    dept_id       INTEGER NOT NULL REFERENCES departments(dept_id),
    consult_fee   REAL NOT NULL CHECK (consult_fee > 0),
    shift_start   TEXT NOT NULL DEFAULT '09:00',
    shift_end     TEXT NOT NULL DEFAULT '17:00',
    CHECK (shift_start < shift_end)
);

CREATE TABLE patients (
    patient_id  INTEGER PRIMARY KEY,
    full_name   TEXT NOT NULL,
    dob         TEXT NOT NULL CHECK (dob >= '1900-01-01' AND dob GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
    gender      TEXT NOT NULL CHECK (gender IN ('M','F','O')),
    phone       TEXT NOT NULL UNIQUE CHECK (length(phone) = 10),
    city        TEXT NOT NULL
);

CREATE TABLE diagnoses (
    diag_id     INTEGER PRIMARY KEY,
    icd_code    TEXT NOT NULL UNIQUE,
    description TEXT NOT NULL,
    dept_id     INTEGER NOT NULL REFERENCES departments(dept_id)
);

CREATE TABLE appointments (
    appt_id       INTEGER PRIMARY KEY,
    patient_id    INTEGER NOT NULL REFERENCES patients(patient_id),
    doctor_id     INTEGER NOT NULL REFERENCES doctors(doctor_id),
    appt_date     TEXT NOT NULL,
    slot_time     TEXT NOT NULL,
    status        TEXT NOT NULL DEFAULT 'Booked'
                  CHECK (status IN ('Booked','Completed','Cancelled','No-Show')),
    wait_minutes  INTEGER CHECK (wait_minutes IS NULL OR wait_minutes >= 0),
    diag_id       INTEGER REFERENCES diagnoses(diag_id),
    -- valid slot: 30-minute grid between 09:00 and 16:30
    CHECK (slot_time BETWEEN '09:00' AND '16:30' AND substr(slot_time,4,2) IN ('00','30')),
    -- wait time and diagnosis only exist for completed visits
    CHECK ((status = 'Completed') OR (wait_minutes IS NULL AND diag_id IS NULL))
);
CREATE INDEX idx_appt_date   ON appointments(appt_date, slot_time);
CREATE INDEX idx_appt_doctor ON appointments(doctor_id, appt_date);
CREATE INDEX idx_appt_patient ON appointments(patient_id);

CREATE TABLE prescriptions (
    presc_id   INTEGER PRIMARY KEY,
    appt_id    INTEGER NOT NULL REFERENCES appointments(appt_id) ON DELETE CASCADE,
    medicine   TEXT NOT NULL,
    dosage     TEXT NOT NULL,
    days       INTEGER NOT NULL CHECK (days > 0)
);

CREATE TABLE bills (
    bill_id      INTEGER PRIMARY KEY,
    appt_id      INTEGER NOT NULL UNIQUE REFERENCES appointments(appt_id),
    amount       REAL NOT NULL CHECK (amount >= 0),
    paid_amount  REAL NOT NULL DEFAULT 0 CHECK (paid_amount >= 0),
    pay_status   TEXT NOT NULL CHECK (pay_status IN ('Paid','Partial','Pending')),
    bill_date    TEXT NOT NULL,
    CHECK (paid_amount <= amount)
);

-- ---------- Triggers: block double booking ----------
-- A doctor cannot hold two live appointments in one slot, and a patient cannot be in two places at once.
CREATE TRIGGER trg_no_double_booking_ins
BEFORE INSERT ON appointments
WHEN NEW.status <> 'Cancelled'
BEGIN
    SELECT RAISE(ABORT, 'Double booking: doctor already has an appointment in this slot')
    WHERE EXISTS (SELECT 1 FROM appointments
                  WHERE doctor_id = NEW.doctor_id AND appt_date = NEW.appt_date
                    AND slot_time = NEW.slot_time AND status <> 'Cancelled');
    SELECT RAISE(ABORT, 'Double booking: patient already has an appointment in this slot')
    WHERE EXISTS (SELECT 1 FROM appointments
                  WHERE patient_id = NEW.patient_id AND appt_date = NEW.appt_date
                    AND slot_time = NEW.slot_time AND status <> 'Cancelled');
END;

CREATE TRIGGER trg_no_double_booking_upd
BEFORE UPDATE OF doctor_id, appt_date, slot_time, status ON appointments
WHEN NEW.status <> 'Cancelled'
BEGIN
    SELECT RAISE(ABORT, 'Double booking: doctor already has an appointment in this slot')
    WHERE EXISTS (SELECT 1 FROM appointments
                  WHERE appt_id <> NEW.appt_id AND doctor_id = NEW.doctor_id
                    AND appt_date = NEW.appt_date AND slot_time = NEW.slot_time
                    AND status <> 'Cancelled');
END;
