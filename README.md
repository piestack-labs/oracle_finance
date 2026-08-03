# Maple Leaf Cement — Databricks Demo

**Stores & spares aging on Oracle EBS R12 data, rebuilt on Databricks.**

Demonstrates that the stores aging report — 2.5 months to build, 2 hours to run —
can be rebuilt so it runs in seconds, ties to the trial balance, and shows each
production unit only its own data.

Built on synthetic data. No Maple Leaf data is used in the demo itself.

---

## The case being demonstrated


| Beat         | Claim                                            | Proven in                    |
| ------------ | ------------------------------------------------ | ---------------------------- |
| **Speed**    | Same four data points, seconds not hours         | `02_gold_ferguson_aging.sql` |
| **Trust**    | Numbers tie to GL, drill back to source invoices | `03` parts A/B               |
| **Security** | Each unit sees only its own rows                 | `03` part C                  |


The four data points match the legacy report: item arrival dates, consumption
frequency, average vs last cost, and redundant items.

**The real argument is not runtime.** It is that the rebuild cost collapsed.
When someone says "that's not how we age it," you switch a column on screen
instead of opening another UAT cycle.

---



## The data

Genuine EBS R12 structure — real base-table names, `ORG_ID` striping, XLA
linkage — so queries port to a live instance by changing one path. Contents
fabricated.


| Table                                              | Rows        |
| -------------------------------------------------- | ----------- |
| `mtl_material_transactions`                        | 174,855     |
| `ap_invoice_distributions_all`                     | 27,329      |
| `ap_invoice_lines_all`                             | 27,329      |
| `xla_ae_headers` / `xla_distribution_links`        | 27,329 each |
| `mtl_system_items_b` / `cst_item_costs`            | 11,398 each |
| `mtl_onhand_quantities_detail`                     | 8,988       |
| `ap_invoices_all`                                  | 4,307       |
| `gl_je_lines` / `gl_je_headers`                    | 432 / 72    |
| `gl_code_combinations`                             | 81          |
| `unit_security_map` / `prod_units` / `cc_unit_map` | 12 / 4 / 9  |


**20 CSV files.** Confirm all 20 land in the volume before running notebook 01.

### Planted findings

1. **1,382 item lines received and never issued**, concentrated in the oldest
  aging buckets — idle capital
2. **7,542 items consumed by more than one production unit** — cost attribution
  problem, concentrated in genuinely shared categories
3. **9,090 items where last PO cost exceeds average by more than 15%** — a
  procurement negotiation list

Lead with the dead stock.

---



## Quick start

Free Edition, serverless, ~25 minutes.

1. Run `00_setup.sql` — creates catalog, four schemas, one volume
2. Unzip `maple_ebs_data_v2.zip`, upload all 20 CSVs to the volume
3. Rerun the last cell of `00_setup.sql` — **confirm 20 files**
4. Run `01_bronze_silver.py` (attach to Serverless)
5. Run `02_gold_ferguson_aging.sql`
6. Run `03_reconciliation_and_security.sql`
7. Run `04_genie_setup.sql`, then create the Genie space



### Checkpoints

```sql
SHOW TABLES IN silver;                    -- expect 7
SELECT * FROM gold.recon_ap_to_gl;        -- status = RECONCILED, all 36 periods
```

Uniform aging buckets means an incomplete upload. A failed reconciliation means
stop — don't build dashboards on a tie-out you can't explain.

### If you already loaded v1

Build v2 in a **new catalog** (`oracle_finance_v2`) rather than dropping the old
one. Clone the dashboards and repoint the clones. Column renames:


| v1                         | v2                    |
| -------------------------- | --------------------- |
| `org_code`                 | `primary_unit_code`   |
| `stocked_in_orgs`          | `consuming_units`     |
| `stocked_org_list`         | `consuming_unit_list` |
| `redistribution_candidate` | `shared_across_units` |
| `business_line`            | *(drop — one plant)*  |


Delete the old catalog only after v2 renders correctly. Not on demo day.

---



## Dashboards

**1 — Stores Aging Overview.** Four counters (total value, dead stock value,
never-issued count, over-730-days count); value by aging bucket; movement status
pie; value by `primary_unit_code` split by status; top 10 categories; detail
table. Filters: `primary_unit_code`, `category_name`, `movement_status`.

**2 — Cross-Unit Consumption & Procurement.** Counters for multi-unit items and
revaluation exposure; table of items charged to one unit but drawn by others;
exposure by category; top 25 by exposure.

**3 — Reconciliation.** Two counters, period table, drill-through. Keep it plain
— ugly and reconciled beats pretty and unexplained in front of a controller.
Skip the variance trend chart: all 36 periods are zero, so it renders as an
invisible flat line. Point at the table instead.

Single page each. Filters, not tabs.

---



## Genie

Space over `gold.agg_stores_aging`, `silver.dim_item`, `silver.dim_organization`.
Column comments and instruction text are in `04_genie_setup.sql` — the comments
are the single biggest lever on answer quality.

Vocabulary block must say:

```
- "unit", "production unit", "section" mean primary_unit_code
  (GREY, WHITE, PUTTY, SHARED)
- "shared across units" means consuming_units > 1
- there is one plant and one stores location; do not group by plant or site
```

Rehearsed questions:

- What is the total value of stores stock
- How many items have never been issued
- **Which items are charged to White Cement but also consumed by Grey Cement**
- Show items where last purchase price is more than 20% above average cost
- Which production unit has the most capital tied up in non-moving stock

Then a follow-up — "now show only refractory" — to demonstrate retained context.
Save all of these as verified queries. Rehearse the day before, not on the day.

---



## Assumptions still open

**The aging basis of the legacy report is unconfirmed.** The gold table computes
both `aging_bucket_last_receipt` and `aging_bucket_first_receipt` so the
dashboard can toggle. Bucket boundaries are also invented.

Ask the ERP team for the concurrent program's BI Publisher data template, or one
page of existing output with headers intact. In their language: *"For the stores
aging report, is the age driver the last receipt date, the original receipt
date, or the cost layer date — and does it value at average or last PO cost?"*

**Category-to-unit mapping is educated inference**, not Maple Leaf's actual bill
of materials. Worth a five-minute conversation with someone at the plant.

---



## Say these out loud

- **Volumes** are a fraction of a real three-year MMT extract. Don't quote demo
runtime as production runtime. The honest claim is the *shape* change: one
windowed aggregation replacing per-item correlated subqueries.
- **The GL is thin** (432 lines, summarised journals). Real reconciliation will
surface timing differences, manual journals, and FX revaluation.
- **Security is simulated on Free Edition** — no account groups, so the persona
view is a parameter, not enforcement.
- **No figure here is a Maple Leaf number.** Say it once at the start.

---



## Scope

**Covered:** GL (partial), AP (partial), SLA (core path), Inventory, Costing
(partial).

**Not covered:** AR, Fixed Assets, Cash Management, Tax, intercompany,
consolidation, budgets, encumbrances, procurement.

Deliberate. GL + AP + SLA + Inventory is the minimum that proves all three
claims. If asked: *"This covers the sub-ledger-to-GL path for Payables and
Inventory, which is what the stores aging report depends on. Receivables, Fixed
Assets and Cash Management follow the same pattern — same SLA bridge, same
security model — roughly a five-week increment each once this foundation
exists."*

---



## The sales force files in this project

Six spreadsheets sit alongside this demo: `JobAgingReport`,
`CompetitorBrandReport`, `SalesOfficerPerformanceReport`,
`SalesOfficerVisitFrequency`, `SalesOfficerLeadsPerformance`,
`SalesOfficerVisitSummaryReport`.

**These are real Maple Leaf data and are not part of the demo.** They cover the
retail sales force — visits, dealers, competitor pricing, job completion — with
named regional heads, sales officers, and dealers. Two consequences:

- Loading them into the demo would turn a synthetic showcase into a system
holding live employee performance records. That needs sign-off first.
- `JobAgingReport` is **visit** aging, not stores aging. Similar name, different
domain.

They are, however, a strong **Phase 2** case. The completion-rate variance across
officers is visible at a glance — one officer shows 119 jobs planned and 0
executed — which is exactly the productivity-correlation gap the strategy
document describes, and it is real rather than fabricated.

---



## Effort, if this becomes real

First domain against a live instance: **8–12 weeks, ~600 hours**. Two people —
one senior data engineer full-time, one Oracle functional at ~40%. Second domain
roughly half; third onwards faster.

Phase 1 (three domains, ~6 months): ~1,460 hours, about 2 FTE. Steady state
after go-live: 0.5 FTE data engineer plus 100–150 hours a year of ERP functional
time.

Critical path runs through **access approvals** and **reconciliation sign-off**.
Neither parallelises. The role people skip and shouldn't is a Finance person with
authority to *approve* the reconciliation — 20 hours of their time, but the
project stalls without them.

---



## Licensing

Databricks Free Edition is for non-commercial use. Build there; run the demo for
Finance on a **14-day Free Trial** workspace, which has no such restriction and
supports real account groups so the security beat works properly. Rebuilding on
Trial takes under an hour. Start the trial about three days before the demo.