# Replicación: Beta-bloqueadores y AKI asociado a sepsis (MIMIC-IV)

Replica el estudio de Wang, Hu & Song (2025), *PLoS ONE* —
["Association between the early use of beta-blocker and the risk of
sepsis-associated acute kidney injury"](https://doi.org/10.1371/journal.pone.0325980) —
usando MIMIC-IV v3.1 en BigQuery, siguiendo la estructura de pipeline del
tutorial [`mimic-iv-aline-study`](https://github.com/alistairewj/mimic-iv-aline-study).

# Proceso de Inferencia causal basado en el marco de Rubin
## 1. Pregunta causal

**¿El uso temprano (primeras 24h de UCI) de beta-bloqueadores reduce el riesgo
de AKI en pacientes sépticos, comparado con no usarlos?**

No es un experimento aleatorizado: quién recibe beta-bloqueador depende de
decisiones clínicas correlacionadas con la gravedad y comorbilidades del
paciente (confusión por indicación). El diseño (ventana de exposición fija +
propensity score matching + regresión ajustada) busca aislar el efecto del
fármaco de esos factores.

## Requisitos

- Acceso aprobado a MIMIC-IV en PhysioNet, vinculado a BigQuery
  (`physionet-data.mimiciv_3_1_hosp/icu/derived`)
- Un proyecto de Google Cloud propio para cómputo/almacenamiento (aquí:
  `akiproject-489303`) con un dataset de trabajo:
  ```bash
  bq mk --location=US akiproject-489303:sa_aki_study
  ```
- Autenticación local: `gcloud auth application-default login`
- Python: `pandas`, `numpy`, `scipy`, `statsmodels`, `scikit-learn`,
  `google-cloud-bigquery`, `db-dtypes`

## Estructura

```
bigquery/
  01_cohort.sql                 -- población + exclusiones (Fig 1 del paper)
  02_exposure.sql               -- beta-bloqueador en primeras 24h
  03_outcome.sql                -- AKI (KDIGO) después de la hora 24
  04_covariates.sql             -- confusores basales (Tabla 1 del paper)
  05_build_analysis_table.sql   -- tabla final de análisis
python/
  01_analysis.py                -- imputación, PSM, regresión, subgrupos
sql/                            -- versiones equivalentes en PostgreSQL
                                     (por si en algún momento vuelves a Postgres)
```

## Cómo correrlo

1. En BigQuery (consola o `bq query --use_legacy_sql=false < archivo.sql`),
   ejecuta en orden `01` → `05`.
2. Revisa el embudo de selección al final de `01_cohort.sql` y compáralo
   contra la Fig 1 del paper (N=12,014 → N=4,419 en el original; tu N variará
   un poco porque MIMIC-IV v3.1 tiene más datos que la versión usada en 2025
   y porque algunas definiciones —p.ej. nefrotóxicos, CABG— son aproximaciones).
3. Corre `python/01_analysis.py`.

## Mapeo pipeline → razonamiento causal

| Script | Qué hace | Por qué importa para causalidad |
|---|---|---|
| `01_cohort.sql` | Define población, excluye AKI/RRT basal, eGFR<15, muerte en 24h | Evita causalidad inversa e *immortal time bias* |
| `02_exposure.sql` | Beta-bloqueador en horas 0–24 | Fija el "antes" de la secuencia temporal exposición→desenlace |
| `03_outcome.sql` | AKI KDIGO estrictamente después de la hora 24 | Fija el "después"; sin esto, el diseño sería transversal, no causal |
| `04_covariates.sql` | Variables basales candidatas a confusor | Solo confusores (afectan exposición Y desenlace), no mediadores |
| `05_build_analysis_table.sql` | Ensambla la tabla final | Insumo para el propensity score |
| `01_analysis.py` | PSM 1:1 (caliper 0.018) + SMD + regresión logística (cruda y ajustada) + subgrupos | Ajuste por confusión *medible*; SMD<0.1 confirma balance logrado |

## Limitaciones (heredadas del paper original, aplican igual aquí)

- Es un estudio observacional: PSM ajusta por confusores medidos, no por
  confusión no medida (ej. decisiones clínicas no registradas en texto libre).
- Los resultados del paper solo fueron significativos después de PSM, lo
  cual el propio artículo discute como posible desenmascaramiento del efecto
  al balancear grupos — pero también es una señal de que el resultado es
  sensible a la especificación del modelo. Vale la pena que hagas la misma
  comparación (antes/después de PSM) para ver si tu replicación muestra el
  mismo patrón.
- Ninguna versión de este análisis establece causalidad de forma definitiva;
  en el mejor de los casos, es evidencia observacional consistente con una
  hipótesis causal.

## Fuente

Wang C, Hu Y, Song Y (2025). *PLoS One* 20(6): e0325980.
https://doi.org/10.1371/journal.pone.0325980
