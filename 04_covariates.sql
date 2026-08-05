-- ============================================================================
-- 04_covariates.sql  (BigQuery / MIMIC-IV v3.1)
-- Confusores basales (primeras 24h de UCI), Tabla 1 del paper.
-- NOTA: se usa el valor MINIMO del primer dia (first_day_lab / first_day_vitalsign)
-- como proxy del "primer registro" que describe el paper (aproximacion razonable,
-- no identica). Avisame si prefieres el valor estrictamente mas temprano.
-- ============================================================================

CREATE OR REPLACE TABLE `akiproject-489303.sa_aki_study.covariates` AS

WITH comorbid_dx AS (
    -- Hipertension no esta en Charlson -> se toma de diagnoses_icd
    SELECT
        c.stay_id,
        MAX(CASE WHEN REGEXP_CONTAINS(d.icd_code, r'^(401|402|403|404|405)')
                   OR REGEXP_CONTAINS(d.icd_code, r'^I1[0-5]')
                  THEN 1 ELSE 0 END) AS hypertension
    FROM `akiproject-489303.sa_aki_study.cohort` c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON c.hadm_id = d.hadm_id
    GROUP BY c.stay_id
),

cabg_flag AS (
    SELECT DISTINCT c.stay_id, 1 AS cabg
    FROM `akiproject-489303.sa_aki_study.cohort` c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p ON c.hadm_id = p.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
        ON p.icd_code = dip.icd_code AND p.icd_version = dip.icd_version
    WHERE LOWER(dip.long_title) LIKE '%coronary artery bypass%'
),

vasopressor_flag AS (
    SELECT DISTINCT c.stay_id, 1 AS vasopressor
    FROM `akiproject-489303.sa_aki_study.cohort` c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie ON c.stay_id = ie.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ie.itemid = di.itemid
    WHERE ie.starttime BETWEEN c.icu_intime AND DATETIME_ADD(c.icu_intime, INTERVAL 24 HOUR)
      AND (LOWER(di.label) LIKE '%norepinephrine%'
        OR LOWER(di.label) LIKE '%epinephrine%'
        OR LOWER(di.label) LIKE '%dopamine%'
        OR LOWER(di.label) LIKE '%phenylephrine%'
        OR LOWER(di.label) LIKE '%vasopressin%')
),

ventilation_flag AS (
    SELECT DISTINCT c.stay_id, 1 AS ventilation
    FROM `akiproject-489303.sa_aki_study.cohort` c
    INNER JOIN `physionet-data.mimiciv_3_1_derived.ventilation` v ON c.stay_id = v.stay_id
    WHERE v.ventilation_status = 'InvasiveVent'
      AND v.starttime <= DATETIME_ADD(c.icu_intime, INTERVAL 24 HOUR)
),

loop_diuretics_flag AS (
    SELECT DISTINCT c.stay_id, 1 AS loop_diuretics
    FROM `akiproject-489303.sa_aki_study.cohort` c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON c.hadm_id = p.hadm_id
    WHERE p.starttime BETWEEN c.icu_intime AND DATETIME_ADD(c.icu_intime, INTERVAL 24 HOUR)
      AND (LOWER(p.drug) LIKE '%furosemide%'
        OR LOWER(p.drug) LIKE '%bumetanide%'
        OR LOWER(p.drug) LIKE '%torsemide%'
        OR LOWER(p.drug) LIKE '%ethacrynic%')
),

nephrotoxic_abx_flag AS (
    SELECT DISTINCT c.stay_id, 1 AS nephrotoxic_antibiotics
    FROM `akiproject-489303.sa_aki_study.cohort` c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON c.hadm_id = p.hadm_id
    WHERE p.starttime BETWEEN c.icu_intime AND DATETIME_ADD(c.icu_intime, INTERVAL 24 HOUR)
      AND (LOWER(p.drug) LIKE '%vancomycin%'
        OR LOWER(p.drug) LIKE '%gentamicin%'
        OR LOWER(p.drug) LIKE '%tobramycin%'
        OR LOWER(p.drug) LIKE '%amikacin%')
),

insulin_flag AS (
    SELECT DISTINCT c.stay_id, 1 AS insulin
    FROM `akiproject-489303.sa_aki_study.cohort` c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON c.hadm_id = p.hadm_id
    WHERE p.starttime BETWEEN c.icu_intime AND DATETIME_ADD(c.icu_intime, INTERVAL 24 HOUR)
      AND LOWER(p.drug) LIKE '%insulin%'
),

platelet_infusion_flag AS (
    SELECT DISTINCT c.stay_id, 1 AS platelet_infusion
    FROM `akiproject-489303.sa_aki_study.cohort` c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie ON c.stay_id = ie.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ie.itemid = di.itemid
    WHERE ie.starttime BETWEEN c.icu_intime AND DATETIME_ADD(c.icu_intime, INTERVAL 24 HOUR)
      AND LOWER(di.label) LIKE '%platelet%'
),

rdw_first_day AS (
    -- RDW no esta en first_day_lab (ese concepto solo agrega
    -- chemistry+coagulation+CBC "basico"); se saca directo de
    -- complete_blood_count, que tiene granularidad por muestra.
    SELECT
        c.stay_id,
        MIN(cbc.rdw) AS rdw_min
    FROM `akiproject-489303.sa_aki_study.cohort` c
    INNER JOIN `physionet-data.mimiciv_3_1_derived.complete_blood_count` cbc
        ON c.subject_id = cbc.subject_id
    WHERE cbc.charttime BETWEEN c.icu_intime AND DATETIME_ADD(c.icu_intime, INTERVAL 24 HOUR)
      AND cbc.rdw IS NOT NULL
    GROUP BY c.stay_id
)

SELECT
    c.stay_id,
    w.weight_admit AS weight,
    ch.congestive_heart_failure AS heart_failure,
    ch.myocardial_infarct        AS ami,
    ch.renal_disease             AS ckd,
    CAST(ch.diabetes_without_cc + ch.diabetes_with_cc > 0 AS INT64) AS diabetes,
    cd.hypertension,
    sofa.sofa,
    saps.sapsii,
    ch.charlson_comorbidity_index AS cci,
    vit.heart_rate_min  AS heart_rate,
    vit.sbp_min         AS systolic,
    vit.dbp_min         AS diastolic,
    vit.resp_rate_min   AS respiratory_rate,
    vit.temperature_min AS temperature,
    vit.spo2_min        AS spo2,
    lab.creatinine_min  AS creatinine,
    lab.bun_min         AS bun,
    lab.platelets_min   AS platelet,
    lab.wbc_min         AS wbc,
    rdw.rdw_min          AS rdw,
    lab.hemoglobin_min  AS hemoglobin,
    lab.hematocrit_min  AS hematocrit,
    lab.glucose_min     AS glucose,
    lab.calcium_min     AS calcium,
    lab.bicarbonate_min AS bicarbonate,
    lab.sodium_min      AS sodium,
    lab.potassium_min   AS potassium,
    lab.chloride_min    AS chloride,
    lab.inr_min         AS inr,
    lab.pt_min          AS pt,
    lab.ptt_min         AS ptt,
    uo.urineoutput       AS urine_output_24h,
    COALESCE(vf.ventilation, 0)             AS ventilation,
    COALESCE(vaso.vasopressor, 0)           AS vasopressor,
    COALESCE(ld.loop_diuretics, 0)          AS loop_diuretics,
    COALESCE(na.nephrotoxic_antibiotics, 0) AS nephrotoxic_antibiotics,
    COALESCE(cb.cabg, 0)                    AS cabg,
    COALESCE(ins.insulin, 0)                AS insulin,
    COALESCE(pi.platelet_infusion, 0)       AS platelet_infusion,
    c.egfr_baseline AS egfr
FROM `akiproject-489303.sa_aki_study.cohort` c
LEFT JOIN `physionet-data.mimiciv_3_1_derived.first_day_weight` w   ON c.stay_id = w.stay_id
LEFT JOIN `physionet-data.mimiciv_3_1_derived.charlson` ch          ON c.hadm_id = ch.hadm_id
LEFT JOIN comorbid_dx cd                                            ON c.stay_id = cd.stay_id
LEFT JOIN `physionet-data.mimiciv_3_1_derived.first_day_sofa` sofa  ON c.stay_id = sofa.stay_id
LEFT JOIN `physionet-data.mimiciv_3_1_derived.sapsii` saps          ON c.stay_id = saps.stay_id
LEFT JOIN `physionet-data.mimiciv_3_1_derived.first_day_vitalsign` vit ON c.stay_id = vit.stay_id
LEFT JOIN `physionet-data.mimiciv_3_1_derived.first_day_lab` lab    ON c.stay_id = lab.stay_id
LEFT JOIN rdw_first_day rdw                                         ON c.stay_id = rdw.stay_id
LEFT JOIN `physionet-data.mimiciv_3_1_derived.first_day_urine_output` uo ON c.stay_id = uo.stay_id
LEFT JOIN ventilation_flag vf       ON c.stay_id = vf.stay_id
LEFT JOIN vasopressor_flag vaso     ON c.stay_id = vaso.stay_id
LEFT JOIN loop_diuretics_flag ld    ON c.stay_id = ld.stay_id
LEFT JOIN nephrotoxic_abx_flag na   ON c.stay_id = na.stay_id
LEFT JOIN cabg_flag cb              ON c.stay_id = cb.stay_id
LEFT JOIN insulin_flag ins          ON c.stay_id = ins.stay_id
LEFT JOIN platelet_infusion_flag pi ON c.stay_id = pi.stay_id;
