"""Python DB-API (sqlite3) layer: DML demo, trigger test, analytics queries and charts."""
import sqlite3, re, os
import pandas as pd
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))
con = sqlite3.connect(os.path.join(HERE, "medicore.db"))
con.execute("PRAGMA foreign_keys = ON")

def load_queries(path):
    text, out = open(path).read(), {}
    for name, body in re.findall(r"-- name: (\w+)\n(.*?)(?=\n-- name:|\Z)", text, re.S):
        out[name] = body.strip()
    return out
Q = load_queries(os.path.join(HERE, "03_analytics.sql"))
df = lambda name: pd.read_sql_query(Q[name], con)

# ---------- DML + trigger demo ----------
def book(pid, did, date, slot):
    try:
        with con:
            cur = con.execute("INSERT INTO appointments (patient_id,doctor_id,appt_date,slot_time) VALUES (?,?,?,?)",
                              (pid, did, date, slot))
        return cur.lastrowid
    except sqlite3.DatabaseError as e:
        print("  REJECTED:", e); return None

print("== Booking / double-booking trigger / reschedule / cancel ==")
a = book(1, 1, "2026-11-25", "10:00");      print("  booked appt", a)
book(2, 1, "2026-11-25", "10:00")           # same doctor+slot -> trigger blocks
book(1, 2, "2026-11-25", "10:00")           # same patient, other doctor, same slot -> blocked
book(3, 1, "2026-11-25", "10:15")           # off-grid slot -> CHECK blocks
with con: con.execute("UPDATE appointments SET appt_date=?, slot_time=? WHERE appt_id=? AND status='Booked'",
                      ("2026-11-26", "11:30", a))
print("  rescheduled; slot 10:00 on 25 Nov free again ->", book(2, 1, "2026-11-25", "10:00") is not None)
with con: con.execute("UPDATE appointments SET status='Cancelled' WHERE appt_id=? AND status='Booked'", (a,))
print("  cancelled appt", a)

# ---------- Reports ----------
for name in ["peak_hours", "doctor_utilisation", "no_show_rate", "top_diagnoses",
             "revenue_by_dept", "slow_doctors", "repeat_no_show_patients", "no_show_by_weekday"]:
    print(f"\n== {name} ==\n", df(name).head(10).to_string(index=False))

# ---------- Charts ----------
load = df("load_by_dept_hour").pivot(index="dept_name", columns="hour", values="appointments").fillna(0)
fig, ax = plt.subplots(figsize=(9, 4.5))
im = ax.imshow(load.values, cmap="YlOrRd", aspect="auto")
ax.set_xticks(range(len(load.columns)), [f"{h}:00" for h in load.columns]); ax.set_yticks(range(len(load.index)), load.index)
for (y, x), v in pd.DataFrame(load.values).stack().items(): ax.text(x, y, int(v), ha="center", va="center", fontsize=7)
ax.set_title("Department load: appointments by hour of day"); fig.colorbar(im, label="appointments")
fig.tight_layout(); fig.savefig(os.path.join(HERE, "chart_dept_load_heatmap.png"), dpi=150); plt.close(fig)

w = df("weekly_wait"); w["week_start"] = pd.to_datetime(w["week_start"])
fig, ax = plt.subplots(figsize=(9, 4.5))
for dept, g in w.groupby("dept_name"): ax.plot(g["week_start"], g["avg_wait"], marker="o", ms=3, lw=1, alpha=.55, label=dept)
overall = pd.read_sql_query("SELECT date(appt_date,'weekday 0','-6 days') wk, AVG(wait_minutes) m FROM appointments WHERE status='Completed' GROUP BY wk", con)
ax.plot(pd.to_datetime(overall["wk"]), overall["m"], color="black", lw=3, label="Hospital average")
ax.set_title("Average waiting time per week (minutes)"); ax.set_ylabel("minutes"); ax.legend(fontsize=7, ncol=3)
fig.autofmt_xdate(); fig.tight_layout(); fig.savefig(os.path.join(HERE, "chart_waiting_time_trend.png"), dpi=150); plt.close(fig)

ns = df("no_show_rate")
fig, ax = plt.subplots(figsize=(8, 4)); ax.barh(ns["dept_name"], ns["no_show_pct"], color="#c0392b")
ax.invert_yaxis(); ax.set_xlabel("no-show %"); ax.set_title("No-show rate by department")
fig.tight_layout(); fig.savefig(os.path.join(HERE, "chart_no_show_rate.png"), dpi=150); plt.close(fig)

ut = df("doctor_utilisation")
fig, ax = plt.subplots(figsize=(8, 5)); ax.barh(ut["full_name"] + " (" + ut["dept_name"] + ")", ut["utilisation_pct"], color="#2471a3")
ax.invert_yaxis(); ax.set_xlabel("utilisation %"); ax.set_title("Doctor utilisation")
fig.tight_layout(); fig.savefig(os.path.join(HERE, "chart_doctor_utilisation.png"), dpi=150); plt.close(fig)
print("\nCharts saved.")
