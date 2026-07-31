-- ============================================================
-- Operating-unit security — Free Edition substitute
--
-- In production this is a Unity Catalog row filter driven by account
-- group membership, so a user cannot bypass it. Free Edition has no
-- access to the account console and no SCIM, so account groups cannot
-- be created and is_account_group_member() has nothing to resolve
-- against.
--
-- The view below reproduces the EFFECT for the demo, not real enforced
-- security. Say this out loud when you show it.
-- ============================================================
USE CATALOG oracle_finance;
CREATE OR REPLACE VIEW gold.vw_stores_aging_secured AS
WITH persona AS (
    SELECT 'BOARD' AS value   -- change to 'GCI', 'WCI', or 'GCM' and rerun
)
SELECT a.*
FROM gold.agg_stores_aging a
CROSS JOIN persona p
WHERE CASE
    WHEN p.value = 'BOARD' THEN TRUE
    WHEN p.value = 'GCI'   THEN a.org_code = 'GCI'   -- Grey, Iskanderabad
    WHEN p.value = 'WCI'   THEN a.org_code = 'WCI'   -- White, Iskanderabad
    WHEN p.value = 'GCM'   THEN a.org_code = 'GCM'   -- Grey, Mianwali
    ELSE FALSE
END;

-- Check what's visible under the current persona
SELECT COUNT(DISTINCT org_code)                 AS orgs_visible,
       COUNT(*)                                 AS rows_visible,
       ROUND(SUM(onhand_value_avg_cost)/1e6, 1) AS value_visible_pkr_mn
FROM gold.vw_stores_aging_secured;