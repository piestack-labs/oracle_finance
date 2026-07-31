**Stores & spares aging on Oracle EBS R12 data, rebuilt on Databricks.**

A working demonstration that the stores aging report — which took 2.5 months to
build and runs for 2 hours — can be rebuilt so that it runs in seconds, ties to
the trial balance, and shows each user only their own plant.

Built on synthetic data. No real data is used anywhere in this project.

---

## 1. The case being demonstrated

One report, three claims:

| Beat | Claim | Where it's proven |
|---|---|---|
| **Speed** | The same four data points, in seconds not hours | `02_gold_ferguson_aging.sql` |
| **Trust** | The numbers tie to General Ledger, and drill back to source invoices | `03_reconciliation_and_security.sql` part A/B |
| **Security** | Each user sees only their operating unit, no code change | `03` part C |

The report reproduces the four data points of the existing one: item arrival
dates, consumption frequency, average vs last cost, and redundant items across
locations.

**The real argument** is not runtime. It is that the *rebuild cost collapsed*.
When someone says "that's not how we age it," you switch a column on screen
instead of opening another UAT cycle.

---

## 2. What's in the repository

```
generate_ebs_demo_data.py    synthetic EBS R12 dataset generator (seeded, reproducible)
validate_aging.py            local sanity check on the planted findings
maple_ebs_demo_data.zip      18 CSVs, 9.9 MB compressed / 44 MB raw

free_edition/
  00_setup.sql               catalog, schemas, volume
  01_bronze_silver.py        bronze load + conformed silver layer
  02_gold_ferguson_aging.sql aging gold table + three demo queries
  03_reconciliation_and_security.sql   AP->SLA->GL tie-out, drill-through, persona view
  04_genie_setup.sql         column comments, Genie instructions, verified queries
```

The non-`free_edition` copies of `01`/`03` are the production versions: they
include `OPTIMIZE ZORDER` and a real Unity Catalog row filter. Use those on a
Trial or paid workspace.

---

## 3. The data

Structure is genuine EBS R12 — real base-table names, key columns, `ORG_ID`
striping, and XLA linkage — so queries port to a live instance by changing one
path. Contents are fabricated.

| Table | Rows | Purpose |
|---|---|---|
| `mtl_system_items_b` | 21,393 | Item master, 3 plants |
| `mtl_material_transactions` | 316,077 | 3 years of receipts (type 18) and issues (type 33) |
| `mtl_onhand_quantities_detail` | 16,853 | Current stock position |
| `cst_item_costs` | 21,393 | Average and last PO cost |
| `ap_invoices_all` / lines / distributions | 12,600 / 50,183 / 50,183 | Supplier invoices linked to receipts |
| `xla_ae_headers` / `xla_distribution_links` | 50,183 each | SLA bridge, 1:1 with AP distributions |
| `gl_je_headers` / `gl_je_lines` | 216 / 1,188 | Posted journals, DR = CR exactly |
| `gl_code_combinations` | 288 | 5-segment flexfield |
| `org_security_map` | 12 | Drives the row filter |

**Three findings are planted deliberately**, so the demo discovers something
rather than just rendering rows:

1. **2,526 item lines received and never issued**, concentrated in the oldest
   aging buckets — idle capital
2. **~3,700 item numbers stocked in more than one plant**, several dead in one
   while actively consumed in another — a redistribution list
3. **Last PO cost well above moving average on most of the master** — a
   procurement negotiation list by category

Lead with the dead stock. It's the finding that makes a CFO ask questions.

---

## 4. Quick start

Free Edition, serverless, ~25 minutes to first result.

1. Run `00_setup.sql` — creates `oracle_finance` catalog, four schemas, one volume
2. Unzip the data, upload all 18 CSVs to
   `/Volumes/oracle_finance/landing/ebs_extract`
3. Run the last cell of `00_setup.sql` — **confirm 18 files** before continuing
4. Run `01_bronze_silver.py` (attach to Serverless)
5. Run `02_gold_ferguson_aging.sql`
6. Run `03_reconciliation_and_security.sql`
7. Run `04_genie_setup.sql`, then create the Genie space and paste in the
   instruction block from its markdown cell

### Checkpoints

```sql
SHOW TABLES IN oracle_finance.silver;              -- expect 7
SELECT * FROM oracle_finance.gold.recon_ap_to_gl;  -- status = RECONCILED, every period
```

If aging buckets look uniform, the CSV upload was incomplete. If reconciliation
fails, stop — do not build dashboards on a tie-out you can't explain.

---

## 5. Demo script (~35 min)

1. **Start the existing Ferguson report first.** Leave it running, visible. It's
   the control group.
2. **Show lineage** in Unity Catalog while it runs.
3. **Aging** — bucket summary, then drill into dead stock.
4. **Redistribution** — items dead in one plant, active in another.
5. **Reconciliation** — AP -> SLA -> GL, RECONCILED. Drill one balance to invoices.
6. **Security** — switch persona, row count changes, no code change.
7. **Genie** — three rehearsed questions plus one follow-up that keeps context.
8. **Close** on the still-running control report.

### Dashboards

- **Stores Aging Overview** — KPI tiles, bucket chart, movement donut, detail table
- **Redistribution & Procurement** — cross-plant duplicates, cost variance by category
- **Reconciliation** — period tie-out, variance trend, drill-through

Keep the third one deliberately plain. Ugly and reconciled beats pretty and
unexplained in front of a controller.

---

## 6. Assumptions that need confirming

**The aging basis of the legacy report is unknown.** The gold table computes
two bases side by side (`aging_bucket_last_receipt` and
`aging_bucket_first_receipt`) so the dashboard can toggle. Bucket boundaries
(0-90 / 91-180 / 181-365 / 366-730 / 730+) are also invented.

To confirm, ask the ERP team for the concurrent program's BI Publisher data
template, or for one page of existing report output with column headers intact.
The question, in their language: *"For the stores aging report, is the age driver
the last receipt date, the original receipt date, or the cost layer date — and
does it value at average cost or last PO cost?"*

Also unconfirmed: whether "redundant item analysis" means the same item number
across plants (what's built here) or duplicate item masters describing the same
physical part — a harder and more valuable problem.

---

## 7. Say these out loud

**Volumes.** Roughly a tenth of a real three-year MMT extract. Don't quote the
demo runtime as a production number. The honest claim is the *shape* change:
one windowed aggregation replacing per-item correlated subqueries.

**The GL is thin.** 1,188 journal lines, because journals are summarised. Real
reconciliation will surface timing differences, manual journals, and FX
revaluation this data doesn't contain.

**Security is simulated on Free Edition.** No account groups available, so the
persona view is a parameter, not enforcement. State the difference.

**No figure here is a Maple Leaf number.** Label the screen as illustrative once
at the start, or a screenshot will resurface later as though it meant something.

---

## 8. Scope

**Covered:** GL (partial), AP (partial), SLA (core path), Inventory, Costing
(partial).

**Not covered:** AR, Fixed Assets, Cash Management, Tax, intercompany and
consolidation, budgets, encumbrances, procurement.

This is deliberate. GL + AP + SLA + Inventory is the minimum that proves all
three claims. A demo spanning nine modules invites "where's the fixed asset
register?" from someone who wasn't going to approve it anyway.

The line to use if asked: *"This covers the sub-ledger-to-GL path for Payables
and Inventory, which is what the stores aging report depends on. Receivables,
Fixed Assets and Cash Management follow the same pattern — same SLA bridge, same
security model — and each is roughly a five-week increment once this foundation
exists."*

---

## 9. Effort, if this becomes real

First domain against a live instance: **8–12 weeks calendar, ~600 hours**,
two developers — one senior data engineer full-time, one Oracle functional
person at ~40%. Second domain roughly half that; third onwards faster.

Full Phase 1 (three domains, ~6 months): ~1,460 hours, about 2 FTE.

Steady state after go-live: 0.5 FTE data engineer plus 100–150 hours a year of
ERP functional time.

The critical path runs through **access approvals** and **reconciliation
sign-off**, and neither parallelises. Adding engineers doesn't compress it. The
role people skip and shouldn't is a Finance person with authority to *approve*
the reconciliation — about 20 hours of their time, but the project stalls
without them.

---

## 10. Licensing note

Databricks Free Edition is for non-commercial use. Build and learn there; run
the demo for Finance on a 14-day Free Trial workspace, which has no such
restriction and supports real account groups so the security beat works
properly. Rebuilding on Trial takes under an hour. Start the trial about three
days before the demo date.