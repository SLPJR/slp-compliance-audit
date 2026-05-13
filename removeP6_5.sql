-- removeP6_5.sql
-- Removes question P6.5 from all historical audit data and recalculates totals.
-- Run in Supabase SQL Editor. Single atomic transaction.

WITH
-- Step 1: Zero out all audit_answers rows for P6.5
zeroed AS (
  UPDATE audit_answers
  SET    weight     = 0,
         points     = 0,
         max_points = 0
  WHERE  item_id = 'P6.5'
  RETURNING audit_id
),

-- Step 2: Get penalty_pct from app_settings
penalty AS (
  SELECT COALESCE((value::jsonb)::numeric, 0) AS pct
  FROM   app_settings
  WHERE  key = 'penalty_pct'
  LIMIT  1
),

-- Step 3: Recalculate totals for every audit that had a P6.5 answer
totals AS (
  SELECT
    aa.audit_id,
    SUM(aa.points)     AS total_achieved,
    SUM(aa.max_points) AS total_max
  FROM audit_answers aa
  WHERE aa.audit_id IN (SELECT DISTINCT audit_id FROM zeroed)
  GROUP BY aa.audit_id
),

-- Step 4: Update the audits summary rows
audit_update AS (
  UPDATE audits a
  SET
    total_achieved = t.total_achieved,
    total_max      = t.total_max,
    total_pct      = CASE
                       WHEN t.total_max = 0 THEN 0
                       ELSE ROUND(
                         (t.total_achieved::numeric / t.total_max * 100)
                         * (1 - COALESCE((SELECT pct FROM penalty), 0) / 100),
                         1
                       )
                     END
  FROM totals t
  WHERE a.id = t.audit_id
  RETURNING a.id
)

-- Summary
SELECT
  (SELECT COUNT(*) FROM zeroed)       AS answers_zeroed,
  (SELECT COUNT(*) FROM audit_update) AS audits_recalculated;
