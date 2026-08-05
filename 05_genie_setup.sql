-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 04 — Genie Preparation
-- MAGIC
-- MAGIC Run this before creating the Genie space. Column comments are the single
-- MAGIC biggest lever on Genie answer quality — it reads them as context. An hour
-- MAGIC of work here is the difference between a reliable demo and a coin flip.

-- COMMAND ----------

COMMENT ON TABLE maple_demo.gold.agg_stores_aging IS
  'Stores and spares inventory aging for Maple Leaf Cement plants. One row per
   item per plant. Contains current stock position, age since receipt, movement
   status, cost variance, and cross-plant redundancy flags. Values are Pakistani
   Rupees. Synthetic demo data.';

-- COMMAND ----------

COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.item_number IS 'Item code from the stores catalogue. Maple Leaf has one plant with one stores location, so each item number is a single row.';
COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.item_description IS 'Plain-language description of the spare part.';
COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.category_name IS 'Spare part category, for example refractory, bearings, conveyor, electrical.';
COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.primary_unit_code IS 'Production unit the item is primarily charged to: GREY (Grey Cement), WHITE (White Cement), PUTTY (HD Putty), or SHARED (plant-wide, no single unit). Users often say unit, production line, or section to mean this.';
COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.org_code IS 'Operating unit code. Maple Leaf has a single plant, so this is always MLC and carries no filtering value. Use primary_unit_code instead when the user asks about unit, line, or section.';
COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.business_line IS 'Constant - Maple Leaf Cement, Mianwali. Not useful for grouping; there is only one plant.';
COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.region IS 'Constant - Mianwali. Not useful for grouping; there is only one plant.';

COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.onhand_qty IS 'Current quantity physically in the stores.';
COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.onhand_value_avg_cost IS 'DEFAULT MEASURE OF VALUE. Stock value in Rupees at moving average cost. When a user says value, worth, or amount without qualification, use this column.';
COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.onhand_value_last_cost IS 'Stock value at the most recent purchase price. Use only when the user explicitly asks about last purchase price or replacement cost.';
COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.average_cost IS 'Moving average unit cost.';
COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.last_po_cost IS 'Unit price on the most recent purchase order.';
COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.cost_variance_pct IS 'Percentage by which the last purchase price exceeds moving average cost. A high positive value means prices are rising and the item is a procurement negotiation candidate.';
COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.revaluation_exposure IS 'Rupee impact if all stock were revalued from average to last purchase cost.';

COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.last_receipt_date IS 'Date the item was most recently received into stores.';
COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.first_receipt_date IS 'Date the item was first ever received.';
COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.days_since_receipt IS 'Days between the most recent goods receipt and the reporting date.';
COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.last_issue_date IS 'Date the item was last issued out of stores for use.';
COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.days_since_issue IS 'Days since the item was last consumed. Null means it has never been issued.';
COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.issue_txn_count IS 'Number of times the item has been issued. Zero means never consumed.';
COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.avg_monthly_consumption IS 'Average quantity consumed per month since first receipt.';
COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.months_of_cover IS 'How many months current stock would last at average consumption. High values indicate overstocking.';

COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.aging_bucket_last_receipt IS 'DEFAULT AGING BUCKET. Age band measured from the most recent receipt: 0-90, 91-180, 181-365, 366-730, over 730 days.';
COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.aging_bucket_first_receipt IS 'Alternative age band measured from the original receipt. Use only if the user asks about original or first receipt.';
COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.movement_status IS 'One of: Active, Slow Moving - 6m+, Non-Moving - 12m+, Dead Stock - Never Issued. Dead stock means received but never once consumed.';

COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.consuming_units IS 'Number of distinct production units (GREY, WHITE, PUTTY, SHARED) that have issued this item. Greater than one means the item is drawn by more than one unit, even though it is charged to a single primary unit.';
COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.consuming_unit_list IS 'The list of production units that have issued this item.';
COMMENT ON COLUMN maple_demo.gold.agg_stores_aging.shared_across_units IS 'True when consuming_units is greater than one. Use this, or "which items are shared across units", when the user asks about cross-unit consumption or misattributed spares - there is one stores location, so this replaces cross-plant redundancy analysis.';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Genie space instructions
-- MAGIC
-- MAGIC Create the space over `gold.agg_stores_aging`, `silver.dim_item` and
-- MAGIC `silver.dim_organization`. Paste the following into **Instructions**:
-- MAGIC
-- MAGIC ```
-- MAGIC This data covers stores and spares inventory at three Maple Leaf Cement plants.
-- MAGIC
-- MAGIC Vocabulary:
-- MAGIC - "plant", "site", "location", "unit" all mean org_code
-- MAGIC - "value", "worth", "amount" mean onhand_value_avg_cost unless the user
-- MAGIC   says last purchase price or replacement cost
-- MAGIC - "dead stock" means movement_status = 'Dead Stock - Never Issued'
-- MAGIC - "non-moving" means movement_status IN ('Non-Moving - 12m+', 'Dead Stock - Never Issued')
-- MAGIC - "age" means days_since_receipt unless the user says original receipt
-- MAGIC - "spares", "stock", "inventory", "items" all refer to rows in agg_stores_aging
-- MAGIC
-- MAGIC Conventions:
-- MAGIC - All amounts are Pakistani Rupees. Present large figures in millions.
-- MAGIC - Default to aging_bucket_last_receipt, not aging_bucket_first_receipt.
-- MAGIC - When asked about items across plants, group by item_number, not by row.
-- MAGIC - Sort results by value descending unless asked otherwise.
-- MAGIC
-- MAGIC This is synthetic demonstration data. Do not present figures as actual
-- MAGIC Maple Leaf financial results.
-- MAGIC ```

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Verified example queries
-- MAGIC
-- MAGIC Save each of these in the Genie space as a verified question-SQL pair.
-- MAGIC These are the ones to demo. Rehearse them the day before, on this data.

-- COMMAND ----------

-- Q: "What is the total value of stock that has never been issued?"
SELECT ROUND(SUM(onhand_value_avg_cost)/1e6, 1) AS dead_stock_value_pkr_mn,
       COUNT(*) AS item_lines
FROM maple_demo.gold.agg_stores_aging
WHERE movement_status = 'Dead Stock - Never Issued';

-- COMMAND ----------

-- Q: "Show stock value by plant and aging bucket"
SELECT org_code, aging_bucket_last_receipt,
       ROUND(SUM(onhand_value_avg_cost)/1e6, 1) AS value_pkr_mn
FROM maple_demo.gold.agg_stores_aging
GROUP BY org_code, aging_bucket_last_receipt
ORDER BY org_code, aging_bucket_last_receipt;

-- COMMAND ----------

-- Q: "Which items are shared across production units?"
SELECT item_number, item_description, category_name,
       ROUND(SUM(onhand_value_avg_cost)/1e6, 2) AS value_pkr_mn,
       ANY_VALUE(primary_unit_code)  AS primary_unit,
       ANY_VALUE(consuming_unit_list) AS consumed_by
FROM maple_demo.gold.agg_stores_aging
WHERE consuming_units > 1
GROUP BY item_number, item_description, category_name
HAVING array_contains(collect_set(movement_status), 'Dead Stock - Never Issued')
   AND array_contains(collect_set(movement_status), 'Active')
ORDER BY value_pkr_mn DESC
LIMIT 25;

-- COMMAND ----------

-- Q: "Which items have a last purchase price more than 20 percent above average cost?"
SELECT category_name, COUNT(*) AS items,
       ROUND(AVG(cost_variance_pct), 1) AS avg_variance_pct,
       ROUND(SUM(revaluation_exposure)/1e6, 1) AS exposure_pkr_mn
FROM maple_demo.gold.agg_stores_aging
WHERE cost_variance_pct > 20
GROUP BY category_name
ORDER BY exposure_pkr_mn DESC;

-- COMMAND ----------

-- Q: "Which category has the most capital tied up in non-moving stock?"
SELECT category_name,
       ROUND(SUM(onhand_value_avg_cost)/1e6, 1) AS value_pkr_mn,
       COUNT(*) AS item_lines
FROM maple_demo.gold.agg_stores_aging
WHERE movement_status IN ('Non-Moving - 12m+', 'Dead Stock - Never Issued')
GROUP BY category_name
ORDER BY value_pkr_mn DESC;