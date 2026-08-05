-- ============================================================================
-- 03_outcome.sql  (BigQuery / MIMIC-IV v3.1)
-- Outcome: AKI (KDIGO, cualquier estadio >=1) entre la hora 24 de UCI y el
-- alta de UCI (o el evento, lo que ocurra primero).
-- ============================================================================

CREATE OR REPLACE TABLE `akiproject-489303.sa_aki_study.outcome` AS

WITH aki_events AS (
    SELECT
        c.stay_id,
        MIN(k.charttime) AS first_aki_time,
        MAX(k.aki_stage)  AS max_aki_stage
    FROM `akiproject-489303.sa_aki_study.cohort` c
    INNER JOIN `physionet-data.mimiciv_3_1_derived.kdigo_stages` k
        ON c.stay_id = k.stay_id
    WHERE k.charttime > DATETIME_ADD(c.icu_intime, INTERVAL 24 HOUR)
      AND k.charttime <= c.icu_outtime
      AND k.aki_stage >= 1
    GROUP BY c.stay_id
)

SELECT
    c.stay_id,
    CASE WHEN ae.stay_id IS NOT NULL THEN 1 ELSE 0 END AS aki,
    ae.first_aki_time,
    ae.max_aki_stage,
    DATETIME_DIFF(
        COALESCE(ae.first_aki_time, c.icu_outtime),
        DATETIME_ADD(c.icu_intime, INTERVAL 24 HOUR),
        HOUR
    ) AS hours_to_event
FROM `akiproject-489303.sa_aki_study.cohort` c
LEFT JOIN aki_events ae ON c.stay_id = ae.stay_id;
