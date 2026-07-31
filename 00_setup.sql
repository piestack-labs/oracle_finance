-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 00 — Free Edition Setup
-- MAGIC
-- MAGIC Run this first, once. Creates the catalog, schemas and the volume you
-- MAGIC will upload the CSVs into.
-- MAGIC
-- MAGIC **Free Edition notes**
-- MAGIC - Serverless compute only. Attach any notebook to Serverless.
-- MAGIC - One SQL warehouse at 2X-Small. Ample for 44 MB.
-- MAGIC - Compute shuts down for the day if you exceed quota — stop the
-- MAGIC   warehouse when you are not using it.

-- COMMAND ----------

CREATE CATALOG IF NOT EXISTS oracle_finance;

-- COMMAND ----------

CREATE SCHEMA IF NOT EXISTS oracle_finance.landing;
CREATE SCHEMA IF NOT EXISTS oracle_finance.bronze;
CREATE SCHEMA IF NOT EXISTS oracle_finance.silver;
CREATE SCHEMA IF NOT EXISTS oracle_finance.gold;

-- COMMAND ----------

CREATE VOLUME IF NOT EXISTS oracle_finance.landing.ebs_extract;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Now upload the CSVs
-- MAGIC
-- MAGIC Catalog → oracle_finance → landing → ebs_extract → **Upload to this volume**
-- MAGIC
-- MAGIC Unzip `maple_ebs_demo_data.zip` locally first and upload all 18 files.
-- MAGIC The largest is `mtl_material_transactions.csv` (~28 MB). If the browser
-- MAGIC upload stalls, upload in batches of five.
-- MAGIC
-- MAGIC Then run the cell below to confirm all 18 landed.

-- COMMAND ----------

LIST '/Volumes/oracle_finance/landing/ebs_extract';

-- COMMAND ----------

-- MAGIC %md Expected: 18 files. If any are missing, re-upload before running notebook 01.
