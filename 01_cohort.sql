-- ============================================================================
-- 01_cohort.sql  (BigQuery / MIMIC-IV v3.1)
-- Reemplaza AKIPROJECT por tu project id (akiproject-489303) al correrlo,
-- o simplemente déjalo así si usas el mismo proyecto como destino.
-- ============================================================================

CREATE OR REPLACE TABLE `akiproject-489303.sa_aki_study.cohort_raw` AS

WITH sepsis_patients AS (
    -- Sepsis-3 (SOFA>=2 + sospecha de infección), ya calculado en mimiciv_derived
    SELECT
        s3.subject_id,
        s3.stay_id,
        s3.sofa_time,
        s3.sofa_score AS sofa_at_sepsis_onset
    FROM `physionet-data.mimiciv_3_1_derived.sepsis3` s3
    WHERE s3.sepsis3 = TRUE
),

first_stay AS (
    -- Primera admision a UCI, primera hospitalizacion, >=18 anios
    SELECT
        id.subject_id,
        id.hadm_id,
        id.stay_id,
        id.gender,
        id.admission_age,
        id.admittime,
        id.dischtime,
        id.icu_intime,
        id.icu_outtime,
        id.los_icu,
        id.hospital_expire_flag,
        id.dod,
        id.race
    FROM `physionet-data.mimiciv_3_1_derived.icustay_detail` id
    WHERE id.first_icu_stay = TRUE
      AND id.first_hosp_stay = TRUE
      AND id.admission_age >= 18
),

baseline_creat AS (
    -- Creatinina basal: primer valor dentro de las primeras 24h de UCI
    SELECT
        fs.stay_id,
        ARRAY_AGG(le.valuenum ORDER BY le.charttime ASC LIMIT 1)[OFFSET(0)] AS baseline_creat
    FROM first_stay fs
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON fs.subject_id = le.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    WHERE LOWER(dli.label) = 'creatinine'
      AND le.charttime BETWEEN fs.icu_intime AND DATETIME_ADD(fs.icu_intime, INTERVAL 24 HOUR)
      AND le.valuenum IS NOT NULL
      AND le.valuenum > 0
    GROUP BY fs.stay_id
),

egfr_baseline AS (
    -- CKD-EPI 2021 (sin coeficiente de raza)
    SELECT
        fs.stay_id,
        bc.baseline_creat,
        CASE
            WHEN fs.gender = 'F' THEN
                142 * POW(LEAST(bc.baseline_creat / 0.7, 1), -0.241)
                    * POW(GREATEST(bc.baseline_creat / 0.7, 1), -1.200)
                    * POW(0.9938, fs.admission_age) * 1.012
            ELSE
                142 * POW(LEAST(bc.baseline_creat / 0.9, 1), -0.302)
                    * POW(GREATEST(bc.baseline_creat / 0.9, 1), -1.200)
                    * POW(0.9938, fs.admission_age)
        END AS egfr_baseline
    FROM first_stay fs
    INNER JOIN baseline_creat bc ON fs.stay_id = bc.stay_id
),

rrt_baseline AS (
    SELECT DISTINCT fs.stay_id
    FROM first_stay fs
    INNER JOIN `physionet-data.mimiciv_3_1_derived.rrt` r ON fs.stay_id = r.stay_id
    WHERE r.dialysis_active = 1
      AND r.charttime BETWEEN fs.icu_intime AND DATETIME_ADD(fs.icu_intime, INTERVAL 24 HOUR)
),

aki_baseline AS (
    -- AKI (cualquier estadio KDIGO) ya presente en las primeras 24h -> se excluye
    SELECT DISTINCT fs.stay_id
    FROM first_stay fs
    INNER JOIN `physionet-data.mimiciv_3_1_derived.kdigo_stages` k ON fs.stay_id = k.stay_id
    WHERE k.charttime BETWEEN fs.icu_intime AND DATETIME_ADD(fs.icu_intime, INTERVAL 24 HOUR)
      AND k.aki_stage >= 1
),

death_24h AS (
    SELECT fs.stay_id
    FROM first_stay fs
    WHERE fs.dod IS NOT NULL
      AND fs.dod BETWEEN fs.icu_intime AND DATETIME_ADD(fs.icu_intime, INTERVAL 24 HOUR)
),

aki_measurable AS (
    -- Criterio (7) del paper: "without measurement for diagnosis of AKI".
    -- Si no hay NINGUN registro de KDIGO (creatinina o diuresis) despues de
    -- la hora 24, no se puede saber si el paciente tuvo o no AKI -> se excluye
    -- en vez de asumir por defecto que no tuvo (eso seria confundir
    -- "sin dato" con "sin evento", un sesgo de mala clasificacion del outcome).
    SELECT DISTINCT fs.stay_id
    FROM first_stay fs
    INNER JOIN `physionet-data.mimiciv_3_1_derived.kdigo_stages` k
        ON fs.stay_id = k.stay_id
    WHERE k.charttime > DATETIME_ADD(fs.icu_intime, INTERVAL 24 HOUR)
      AND k.charttime <= fs.icu_outtime
)

SELECT
    fs.subject_id,
    fs.hadm_id,
    fs.stay_id,
    fs.gender,
    fs.admission_age,
    fs.race,
    fs.icu_intime,
    fs.icu_outtime,
    fs.los_icu,
    fs.hospital_expire_flag,
    sp.sofa_at_sepsis_onset,
    eb.baseline_creat,
    eb.egfr_baseline,
    (DATETIME_DIFF(fs.icu_outtime, fs.icu_intime, HOUR) < 24) AS excl_icu_lt_24h,
    (eb.baseline_creat IS NULL)                               AS excl_missing_creat,
    (eb.egfr_baseline < 15)                                   AS excl_egfr_lt_15,
    (rb.stay_id IS NOT NULL)                                  AS excl_rrt_baseline,
    (ab.stay_id IS NOT NULL)                                  AS excl_aki_baseline,
    (d24.stay_id IS NOT NULL)                                 AS excl_death_24h,
    (am.stay_id IS NULL)                                      AS excl_no_aki_measurement
FROM sepsis_patients sp
INNER JOIN first_stay fs ON sp.stay_id = fs.stay_id
LEFT JOIN egfr_baseline eb ON fs.stay_id = eb.stay_id
LEFT JOIN rrt_baseline rb  ON fs.stay_id = rb.stay_id
LEFT JOIN aki_baseline ab  ON fs.stay_id = ab.stay_id
LEFT JOIN death_24h d24    ON fs.stay_id = d24.stay_id
LEFT JOIN aki_measurable am ON fs.stay_id = am.stay_id;

-- Cohorte final (equivalente al N=4419 del paper, pero para tu exposicion)
CREATE OR REPLACE TABLE `akiproject-489303.sa_aki_study.cohort` AS
SELECT * EXCEPT(excl_icu_lt_24h, excl_missing_creat, excl_egfr_lt_15,
                 excl_rrt_baseline, excl_aki_baseline, excl_death_24h,
                 excl_no_aki_measurement)
FROM `akiproject-489303.sa_aki_study.cohort_raw`
WHERE NOT excl_icu_lt_24h
  AND NOT excl_missing_creat
  AND NOT excl_egfr_lt_15
  AND NOT excl_rrt_baseline
  AND NOT excl_aki_baseline
  AND NOT excl_death_24h
  AND NOT excl_no_aki_measurement;

-- Embudo de seleccion, para comparar contra la Fig 1 del paper original
SELECT
    COUNT(*) AS n_sepsis3_first_stay,
    COUNTIF(excl_icu_lt_24h)         AS excl_icu_lt_24h,
    COUNTIF(excl_missing_creat)      AS excl_missing_creat,
    COUNTIF(excl_egfr_lt_15)         AS excl_egfr_lt_15,
    COUNTIF(excl_rrt_baseline)       AS excl_rrt_baseline,
    COUNTIF(excl_aki_baseline)       AS excl_aki_baseline,
    COUNTIF(excl_death_24h)          AS excl_death_24h,
    COUNTIF(excl_no_aki_measurement) AS excl_no_aki_measurement
FROM `akiproject-489303.sa_aki_study.cohort_raw`;
