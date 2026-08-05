-- ============================================================================
-- 05_build_analysis_table.sql  (BigQuery / MIMIC-IV v3.1)
-- Une cohorte + exposicion + outcome + covariables. Esta tabla es la que
-- luego lees desde Python via BigQuery client / pandas-gbq.
-- ============================================================================

CREATE OR REPLACE TABLE `akiproject-489303.sa_aki_study.analysis_table` AS
SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.gender,
    c.admission_age AS age,
    c.race,
    c.icu_intime,
    c.icu_outtime,
    c.los_icu,
    e.beta_blocker,
    e.bb_labetalol,
    e.bb_metoprolol,
    e.bb_esmolol,
    o.aki,
    o.first_aki_time,
    o.max_aki_stage,
    o.hours_to_event,
    cov.* EXCEPT(stay_id)
FROM `akiproject-489303.sa_aki_study.cohort` c
INNER JOIN `akiproject-489303.sa_aki_study.exposure`   e   ON c.stay_id = e.stay_id
INNER JOIN `akiproject-489303.sa_aki_study.outcome`    o   ON c.stay_id = o.stay_id
INNER JOIN `akiproject-489303.sa_aki_study.covariates` cov ON c.stay_id = cov.stay_id;

SELECT COUNT(*) AS n_final, SUM(aki) AS n_aki, SUM(beta_blocker) AS n_beta_blocker
FROM `akiproject-489303.sa_aki_study.analysis_table`;
