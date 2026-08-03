-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 03 — Trial-Balance Tie-Out
-- MAGIC
-- MAGIC Proves the numbers tie to GL. This is the "can we trust it" beat —
-- MAGIC more important to Finance than speed.

-- COMMAND ----------

USE CATALOG oracle_finance_v2;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## A. AP sub-ledger to GL reconciliation via SLA
-- MAGIC Walks AP distributions through XLA into GL. If this reconciles on
-- MAGIC screen, the "can we trust it" objection is answered in one slide.

-- COMMAND ----------

CREATE OR REPLACE TABLE gold.recon_ap_to_gl AS
WITH ap_side AS (
    SELECT d.period_name,
           COUNT(*)               AS ap_distribution_count,
           ROUND(SUM(d.amount),2) AS ap_amount
    FROM silver.fact_ap_distribution d
    GROUP BY d.period_name
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
