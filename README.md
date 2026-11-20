# MediCore Hospital – Patient and Appointment Analytics

Relational core (appointments, billing) in SQL; unstructured lab reports and clinical notes in MongoDB.

| File | Purpose |
|---|---|
| `01_schema.sql` | DDL: tables, constraints, indexes, double-booking triggers |
| `02_dml.sql` | Book, reschedule, cancel, complete + bill |
| `03_analytics.sql` | Peak hours, utilisation, no-show, diagnoses, revenue, nested queries |
| `build_db.py` | Creates `medicore.db` and loads 7,600+ synthetic appointments (seeded, reproducible) |
| `analysis.py` | Python DB-API: runs DML demo, reports, charts (`chart_*.png`) |
| `mongo_medicore.js` | MongoDB documents, CRUD, indexes, aggregations (`mongosh medicore mongo_medicore.js`) |

Run: `python3 build_db.py && python3 analysis.py`

## 1. Schema design and normalisation

**Entities and keys**

- `departments(dept_id PK, dept_name, floor_no)`
- `doctors(doctor_id PK, full_name, dept_id FK, consult_fee, shift_start, shift_end)`
- `patients(patient_id PK, full_name, dob, gender, phone, city)`
- `diagnoses(diag_id PK, icd_code, description, dept_id FK)`
- `appointments(appt_id PK, patient_id FK, doctor_id FK, appt_date, slot_time, status, wait_minutes, diag_id FK)`
- `prescriptions(presc_id PK, appt_id FK, medicine, dosage, days)`
- `bills(bill_id PK, appt_id FK UNIQUE, amount, paid_amount, pay_status, bill_date)`

**Functional dependencies**

- dept_id → dept_name, floor_no; dept_name → dept_id
- doctor_id → full_name, dept_id, consult_fee, shift_start, shift_end
- patient_id → full_name, dob, gender, city; phone → patient_id
- icd_code → diag_id, description, dept_id
- appt_id → patient_id, doctor_id, appt_date, slot_time, status, wait_minutes, diag_id
- (doctor_id, appt_date, slot_time) → appt_id for live appointments (a candidate key enforced by the trigger, because cancelled rows may repeat it)
- appt_id → bill_id; bill_id → amount, paid_amount, pay_status, bill_date

**Normalisation walk-through.** Start from one wide sheet: `(appt_id, appt_date, slot, patient_name, patient_phone, patient_city, doctor_name, dept_name, dept_floor, consult_fee, diagnosis, medicines, bill_amount)`.

- **1NF:** `medicines` is multi-valued, so it moves to `prescriptions`, one row per medicine.
- **2NF:** if prescriptions were keyed on (appt_id, medicine), attributes depending only on appt_id would be partial dependencies. Patient, doctor and date attributes depend only on `appt_id`, so they sit in `appointments`, not in prescriptions.
- **3NF:** transitive dependencies are removed.
  - appt_id → doctor_id → dept_id → dept_name, floor_no, so `departments` and `doctors` are separate tables.
  - appt_id → patient_id → patient_name, city, so `patients` is separate.
  - icd_code → description is held once in `diagnoses`.
- **BCNF:** every determinant above is a candidate key of its table (`phone` and `icd_code` are declared UNIQUE), so all tables are in BCNF.
- **Deliberate trade-off:** `bills.amount` could be derived from consult_fee plus services. It is stored because fees change over time and a bill must stay historically correct.

## 2. Constraints that protect data quality

- **Valid slots:** a CHECK keeps slots on the 30-minute grid between 09:00 and 16:30.
- **Valid amounts:** `amount >= 0`, `paid_amount <= amount`, `consult_fee > 0`.
- **Status integrity:** `wait_minutes` and `diag_id` exist only on `Completed` visits.
- **Contact data:** gender and phone-length CHECKs, and a UNIQUE phone number.
- **Double booking:** `trg_no_double_booking_ins` and `_upd` raise an error when a doctor or patient already has a live appointment in the slot. Cancelling frees the slot.
- **Tested in `analysis.py`:** a second booking in the same doctor slot is rejected, a patient clash is rejected, and an off-grid slot such as 10:15 is rejected.

## 3. Findings from the sample data (seeded 3-month, synthetic)

- **Peak hours:** 11:00 (1,306 appointments) and 10:00 (1,224) are busiest, with a smaller afternoon peak at 15:00. 13:00 is the quietest hour (471). Staff the morning clinics heavily and use the lunch lull for procedures.
- **No-shows:** Orthopaedics is highest at 15.3% and ENT lowest at 11.3%. Mondays (17.2%) and Fridays (16.5%) run about 7 points above mid-week (~10%). Reminders and overbooking rules should target those days. Patients 215 and 149 each have 7 no-shows and are candidates for a deposit or a confirmation call.
- **Doctor utilisation:** the General Medicine doctor is at 56.8% and the lowest-loaded doctors are in the high 30s. Moving walk-in or follow-up demand to under-used doctors would balance the load.
- **Waiting time:** the average rises across the quarter (see `chart_waiting_time_trend.png`). Eight doctors exceed the hospital average, and waits grow later in the day.
- **Revenue:** Cardiology bills the most (₹11.96 lakh) and collection is about 70% across all departments, so unpaid bills are a bigger lever than slot filling.
- **Top diagnoses:** Fever, Vaginitis, Angina, Hypertension and Atrial fibrillation lead.

## 4. MongoDB model

**Lab reports** have a variable number of tests, and some include imaging. Modelling each test as a row would need a join and many NULLs. Here a report is one document with an embedded `tests[]` array, and `imaging` appears only where it exists. Reports and notes reference the SQL `patient_id` and `appt_id`. Full CRUD is in `mongo_medicore.js`.

Indexes:

- `{patient_id, report_date:-1}`: a patient's history, newest first
- `{dept, report_date}`: supports the department/month aggregation
- `{tests.name, tests.flag}`: multikey index for abnormal-result searches
- a text index on notes for free-text search

Aggregations: test results by department and month with the abnormal percentage, monthly averages per test (HbA1c, LDL, Hemoglobin) for trends, and `$lookup` joining notes to reports.

## 5. SQL vs MongoDB

| | SQL (relational) | MongoDB (document) |
|---|---|---|
| Best for | Appointments, billing, anything needing joins and strict rules | Lab reports, clinical notes, with varying structure |
| Integrity | FK, CHECK, triggers prevent bad data | Schema is flexible, so validation lives in the app or `$jsonSchema` |
| Reads | Patient history needs several joins | One document per report, so a single indexed read |
| Aggregation | Powerful JOIN + GROUP BY across entities | `$unwind` then `$group` suits nested arrays, but cross-collection joins (`$lookup`) are weaker |
| Change | `ALTER TABLE` migration for each new test type | New fields can be added immediately |
| Transactions | Strong, multi-table | Supported but not its sweet spot |

**Conclusion:** use a polyglot design. SQL is the system of record for scheduling and money, where double booking and invalid amounts must be impossible. MongoDB stores the clinical documents, linked by `patient_id` and `appt_id`.
