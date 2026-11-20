-- name: load_by_dept_hour
-- Appointments per department and hour (peak-hour view)
SELECT dp.dept_name,
       CAST(substr(a.slot_time,1,2) AS INTEGER) AS hour,
       COUNT(*) AS appointments
FROM appointments a
JOIN doctors d      ON d.doctor_id = a.doctor_id
JOIN departments dp ON dp.dept_id  = d.dept_id
WHERE a.status <> 'Cancelled'
GROUP BY dp.dept_name, hour
ORDER BY dp.dept_name, hour;

-- name: peak_hours
SELECT CAST(substr(slot_time,1,2) AS INTEGER) AS hour, COUNT(*) AS appointments
FROM appointments WHERE status <> 'Cancelled'
GROUP BY hour ORDER BY appointments DESC;

-- name: doctor_utilisation
-- Utilisation = booked slots / available slots (16 half-hour slots per working day).
-- Nested SELECT supplies the number of clinic days in the data.
SELECT d.full_name, dp.dept_name,
       COUNT(a.appt_id) AS slots_used,
       (SELECT COUNT(DISTINCT appt_date) FROM appointments) * 16 AS slots_available,
       ROUND(100.0 * COUNT(a.appt_id) /
             ((SELECT COUNT(DISTINCT appt_date) FROM appointments) * 16), 1) AS utilisation_pct
FROM doctors d
JOIN departments dp ON dp.dept_id = d.dept_id
LEFT JOIN appointments a ON a.doctor_id = d.doctor_id AND a.status <> 'Cancelled'
GROUP BY d.doctor_id
ORDER BY utilisation_pct DESC;

-- name: no_show_rate
-- No-show rate = no-shows / appointments that were meant to happen (cancellations excluded).
SELECT dp.dept_name,
       COUNT(*) AS attended_or_missed,
       SUM(a.status = 'No-Show') AS no_shows,
       ROUND(100.0 * SUM(a.status = 'No-Show') / COUNT(*), 1) AS no_show_pct
FROM appointments a
JOIN doctors d      ON d.doctor_id = a.doctor_id
JOIN departments dp ON dp.dept_id  = d.dept_id
WHERE a.status IN ('Completed','No-Show')
GROUP BY dp.dept_name
ORDER BY no_show_pct DESC;

-- name: top_diagnoses
SELECT g.icd_code, g.description, dp.dept_name, COUNT(*) AS cases
FROM appointments a
JOIN diagnoses g    ON g.diag_id  = a.diag_id
JOIN departments dp ON dp.dept_id = g.dept_id
GROUP BY g.diag_id
ORDER BY cases DESC
LIMIT 10;

-- name: revenue_by_dept
SELECT dp.dept_name,
       COUNT(b.bill_id)        AS bills,
       ROUND(SUM(b.amount),0)  AS billed,
       ROUND(SUM(b.paid_amount),0) AS collected,
       ROUND(100.0 * SUM(b.paid_amount) / SUM(b.amount), 1) AS collection_pct
FROM bills b
JOIN appointments a ON a.appt_id = b.appt_id
JOIN doctors d      ON d.doctor_id = a.doctor_id
JOIN departments dp ON dp.dept_id = d.dept_id
GROUP BY dp.dept_name
ORDER BY billed DESC;

-- name: slow_doctors
-- Nested SELECT: doctors whose average wait is above the hospital-wide average.
SELECT d.full_name, ROUND(AVG(a.wait_minutes),1) AS avg_wait
FROM appointments a JOIN doctors d ON d.doctor_id = a.doctor_id
WHERE a.status = 'Completed'
GROUP BY d.doctor_id
HAVING AVG(a.wait_minutes) > (SELECT AVG(wait_minutes) FROM appointments WHERE status='Completed')
ORDER BY avg_wait DESC;

-- name: repeat_no_show_patients
-- Nested SELECT: patients with more no-shows than the average no-show count per patient.
SELECT p.patient_id, p.full_name, COUNT(*) AS no_shows
FROM appointments a JOIN patients p ON p.patient_id = a.patient_id
WHERE a.status = 'No-Show'
GROUP BY p.patient_id
HAVING COUNT(*) > (SELECT AVG(c) FROM (SELECT COUNT(*) AS c FROM appointments
                                       WHERE status='No-Show' GROUP BY patient_id))
ORDER BY no_shows DESC
LIMIT 10;

-- name: weekly_wait
SELECT date(a.appt_date, 'weekday 0', '-6 days') AS week_start,
       dp.dept_name, ROUND(AVG(a.wait_minutes),1) AS avg_wait
FROM appointments a
JOIN doctors d      ON d.doctor_id = a.doctor_id
JOIN departments dp ON dp.dept_id  = d.dept_id
WHERE a.status = 'Completed'
GROUP BY week_start, dp.dept_name
ORDER BY week_start;

-- name: no_show_by_weekday
SELECT strftime('%w', appt_date) AS dow,
       ROUND(100.0 * SUM(status='No-Show') / COUNT(*), 1) AS no_show_pct
FROM appointments WHERE status IN ('Completed','No-Show')
GROUP BY dow ORDER BY dow;
