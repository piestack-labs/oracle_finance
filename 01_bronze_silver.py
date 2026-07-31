# Databricks notebook source
# MAGIC %md
# MAGIC # 01 — Bronze & Silver: Oracle EBS R12 Financials
# MAGIC
# MAGIC Lands the EBS extracts and builds the conformed silver layer.
# MAGIC The only thing that changes when you point this at the live instance is
# MAGIC `SOURCE_PATH` — swap the CSV volume for a JDBC read or GoldenGate target.

# COMMAND ----------

CATALOG = "oracle_finance"   # Free Edition: single metastore, this is fine
SOURCE_PATH = "/Volumes/oracle_finance/landing/ebs_extract"   # upload the CSVs here

spark.sql(f"CREATE CATALOG IF NOT EXISTS {CATALOG}")
for schema in ["bronze", "silver", "gold"]:
    spark.sql(f"CREATE SCHEMA IF NOT EXISTS {CATALOG}.{schema}")

# COMMAND ----------

# MAGIC %md ## Bronze — land as-is, no transformation

# COMMAND ----------

from pyspark.sql import functions as F

TABLES = [
    "hr_operating_units", "gl_ledgers", "gl_periods", "gl_code_combinations",
    "gl_je_headers", "gl_je_lines", "gl_import_references",
    "xla_ae_headers", "xla_distribution_links",
    "ap_suppliers", "ap_invoices_all", "ap_invoice_lines_all",
    "ap_invoice_distributions_all",
    "mtl_system_items_b", "mtl_material_transactions",
    "mtl_onhand_quantities_detail", "cst_item_costs", "org_security_map",
]

for t in TABLES:
    (spark.read
        .option("header", True)
        .option("inferSchema", True)
        .csv(f"{SOURCE_PATH}/{t}.csv")
        .withColumn("_ingest_ts", F.current_timestamp())
        .withColumn("_source_system", F.lit("EBS_R12"))
        .write.mode("overwrite")
        .saveAsTable(f"{CATALOG}.bronze.{t}"))
    print(f"bronze.{t}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Silver — the step that actually matters
# MAGIC
# MAGIC Flexfield segments become named columns. Every downstream query stops
# MAGIC carrying concatenated-segment string parsing, which is most of why the
# MAGIC current report is unreadable and slow.

# COMMAND ----------

spark.sql(f"""
CREATE OR REPLACE TABLE {CATALOG}.silver.dim_account AS
SELECT
    CODE_COMBINATION_ID          AS code_combination_id,
    SEGMENT1                     AS company_code,
    SEGMENT2                     AS cost_centre_code,
    COST_CENTRE_DESC             AS cost_centre_name,
    SEGMENT3                     AS natural_account,
    ACCOUNT_DESC                 AS account_name,
    CASE ACCOUNT_TYPE WHEN 'A' THEN 'Asset' WHEN 'L' THEN 'Liability'
                      WHEN 'E' THEN 'Expense' ELSE 'Other' END AS account_type,
    SEGMENT4                     AS plant_code,
    SEGMENT5                     AS intercompany_code,
    CONCATENATED_SEGMENTS        AS concatenated_segments
FROM {CATALOG}.bronze.gl_code_combinations
WHERE ENABLED_FLAG = 'Y'
""")

spark.sql(f"""
CREATE OR REPLACE TABLE {CATALOG}.silver.dim_organization AS
SELECT ORG_ID AS org_id, ORG_CODE AS org_code, ORG_NAME AS org_name,
       LEDGER_ID AS ledger_id, PLANT_SEGMENT AS plant_code, REGION AS region,
       CASE WHEN ORG_CODE LIKE 'W%' THEN 'White Cement'
            WHEN ORG_CODE LIKE 'G%' THEN 'Grey Cement'
            ELSE 'Corporate' END AS business_line
FROM {CATALOG}.bronze.hr_operating_units
""")

spark.sql(f"""
CREATE OR REPLACE TABLE {CATALOG}.silver.dim_item AS
SELECT i.INVENTORY_ITEM_ID AS inventory_item_id,
       i.ORGANIZATION_ID   AS org_id,
       i.SEGMENT1          AS item_number,
       i.DESCRIPTION       AS item_description,
       i.CATEGORY_CODE     AS category_code,
       i.CATEGORY_NAME     AS category_name,
       i.PRIMARY_UOM_CODE  AS uom,
       i.FULL_LEAD_TIME    AS lead_time_days,
       o.org_code, o.region, o.business_line
FROM {CATALOG}.bronze.mtl_system_items_b i
JOIN {CATALOG}.silver.dim_organization o ON o.org_id = i.ORGANIZATION_ID
""")

spark.sql(f"""
CREATE OR REPLACE TABLE {CATALOG}.silver.fact_material_txn
PARTITIONED BY (txn_year_month) AS
SELECT TRANSACTION_ID        AS transaction_id,
       INVENTORY_ITEM_ID     AS inventory_item_id,
       ORGANIZATION_ID       AS org_id,
       TRANSACTION_TYPE_ID   AS txn_type_id,
       TRANSACTION_TYPE_NAME AS txn_type_name,
       CAST(TRANSACTION_DATE AS DATE) AS txn_date,
       PRIMARY_QUANTITY      AS primary_quantity,
       ACTUAL_COST           AS actual_cost,
       TRANSACTION_COST_TOTAL AS txn_value,
       VENDOR_ID             AS vendor_id,
       PO_NUMBER             AS po_number,
       date_format(TRANSACTION_DATE, 'yyyy-MM') AS txn_year_month
FROM {CATALOG}.bronze.mtl_material_transactions
""")

spark.sql(f"""
CREATE OR REPLACE TABLE {CATALOG}.silver.fact_ap_distribution AS
SELECT d.INVOICE_DISTRIBUTION_ID AS invoice_distribution_id,
       d.INVOICE_ID              AS invoice_id,
       d.INVOICE_LINE_ID         AS invoice_line_id,
       d.ORG_ID                  AS org_id,
       d.AMOUNT                  AS amount,
       d.DIST_CODE_COMBINATION_ID AS code_combination_id,
       d.PERIOD_NAME             AS period_name,
       CAST(d.ACCOUNTING_DATE AS DATE) AS accounting_date,
       h.INVOICE_NUM             AS invoice_num,
       CAST(h.INVOICE_DATE AS DATE) AS invoice_date,
       CAST(h.DUE_DATE AS DATE)  AS due_date,
       h.PAYMENT_STATUS_PAID_FLAG AS paid_flag,
       s.VENDOR_NAME             AS vendor_name,
       s.TERMS_NAME              AS payment_terms
FROM {CATALOG}.bronze.ap_invoice_distributions_all d
JOIN {CATALOG}.bronze.ap_invoices_all h ON h.INVOICE_ID = d.INVOICE_ID
JOIN {CATALOG}.bronze.ap_suppliers   s ON s.VENDOR_ID  = h.VENDOR_ID
""")

spark.sql(f"""
CREATE OR REPLACE TABLE {CATALOG}.silver.fact_gl_line AS
SELECT l.JE_HEADER_ID  AS je_header_id,
       l.JE_LINE_NUM   AS je_line_num,
       l.CODE_COMBINATION_ID AS code_combination_id,
       l.LEDGER_ID     AS ledger_id,
       l.PERIOD_NAME   AS period_name,
       l.ACCOUNTED_DR  AS accounted_dr,
       l.ACCOUNTED_CR  AS accounted_cr,
       CAST(l.EFFECTIVE_DATE AS DATE) AS effective_date,
       h.JE_SOURCE     AS je_source,
       h.JE_CATEGORY   AS je_category,
       h.NAME          AS je_name
FROM {CATALOG}.bronze.gl_je_lines l
JOIN {CATALOG}.bronze.gl_je_headers h ON h.JE_HEADER_ID = l.JE_HEADER_ID
""")

# SLA bridge: sub-ledger distribution -> GL. This is the tie-out backbone.
spark.sql(f"""
CREATE OR REPLACE TABLE {CATALOG}.silver.bridge_sla_gl AS
SELECT dl.GL_SL_LINK_ID                AS gl_sl_link_id,
       dl.SOURCE_DISTRIBUTION_ID_NUM_1 AS invoice_distribution_id,
       dl.SOURCE_DISTRIBUTION_TYPE     AS source_type,
       dl.JE_HEADER_ID                 AS je_header_id,
       ah.AE_HEADER_ID                 AS ae_header_id,
       ah.APPLICATION_NAME             AS sub_ledger,
       ah.PERIOD_NAME                  AS period_name,
       CAST(ah.ACCOUNTING_DATE AS DATE) AS accounting_date
FROM {CATALOG}.bronze.xla_distribution_links dl
JOIN {CATALOG}.bronze.xla_ae_headers ah ON ah.AE_HEADER_ID = dl.AE_HEADER_ID
""")

print("silver layer complete")

# COMMAND ----------
