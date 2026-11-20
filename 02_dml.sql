-- DML: appointment lifecycle. ? placeholders are bound by the caller (see analysis.py).

-- Book
INSERT INTO appointments (patient_id, doctor_id, appt_date, slot_time, status)
VALUES (:patient_id, :doctor_id, :appt_date, :slot_time, 'Booked');

-- Reschedule (only a Booked appointment can move; trigger re-checks the new slot)
UPDATE appointments
SET appt_date = :new_date, slot_time = :new_slot
WHERE appt_id = :appt_id AND status = 'Booked';

-- Cancel (soft delete: keeps history for no-show / cancellation analytics, frees the slot)
UPDATE appointments SET status = 'Cancelled'
WHERE appt_id = :appt_id AND status = 'Booked';

-- Complete a visit and bill it
UPDATE appointments SET status='Completed', wait_minutes=:wait, diag_id=:diag_id
WHERE appt_id = :appt_id AND status = 'Booked';

INSERT INTO bills (appt_id, amount, paid_amount, pay_status, bill_date)
SELECT a.appt_id, d.consult_fee + :extras, 0, 'Pending', a.appt_date
FROM appointments a JOIN doctors d ON d.doctor_id = a.doctor_id
WHERE a.appt_id = :appt_id;

-- Mark no-shows for yesterday's unattended bookings
UPDATE appointments SET status = 'No-Show'
WHERE status = 'Booked' AND appt_date < date('now');
