/*
    REPORTING VIEWS

    The anchor model records task runs, lineage and row counts, and the generated
    perspectives expose them attribute by attribute. These views answer the questions the
    model exists for, in the vocabulary of the domain rather than of the model.

    Nothing here stores data; they are views over the generated perspectives.
*/

-- ============================================================
-- TASK RUNS
-- ============================================================
-- One row per task execution. A run with no STATUS is still running or died without being
-- able to report; DURATION_SECONDS is null for the same reason.

CREATE OR REPLACE VIEW metadata.TaskRuns AS
SELECT
    tr.TR_ID                                   AS TASK_RUN_ID,
    tr.TR_NAM_TKN_TaskName                     AS TASK_NAME,
    tr.TR_GRG_GRG_GraphRunGroupId              AS GRAPH_RUN_ID,
    cf.CF_NAM_Configuration_Name               AS WORKFLOW,
    tr.TR_BEG_TaskRun_StartedAt                AS STARTED_AT,
    tr.TR_FIN_TaskRun_FinishedAt               AS FINISHED_AT,
    tr.TR_STA_TRS_TaskRunStatus                AS STATUS,
    DATEDIFF('millisecond', tr.TR_BEG_TaskRun_StartedAt, tr.TR_FIN_TaskRun_FinishedAt) / 1000.0
                                               AS DURATION_SECONDS,
    tr.TR_ERR_TaskRun_Error                    AS ERROR
FROM metadata.lTR_TaskRun tr
LEFT JOIN metadata.TR_formed_CF_from f ON f.TR_ID_formed = tr.TR_ID
LEFT JOIN metadata.lCF_Configuration cf ON cf.CF_ID = f.CF_ID_from;

COMMENT ON VIEW metadata.TaskRuns IS
    'One row per task execution, with outcome and duration. No status means still running or died without reporting.';

-- ============================================================
-- GRAPH RUNS
-- ============================================================
-- One row per execution of a whole task graph, rolled up from its task runs. This is the
-- "did last night work?" view.

CREATE OR REPLACE VIEW metadata.GraphRuns AS
SELECT
    GRAPH_RUN_ID,
    MAX(WORKFLOW)                                              AS WORKFLOW,
    MIN(STARTED_AT)                                            AS STARTED_AT,
    MAX(FINISHED_AT)                                           AS FINISHED_AT,
    DATEDIFF('millisecond', MIN(STARTED_AT), MAX(FINISHED_AT)) / 1000.0 AS DURATION_SECONDS,
    COUNT(*)                                                   AS TASKS,
    COUNT_IF(STATUS = 'Succeeded')                             AS SUCCEEDED,
    COUNT_IF(STATUS = 'Failed')                                AS FAILED,
    COUNT_IF(STATUS IS NULL)                                   AS UNFINISHED,
    CASE
        WHEN COUNT_IF(STATUS = 'Failed') > 0 THEN 'Failed'
        WHEN COUNT_IF(STATUS IS NULL) > 0    THEN 'Running'
        ELSE 'Succeeded'
    END                                                        AS STATUS
FROM metadata.TaskRuns
GROUP BY GRAPH_RUN_ID;

COMMENT ON VIEW metadata.GraphRuns IS
    'One row per task graph execution, rolled up from its task runs.';

-- ============================================================
-- LINEAGE
-- ============================================================
-- Which containers a task read from and wrote to, with the row counts it reported. The
-- model has carried this since the beginning without anything surfacing it.

CREATE OR REPLACE VIEW metadata.Lineage AS
SELECT
    tr.TR_ID                            AS TASK_RUN_ID,
    tr.TR_NAM_TKN_TaskName              AS TASK_NAME,
    tr.TR_GRG_GRG_GraphRunGroupId       AS GRAPH_RUN_ID,
    tr.TR_BEG_TaskRun_StartedAt         AS STARTED_AT,
    src.CO_NAM_Container_Name           AS SOURCE,
    src.CO_TYP_COT_ContainerType        AS SOURCE_TYPE,
    tgt.CO_NAM_Container_Name           AS TARGET,
    tgt.CO_TYP_COT_ContainerType        AS TARGET_TYPE,
    op.OP_INS_Operations_RowsInserted   AS ROWS_INSERTED,
    op.OP_UPD_Operations_RowsUpdated    AS ROWS_UPDATED,
    op.OP_DEL_Operations_RowsDeleted    AS ROWS_DELETED,
    op.OP_MRG_Operations_RowsMerged     AS ROWS_MERGED
FROM metadata.TR_operates_CO_source_CO_target_OP_with t
JOIN metadata.lTR_TaskRun tr  ON tr.TR_ID  = t.TR_ID_operates
JOIN metadata.lCO_Container src ON src.CO_ID = t.CO_ID_source
JOIN metadata.lCO_Container tgt ON tgt.CO_ID = t.CO_ID_target
LEFT JOIN metadata.lOP_Operations op ON op.OP_ID = t.OP_ID_with;

COMMENT ON VIEW metadata.Lineage IS
    'Source to target movements per task run, with reported row counts.';

-- ============================================================
-- CONTAINER FLOW
-- ============================================================
-- Lineage collapsed across runs: which containers feed which, and when it last happened.
-- This is the impact-analysis view — what breaks downstream if a source changes.

CREATE OR REPLACE VIEW metadata.ContainerFlow AS
SELECT
    SOURCE,
    TARGET,
    COUNT(DISTINCT TASK_NAME)  AS TASKS,
    COUNT(*)                   AS MOVEMENTS,
    MAX(STARTED_AT)            AS LAST_SEEN
FROM metadata.Lineage
GROUP BY SOURCE, TARGET;

COMMENT ON VIEW metadata.ContainerFlow IS
    'Distinct source to target edges across all runs, for impact analysis.';

-- ============================================================
-- INSTALLATIONS
-- ============================================================
-- What was deployed, from which configuration and template, and how it went. Outlives the
-- staged file, which prune.ps1 removes.

CREATE OR REPLACE VIEW metadata.Installations AS
SELECT
    il.IL_ID                              AS INSTALLATION_ID,
    il.IL_RID_Installation_RunId          AS RUN_ID,
    cf.CF_NAM_Configuration_Name          AS WORKFLOW,
    tp.TP_NAM_Template_Name               AS TEMPLATE,
    il.IL_RAT_Installation_RenderedAt     AS RENDERED_AT,
    il.IL_STA_ILS_InstallationStatus      AS STATUS,
    LENGTH(il.IL_DDL_Installation_RenderedSql) AS DDL_BYTES,
    il.IL_ERR_Installation_Error          AS ERROR
FROM metadata.lIL_Installation il
LEFT JOIN metadata.IL_installs_CF_configuration t ON t.IL_ID_installs = il.IL_ID
LEFT JOIN metadata.lCF_Configuration cf ON cf.CF_ID = t.CF_ID_configuration
LEFT JOIN metadata.IL_applies_TP_rendered a ON a.IL_ID_applies = il.IL_ID
LEFT JOIN metadata.lTP_Template tp ON tp.TP_ID = a.TP_ID_rendered;

COMMENT ON VIEW metadata.Installations IS
    'Deployment history. No status means rendered but never reported back on.';
