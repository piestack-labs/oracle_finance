-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 03 — Trial-Balance Tie-Out & Operating-Unit Security
-- MAGIC
-- MAGIC Two things that decide whether Finance accepts the platform:
-- MAGIC can it prove the numbers tie to GL, and does it respect MOAC.

-- COMMAND ----------

USE CATALOG oracle_finance;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## A. AP sub-ledger to GL reconciliation via SLA
-- MAGIC Walks AP distributions through XLA into GL. If this reconciles on
-- MAGIC screen, the "can we trust it" objection is answered in one slide.

-- COMMAND ----------

CREATE OR REPLACE TABLE gold.recon_ap_to_gl AS
WITH ap_side AS (
    SELECT d.period_name,
           o.org_code,
           COUNT(*)               AS ap_distribution_count,
           ROUND(SUM(d.amount),2) AS ap_amount
    FROM silver.fact_ap_distribution d
    JOIN silver.dim_organization o ON o.org_id = d.org_id
    GROUP BY d.period_name, o.org_code
),
sla_side AS (
    SELECT b.period_name,
           COUNT(*)                            AS sla_link_count,
           ROUND(SUM(d.amount), 2)             AS sla_amount
    FROM silver.bridge_sla_gl b
    JOIN silver.fact_ap_distribution d
      ON d.invoice_distribution_id = b.invoice_distribution_id
    GROUP BY b.period_name
),
gl_side AS (
    SELECT l.period_name,
           ROUND(SUM(l.accounted_dr), 2) AS gl_debit,
           ROUND(SUM(l.accounted_cr), 2) AS gl_credit
    FROM silver.fact_gl_line l
    JOIN silver.dim_account a ON a.code_combination_id = l.code_combination_id
    WHERE l.je_source = 'Payables'
      AND a.natural_account = '1310'          -- Stores & Spares Inventory
    GROUP BY l.period_name
)
SELECT COALESCE(ap.period_name, g.period_name) AS period_name,
       SUM(ap.ap_amount)                       AS ap_subledger_total,
       MAX(s.sla_amount)                       AS sla_bridged_total,
       MAX(g.gl_debit)                         AS gl_posted_total,
       ROUND(SUM(ap.ap_amount) - MAX(g.gl_debit), 2) AS variance,
       CASE WHEN ABS(COALESCE(SUM(ap.ap_amount),0) - COALESCE(MAX(g.gl_debit),0)) < 1
            THEN 'RECONCILED' ELSE 'INVESTIGATE' END AS status
FROM ap_side ap
FULL OUTER JOIN gl_side  g ON g.period_name = ap.period_name
LEFT JOIN      sla_side  s ON s.period_name = COALESCE(ap.period_name, g.period_name)
GROUP BY COALESCE(ap.period_name, g.period_name);

-- COMMAND ----------

SELECT * FROM gold.recon_ap_to_gl ORDER BY to_date(period_name, 'MMM-yy');

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## B. Drill-through: one GL balance back to source invoices
-- MAGIC The question every auditor asks. Answer it live.

-- COMMAND ----------

SELECT d.invoice_num, d.vendor_name, d.invoice_date, d.amount,
       a.concatenated_segments, a.account_name,
       b.je_header_id, b.gl_sl_link_id
FROM silver.fact_ap_distribution d
JOIN silver.bridge_sla_gl b ON b.invoice_distribution_id = d.invoice_distribution_id
JOIN silver.dim_account   a ON a.code_combination_id = d.code_combination_id
WHERE d.period_name = 'MAR-26'
  AND a.natural_account = '1310'
ORDER BY d.amount DESC
LIMIT 25;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## C. Operating-unit security — Free Edition substitute
-- MAGIC
-- MAGIC In production this is a Unity Catalog **row filter** driven by account
-- MAGIC group membership, so a user cannot bypass it. Free Edition has no access
-- MAGIC to the account console and no SCIM, so account groups cannot be created
-- MAGIC and `is_account_group_member()` has nothing to resolve against.
-- MAGIC
-- MAGIC The view below reproduces the *effect* for the demo. Say this out loud
-- MAGIC when you show it — if a technical person is in the room and you imply
-- MAGIC this is enforced security, you lose credibility you will need later.
-- MAGIC
-- MAGIC The production version is in `03_reconciliation_and_security.sql`
-- MAGIC (the non-Free-Edition copy). Run that one on a Trial workspace.

-- COMMAND ----------

CREATE WIDGET TEXT persona DEFAULT 'BOARD';

-- COMMAND ----------

CREATE OR REPLACE VIEW gold.vw_stores_aging_secured AS
SELECT * FROM gold.agg_stores_aging
WHERE CASE
    WHEN '${persona}' = 'BOARD' THEN TRUE
    WHEN '${persona}' = 'GCI'   THEN org_code = 'GCI'   -- Grey, Iskanderabad
    WHEN '${persona}' = 'WCI'   THEN org_code = 'WCI'   -- White, Iskanderabad
    WHEN '${persona}' = 'GCM'   THEN org_code = 'GCM'   -- Grey, Mianwali
    ELSE FALSE
END;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Change the widget at the top of the notebook and rerun the cell below.
-- MAGIC BOARD sees everything; a plant persona sees only its own rows.
-- MAGIC Same query, same dashboard, no code change — that is the point being made.

-- COMMAND ----------

SELECT '${persona}'                             AS running_as,
       COUNT(DISTINCT org_code)                 AS orgs_visible,
       COUNT(*)                                 AS rows_visible,
       ROUND(SUM(onhand_value_avg_cost)/1e6, 1) AS value_visible_pkr_mn
FROM gold.vw_stores_aging_secured;
