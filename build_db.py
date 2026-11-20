"""Creates medicore.db from 01_schema.sql and loads reproducible synthetic data."""
import sqlite3, random, datetime as dt, os
random.seed(42)
DB = os.path.join(os.path.dirname(__file__), "medicore.db")
if os.path.exists(DB): os.remove(DB)
con = sqlite3.connect(DB)
con.executescript(open(os.path.join(os.path.dirname(__file__), "01_schema.sql")).read())

depts = ["Cardiology","Orthopaedics","Paediatrics","General Medicine","Dermatology","ENT","Gynaecology","Neurology"]
con.executemany("INSERT INTO departments VALUES (?,?,?)", [(i+1, n, 1+i%4) for i, n in enumerate(depts)])

diag = {1:[("I10","Hypertension"),("I20","Angina"),("I48","Atrial fibrillation")],
        2:[("M54","Back pain"),("M17","Knee osteoarthritis"),("S52","Forearm fracture")],
        3:[("J06","Upper respiratory infection"),("A09","Gastroenteritis"),("J45","Asthma")],
        4:[("E11","Type 2 diabetes"),("J11","Influenza"),("R50","Fever")],
        5:[("L20","Atopic dermatitis"),("L70","Acne"),("B35","Tinea")],
        6:[("J32","Chronic sinusitis"),("H66","Otitis media"),("J35","Tonsillitis")],
        7:[("N92","Menstrual disorder"),("O09","Antenatal care"),("N76","Vaginitis")],
        8:[("G43","Migraine"),("G40","Epilepsy"),("G44","Tension headache")]}
diag_rows, did = [], 1
for d, lst in diag.items():
    for code, desc in lst: diag_rows.append((did, code, desc, d)); did += 1
con.executemany("INSERT INTO diagnoses VALUES (?,?,?,?)", diag_rows)

first = ["Aarav","Vivaan","Ananya","Diya","Rohan","Isha","Kabir","Meera","Arjun","Sneha","Nikhil","Priya","Rahul","Kavya","Sanjay","Lakshmi","Imran","Fatima","Suresh","Divya"]
last  = ["Sharma","Reddy","Iyer","Nair","Gupta","Khan","Patel","Rao","Menon","Das","Joshi","Kulkarni"]
doc_fee = {1:900,2:800,3:600,4:500,5:700,6:650,7:800,8:1000}
doctors, i = [], 1
for d in range(1, 9):
    for k in range(2):
        doctors.append((i, f"Dr. {random.choice(first)} {random.choice(last)}", d, doc_fee[d]+k*100, "09:00", "17:00")); i += 1
con.executemany("INSERT INTO doctors VALUES (?,?,?,?,?,?)", doctors)

cities = ["Bengaluru","Mysuru","Mangaluru","Hubballi","Tumakuru"]
pats = []
for p in range(1, 401):
    pats.append((p, f"{random.choice(first)} {random.choice(last)}",
                 (dt.date(2026,1,1) - dt.timedelta(days=random.randint(200, 30000))).isoformat(),
                 random.choice("MMFFO"), str(9000000000 + p*7919 % 99999999).zfill(10)[:10], random.choice(cities)))
con.executemany("INSERT INTO patients VALUES (?,?,?,?,?,?)", pats)

slots = [f"{h:02d}:{m}" for h in range(9, 17) for m in ("00","30")]
hour_w = {9:.55,10:.9,11:.95,12:.6,13:.35,14:.6,15:.7,16:.5}
meds = ["Paracetamol","Amoxicillin","Metformin","Amlodipine","Cetirizine","Ibuprofen","Pantoprazole","Salbutamol"]
start = dt.date(2026, 8, 3)
day_list = [start + dt.timedelta(days=n) for n in range(0, 91) if (start + dt.timedelta(days=n)).weekday() < 5]
pop = {d[0]: random.uniform(.55, 1.0) for d in doctors}
used_p, aid, bid, pid = set(), 1, 1, 1
appts, bills, rx = [], [], []
for wk, day in enumerate(day_list):
    trend = 1 + (day - start).days / 180        # waiting time creeps up over the quarter
    for doc in doctors:
        for s in slots:
            h = int(s[:2])
            if random.random() > hour_w[h] * pop[doc[0]]: continue
            pat = random.randint(1, 400)
            if (pat, day, s) in used_p: continue
            used_p.add((pat, day, s))
            r = random.random()
            ns_bias = .15 if day.weekday() in (0, 4) else .09   # Mondays/Fridays miss more
            status = "No-Show" if r < ns_bias else "Cancelled" if r < ns_bias + .08 else "Completed"
            wait = dg = None
            if status == "Completed":
                wait = max(0, int(random.gauss(8 + (h-9)*3 + doc[2]*1.5, 6) * trend))
                dg = random.choice([x for x in diag_rows if x[3] == doc[2]])[0]
            appts.append((aid, pat, doc[0], day.isoformat(), s, status, wait, dg))
            if status == "Completed":
                amt = doc[3] + random.choice([0, 0, 250, 500, 1200])
                paid = random.choice([amt, amt, amt, amt/2, 0])
                bills.append((bid, aid, amt, paid, "Paid" if paid == amt else "Partial" if paid else "Pending", day.isoformat())); bid += 1
                if random.random() < .7:
                    rx.append((pid, aid, random.choice(meds), random.choice(["1-0-1","0-0-1","1-1-1"]), random.choice([3,5,7,14]))); pid += 1
            aid += 1
con.executemany("INSERT INTO appointments VALUES (?,?,?,?,?,?,?,?)", appts)
con.executemany("INSERT INTO bills VALUES (?,?,?,?,?,?)", bills)
con.executemany("INSERT INTO prescriptions VALUES (?,?,?,?,?)", rx)
con.commit()
print({t: con.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0] for t in
       ["departments","doctors","patients","diagnoses","appointments","prescriptions","bills"]})
