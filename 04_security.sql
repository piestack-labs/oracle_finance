-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 03b — Production-Unit Security (Free Edition substitute)
-- MAGIC
-- MAGIC In production this is a Unity Catalog **row filter** driven by account
-- MAGIC group membership, so a user cannot bypass it. Free Edition has no access
-- MAGIC to the account console and no SCIM, so account groups cannot be created
-- MAGIC and `is_account_group_member()` has nothing to resolve against.
-- MAGIC
-- MAGIC The view below reproduces the *effect* for the demo, not real enforced
-- MAGIC security. Say this out loud when you show it — if a technical person is
-- MAGIC in the room and you imply this is enforced, you lose credibility you
-- MAGIC will need later.
-- MAGIC
-- MAGIC Maple Leaf has one plant with three production units sharing one
-- MAGIC stores location, so the security boundary here is `primary_unit_code`
-- MAGIC (GREY / WHITE / PUTTY), not a plant or site.
-- MAGIC
-- MAGIC No `CREATE WIDGET` — that syntax only works inside a Databricks
-- MAGIC **notebook** cell, not the SQL editor connected to a SQL warehouse.
-- MAGIC Change the value in the `persona` CTE below and rerun instead; it
-- MAGIC works in either place.

-- COMMAND ----------

USE CATALOG maple_demo;

-- COMMAND ----------

CREATE OR REPLACE VIEW gold.vw_stores_aging_secured AS
WITH persona AS (
    SELECT 'BOARD' AS value   -- change to 'GREY', 'WHITE', or 'PUTTY' and rerun
)
SELECT a.*
FROM gold.agg_stores_aging a
CROSS JOIN persona p
WHERE CASE
    WHEN p.value = 'BOARD' THEN TRUE
    WHEN p.value = 'GREY'  THEN a.primary_unit_code = 'GREY'
    WHEN p.value = 'WHITE' THEN a.primary_unit_code = 'WHITE'
    WHEN p.value = 'PUTTY' THEN a.primary_unit_code = 'PUTTY'
    ELSE FALSE
END;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Change the value above and rerun both cells to switch who you're
-- MAGIC "logged in as". BOARD sees everything; a unit persona sees only its
-- MAGIC own rows. Same query, same dashboard, only this one value changes —
-- MAGIC that is the point being made.

-- COMMAND ----------

SELECT COUNT(DISTINCT primary_unit_code)        AS units_visible,
       COUNT(*)                                 AS rows_visible,
       ROUND(SUM(onhand_value_avg_cost)/1e6, 1) AS value_visible_pkr_mn
FROM gold.vw_stores_aging_secured;