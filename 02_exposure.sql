-- ============================================================================
-- 02_exposure.sql  (BigQuery / MIMIC-IV v3.1)
-- Exposicion: uso de beta-bloqueador (Labetalol, Metoprolol, Esmolol) dentro
-- de las primeras 24h de UCI, igual que el paper. Se incluyen tanto
-- prescriptions (ordenes orales/IV en bolo) como inputevents (goteos IV,
-- comunes para esmolol/labetalol en UCI) para no subestimar la exposicion.
-- ============================================================================

CREATE OR REPLACE TABLE `akiproject-489303.sa_aki_study.exposure` AS

WITH bb_prescriptions AS (
    SELECT
        c.stay_id,
        LOWER(p.drug) AS drug_name,
        p.starttime
    FROM `akiproject-489303.sa_aki_study.cohort` c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON c.hadm_id = p.hadm_id
    WHERE p.starttime BETWEEN c.icu_intime AND DATETIME_ADD(c.icu_intime, INTERVAL 24 HOUR)
      AND (
            LOWER(p.drug) LIKE '%labetalol%'
         OR LOWER(p.drug) LIKE '%metoprolol%'
         OR LOWER(p.drug) LIKE '%esmolol%'
      )
),

bb_infusions AS (
    SELECT
        c.stay_id,
        LOWER(di.label) AS drug_name,
        ie.starttime
    FROM `akiproject-489303.sa_aki_study.cohort` c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
        ON c.stay_id = ie.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
        ON ie.itemid = di.itemid
    WHERE ie.starttime BETWEEN c.icu_intime AND DATETIME_ADD(c.icu_intime, INTERVAL 24 HOUR)
      AND (
            LOWER(di.label) LIKE '%labetalol%'
         OR LOWER(di.label) LIKE '%metoprolol%'
         OR LOWER(di.label) LIKE '%esmolol%'
      )
),

bb_all AS (
    SELECT stay_id, drug_name FROM bb_prescriptions
    UNION DISTINCT
    SELECT stay_id, drug_name FROM bb_infusions
)

SELECT
    c.stay_id,
    CASE WHEN ba.stay_id IS NOT NULL THEN 1 ELSE 0 END AS beta_blocker,
    MAX(CASE WHEN ba.drug_name LIKE '%labetalol%'  THEN 1 ELSE 0 END) AS bb_labetalol,
    MAX(CASE WHEN ba.drug_name LIKE '%metoprolol%' THEN 1 ELSE 0 END) AS bb_metoprolol,
    MAX(CASE WHEN ba.drug_name LIKE '%esmolol%'    THEN 1 ELSE 0 END) AS bb_esmolol
FROM `akiproject-489303.sa_aki_study.cohort` c
LEFT JOIN bb_all ba ON c.stay_id = ba.stay_id
GROUP BY c.stay_id, (CASE WHEN ba.stay_id IS NOT NULL THEN 1 ELSE 0 END);

-- Si un stay_id recibio mas de un tipo, quedara con dos+ columnas bb_* en 1
-- simultaneamente -> corresponde a la categoria "more than two types" de la
-- Tabla 3 del paper. Esto se resuelve en el script de Python (bb_type_analysis).
