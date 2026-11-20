// MediCore: MongoDB model, CRUD, indexes and aggregations. Run with:  mongosh medicore mongo_medicore.js
// patient_id / appt_id / dept values are the same keys as the SQL database, so the two stores can be joined in the app layer.
db = db.getSiblingDB("medicore");
db.lab_reports.drop(); db.clinical_notes.drop();

// ---------- CREATE ----------
db.lab_reports.insertMany([
  { patient_id: 12, appt_id: 3001, dept: "Cardiology", report_date: ISODate("2026-08-12"), lab: "CoreLab",
    tests: [ { name: "Total Cholesterol", value: 242, unit: "mg/dL", ref: [0, 200], flag: "HIGH" },
             { name: "LDL", value: 160, unit: "mg/dL", ref: [0, 130], flag: "HIGH" },
             { name: "Troponin I", value: 0.01, unit: "ng/mL", ref: [0, 0.04], flag: "NORMAL" } ] },
  { patient_id: 12, appt_id: 3188, dept: "Cardiology", report_date: ISODate("2026-09-20"), lab: "CoreLab",
    tests: [ { name: "Total Cholesterol", value: 205, unit: "mg/dL", ref: [0, 200], flag: "HIGH" },
             { name: "LDL", value: 128, unit: "mg/dL", ref: [0, 130], flag: "NORMAL" } ] },
  { patient_id: 77, appt_id: 3050, dept: "General Medicine", report_date: ISODate("2026-08-30"), lab: "CoreLab",
    tests: [ { name: "HbA1c", value: 8.1, unit: "%", ref: [4, 5.6], flag: "HIGH" },
             { name: "Fasting Glucose", value: 156, unit: "mg/dL", ref: [70, 100], flag: "HIGH" } ],
    imaging: { type: "Chest X-ray", finding: "Clear lung fields" } },          // field only some reports have
  { patient_id: 77, appt_id: 3400, dept: "General Medicine", report_date: ISODate("2026-10-05"), lab: "CoreLab",
    tests: [ { name: "HbA1c", value: 7.2, unit: "%", ref: [4, 5.6], flag: "HIGH" } ] },
  { patient_id: 140, appt_id: 3120, dept: "Paediatrics", report_date: ISODate("2026-09-02"), lab: "CoreLab",
    tests: [ { name: "Hemoglobin", value: 10.4, unit: "g/dL", ref: [11, 14], flag: "LOW" },
             { name: "WBC", value: 9.1, unit: "x10^3/uL", ref: [5, 15], flag: "NORMAL" } ] },
  { patient_id: 140, appt_id: 3333, dept: "Paediatrics", report_date: ISODate("2026-10-14"), lab: "CoreLab",
    tests: [ { name: "Hemoglobin", value: 11.6, unit: "g/dL", ref: [11, 14], flag: "NORMAL" } ] },
  { patient_id: 205, appt_id: 3210, dept: "Neurology", report_date: ISODate("2026-10-22"), lab: "NeuroDiag",
    tests: [ { name: "EEG", value: null, unit: null, ref: null, flag: "ABNORMAL", remarks: "Spike-wave activity" } ] }
]);

db.clinical_notes.insertMany([
  { patient_id: 12, appt_id: 3001, doctor_id: 1, dept: "Cardiology", date: ISODate("2026-08-12"),
    note: "Chest tightness on exertion for 2 weeks. BP 150/95. Advised lipid profile, start amlodipine.",
    tags: ["hypertension", "lipids"], vitals: { bp: "150/95", pulse: 82, weight_kg: 78 } },
  { patient_id: 77, appt_id: 3050, doctor_id: 7, dept: "General Medicine", date: ISODate("2026-08-30"),
    note: "Increased thirst, fatigue. Poor glycaemic control. Metformin dose increased; diet counselling.",
    tags: ["diabetes"], vitals: { bp: "130/84", pulse: 76 }, follow_up: ISODate("2026-10-05") },
  { patient_id: 140, appt_id: 3120, doctor_id: 5, dept: "Paediatrics", date: ISODate("2026-09-02"),
    note: "Pallor, easy fatigue. Iron supplements prescribed.", tags: ["anaemia"] }
]);

// ---------- INDEXES ----------
db.lab_reports.createIndex({ patient_id: 1, report_date: -1 });           // patient history, newest first
db.lab_reports.createIndex({ dept: 1, report_date: 1 });                  // dept/month aggregation
db.lab_reports.createIndex({ "tests.name": 1, "tests.flag": 1 });         // multikey: find abnormal tests
db.clinical_notes.createIndex({ patient_id: 1, date: -1 });
db.clinical_notes.createIndex({ note: "text", tags: "text" });            // free-text search

// ---------- READ ----------
printjson(db.lab_reports.find({ patient_id: 12 }).sort({ report_date: -1 }).toArray());
printjson(db.lab_reports.find({ tests: { $elemMatch: { name: "HbA1c", value: { $gt: 7 } } } }, { patient_id: 1, report_date: 1 }).toArray());
printjson(db.clinical_notes.find({ $text: { $search: "diabetes glycaemic" } }).toArray());
printjson(db.lab_reports.find({ patient_id: 12 }).explain("executionStats").executionStats.totalDocsExamined); // uses the patient_id index

// ---------- UPDATE ----------
db.lab_reports.updateOne({ appt_id: 3400 }, { $push: { tests: { name: "Fasting Glucose", value: 132, unit: "mg/dL", ref: [70, 100], flag: "HIGH" } } });
db.clinical_notes.updateOne({ appt_id: 3120 }, { $set: { follow_up: ISODate("2026-10-14") }, $addToSet: { tags: "iron-therapy" } });
db.lab_reports.updateMany({ lab: "CoreLab" }, { $set: { verified: true } });

// ---------- DELETE ----------
db.clinical_notes.deleteOne({ appt_id: 3120, tags: "anaemia" });
db.lab_reports.deleteMany({ patient_id: 205 });

// ---------- AGGREGATION 1: test results by department and month ----------
printjson(db.lab_reports.aggregate([
  { $unwind: "$tests" },
  { $match: { "tests.value": { $ne: null } } },
  { $group: { _id: { dept: "$dept", month: { $dateToString: { format: "%Y-%m", date: "$report_date" } } },
              tests_done: { $sum: 1 },
              abnormal: { $sum: { $cond: [{ $ne: ["$tests.flag", "NORMAL"] }, 1, 0] } } } },
  { $addFields: { abnormal_pct: { $round: [{ $multiply: [{ $divide: ["$abnormal", "$tests_done"] }, 100] }, 1] } } },
  { $sort: { "_id.dept": 1, "_id.month": 1 } }
]).toArray());

// ---------- AGGREGATION 2: average value per test per month (trend) ----------
printjson(db.lab_reports.aggregate([
  { $unwind: "$tests" },
  { $match: { "tests.name": { $in: ["HbA1c", "LDL", "Hemoglobin"] } } },
  { $group: { _id: { test: "$tests.name", month: { $dateToString: { format: "%Y-%m", date: "$report_date" } } },
              avg_value: { $avg: "$tests.value" }, patients: { $addToSet: "$patient_id" } } },
  { $project: { avg_value: { $round: ["$avg_value", 2] }, patient_count: { $size: "$patients" } } },
  { $sort: { "_id.test": 1, "_id.month": 1 } }
]).toArray());

// ---------- AGGREGATION 3: join notes to reports ($lookup) ----------
printjson(db.clinical_notes.aggregate([
  { $lookup: { from: "lab_reports", localField: "appt_id", foreignField: "appt_id", as: "labs" } },
  { $project: { patient_id: 1, dept: 1, note: 1, lab_count: { $size: "$labs" } } }
]).toArray());
