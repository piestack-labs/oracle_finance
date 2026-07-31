-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 02 — Gold: Ferguson Stores & Spares Aging
-- MAGIC
-- MAGIC Rebuild of the existing 2.5-month-to-build / 2-hour-to-run report.
-- MAGIC Covers all four data points the current report produces:
-- MAGIC item arrival dates, consumption frequency, average vs last cost,
-- MAGIC and redundant items across locations.
-- MAGIC
-- MAGIC The whole thing is one windowed pass over a partitioned Delta table.
-- MAGIC The two-hour runtime in EBS comes from per-item correlated subqueries
-- MAGIC against MMT — that is the shape being eliminated here, not the volume.

-- COMMAND ----------

USE CATALOG oracle_finance;

-- COMMAND ----------

CREATE OR REPLACE TABLE gold.agg_stores_aging AS
WITH ref AS (
    SELECT DATE'2026-06-30' AS as_of_date
),
txn_profile AS (
    -- single aggregation replaces the correlated per-item subqueries
    SELECT
        inventory_item_id,
        org_id,
        MAX(CASE WHEN txn_type_id = 18 THEN txn_date END)  AS last_receipt_date,
        MIN(CASE WHEN txn_type_id = 18 THEN txn_date END)  AS first_receipt_date,
        MAX(CASE WHEN txn_type_id = 33 THEN txn_date END)  AS last_issue_date,
        COUNT_IF(txn_type_id = 33)                         AS issue_txn_count,
        COUNT_IF(txn_type_id = 18)                         AS receipt_txn_count,
        SUM(CASE WHEN txn_type_id = 33 THEN -primary_quantity ELSE 0 END) AS qty_consumed,
        COUNT(DISTINCT CASE WHEN txn_type_id = 18 THEN vendor_id END)     AS distinct_suppliers
    FROM silver.fact_material_txn
    GROUP BY inventory_item_id, org_id
),
redundancy AS (
    -- same item number carried in more than one plant
    SELECT item_number,
           COUNT(DISTINCT org_id)               AS stocked_in_orgs,
           collect_set(org_code)                AS stocked_org_list
    FROM silver.dim_item
    GROUP BY item_number
)
SELECT
    i.item_number,
    i.item_description,
    i.category_name,
    i.org_code,
    i.region,
    i.business_line,
    i.uom,

    oh.PRIMARY_TRANSACTION_QUANTITY                         AS onhand_qty,
    c.ITEM_COST                                             AS average_cost,
    c.LAST_PO_COST                                          AS last_po_cost,
    ROUND(oh.PRIMARY_TRANSACTION_QUANTITY * c.ITEM_COST, 2) AS onhand_value_avg_cost,
    ROUND(oh.PRIMARY_TRANSACTION_QUANTITY * c.LAST_PO_COST, 2) AS onhand_value_last_cost,

    -- average vs last cost divergence: the procurement negotiation lever
    ROUND((c.LAST_PO_COST - c.ITEM_COST) / NULLIF(c.ITEM_COST, 0) * 100, 2) AS cost_variance_pct,
    ROUND(oh.PRIMARY_TRANSACTION_QUANTITY * (c.LAST_PO_COST - c.ITEM_COST), 2) AS revaluation_exposure,

    -- arrival dating
    t.first_receipt_date,
    t.last_receipt_date,
    DATEDIFF(r.as_of_date, t.last_receipt_date)             AS days_since_receipt,

    -- consumption frequency
    t.last_issue_date,
    DATEDIFF(r.as_of_date, t.last_issue_date)               AS days_since_issue,
    t.issue_txn_count,
    t.receipt_txn_count,
    t.distinct_suppliers,
    ROUND(t.qty_consumed / NULLIF(MONTHS_BETWEEN(r.as_of_date, t.first_receipt_date), 0), 3)
                                                            AS avg_monthly_consumption,
    CASE WHEN t.qty_consumed > 0
         THEN ROUND(oh.PRIMARY_TRANSACTION_QUANTITY
              / NULLIF(t.qty_consumed / NULLIF(MONTHS_BETWEEN(r.as_of_date, t.first_receipt_date), 0), 0), 1)
    END                                                     AS months_of_cover,

    -- Two aging bases computed side by side. The business has not yet confirmed
    -- which one the legacy report uses, so the dashboard toggles between them
    -- rather than requiring a rebuild. Bucket boundaries are also assumptions -
    -- confirm against the documented obsolescence policy before quoting numbers.
    DATEDIFF(r.as_of_date, t.first_receipt_date)            AS days_since_first_receipt,

    CASE
        WHEN DATEDIFF(r.as_of_date, t.last_receipt_date) <= 90  THEN '1. 0-90 days'
        WHEN DATEDIFF(r.as_of_date, t.last_receipt_date) <= 180 THEN '2. 91-180 days'
        WHEN DATEDIFF(r.as_of_date, t.last_receipt_date) <= 365 THEN '3. 181-365 days'
        WHEN DATEDIFF(r.as_of_date, t.last_receipt_date) <= 730 THEN '4. 366-730 days'
        ELSE '5. Over 730 days'
    END                                                     AS aging_bucket_last_receipt,

    CASE
        WHEN DATEDIFF(r.as_of_date, t.first_receipt_date) <= 90  THEN '1. 0-90 days'
        WHEN DATEDIFF(r.as_of_date, t.first_receipt_date) <= 180 THEN '2. 91-180 days'
        WHEN DATEDIFF(r.as_of_date, t.first_receipt_date) <= 365 THEN '3. 181-365 days'
        WHEN DATEDIFF(r.as_of_date, t.first_receipt_date) <= 730 THEN '4. 366-730 days'
        ELSE '5. Over 730 days'
    END                                                     AS aging_bucket_first_receipt,

    CASE
        WHEN COALESCE(t.issue_txn_count, 0) = 0             THEN 'Dead Stock - Never Issued'
        WHEN DATEDIFF(r.as_of_date, t.last_issue_date) > 365 THEN 'Non-Moving - 12m+'
        WHEN DATEDIFF(r.as_of_date, t.last_issue_date) > 180 THEN 'Slow Moving - 6m+'
        ELSE 'Active'
    END                                                     AS movement_status,

    COALESCE(rd.stocked_in_orgs, 1)                         AS stocked_in_orgs,
    rd.stocked_org_list,
    CASE WHEN COALESCE(rd.stocked_in_orgs, 1) > 1
              AND COALESCE(t.issue_txn_count, 0) = 0
         THEN TRUE ELSE FALSE END                           AS redistribution_candidate,

    i.org_id
FROM silver.dim_item i
JOIN oracle_finance.bronze.mtl_onhand_quantities_detail oh
     ON oh.INVENTORY_ITEM_ID = i.inventory_item_id
    AND oh.ORGANIZATION_ID   = i.org_id
JOIN oracle_finance.bronze.cst_item_costs c
     ON c.INVENTORY_ITEM_ID = i.inventory_item_id
    AND c.ORGANIZATION_ID   = i.org_id
LEFT JOIN txn_profile t
     ON t.inventory_item_id = i.inventory_item_id
    AND t.org_id            = i.org_id
LEFT JOIN redundancy rd ON rd.item_number = i.item_number
CROSS JOIN ref r;

-- COMMAND ----------

-- MAGIC %md ## Demo query 1 — the headline the CFO sees

-- COMMAND ----------

SELECT aging_bucket_last_receipt AS aging_bucket,
       COUNT(*)                                   AS stock_lines,
       ROUND(SUM(onhand_value_avg_cost)/1e6, 1)   AS value_pkr_mn,
       COUNT_IF(movement_status = 'Dead Stock - Never Issued') AS dead_stock_lines,
       ROUND(SUM(CASE WHEN movement_status = 'Dead Stock - Never Issued'
                      THEN onhand_value_avg_cost ELSE 0 END)/1e6, 1) AS dead_value_pkr_mn
FROM gold.agg_stores_aging
GROUP BY aging_bucket_last_receipt
ORDER BY aging_bucket_last_receipt;

-- COMMAND ----------

-- MAGIC %md ## Demo query 2 — redistribution instead of purchase
-- MAGIC Items sitting dead in one plant while another plant consumes them.

-- COMMAND ----------

SELECT item_number, item_description, category_name,
       SUM(onhand_qty)                            AS total_onhand,
       ROUND(SUM(onhand_value_avg_cost)/1e6, 2)   AS value_pkr_mn,
       collect_set(org_code)                      AS held_in,
       collect_set(movement_status)               AS status_mix
FROM gold.agg_stores_aging
WHERE stocked_in_orgs > 1
GROUP BY item_number, item_description, category_name
HAVING array_contains(collect_set(movement_status), 'Dead Stock - Never Issued')
   AND array_contains(collect_set(movement_status), 'Active')
ORDER BY value_pkr_mn DESC
LIMIT 50;

-- COMMAND ----------

-- MAGIC %md ## Demo query 3 — procurement negotiation list
-- MAGIC Where last PO cost has run well ahead of moving average.

-- COMMAND ----------

SELECT category_name,
       COUNT(*)                                        AS items,
       ROUND(AVG(cost_variance_pct), 1)                AS avg_variance_pct,
       ROUND(SUM(revaluation_exposure)/1e6, 1)         AS exposure_pkr_mn
FROM gold.agg_stores_aging
WHERE cost_variance_pct > 15
GROUP BY category_name
ORDER BY exposure_pkr_mn DESC;
