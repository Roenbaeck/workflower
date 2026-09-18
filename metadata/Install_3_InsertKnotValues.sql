/*
    INSERT KNOT VALUES
    
    Populates the reference data (knots) for the metadata model.
    These are the enumerated values used by anchors and ties.
*/

-- ============================================================
-- CONTAINER TYPE
-- ============================================================

MERGE INTO metadata.COT_ContainerType k
USING (SELECT 'File'  AS val, 1 AS id UNION ALL
       SELECT 'Table',       2 UNION ALL
       SELECT 'View',        3 UNION ALL
       SELECT 'Stage',       4) v
ON k.COT_ContainerType = v.val
WHEN NOT MATCHED THEN INSERT (COT_ID, COT_ContainerType) VALUES (v.id, v.val);

-- ============================================================
-- CONFIGURATION TYPE
-- ============================================================

-- Environment is a configuration too: a named set of bindings merged over a workflow at
-- render time, so the same workflow can be installed into dev and production without
-- editing its definition.

MERGE INTO metadata.CFT_ConfigurationType k
USING (SELECT 'Workflow' AS val, 1 AS id UNION ALL
       SELECT 'Source',         2 UNION ALL
       SELECT 'Target',         3 UNION ALL
       SELECT 'Environment',    4) v
ON k.CFT_ConfigurationType = v.val
WHEN NOT MATCHED THEN INSERT (CFT_ID, CFT_ConfigurationType) VALUES (v.id, v.val);

-- ============================================================
-- INSTALLATION STATUS
-- ============================================================
-- The outcome an installation is reported to have reached. It is set once: an installation
-- with no status row was rendered but never reported back on. Execution stops at the first
-- failing statement and leaves earlier ones applied, so Failed means partially applied,
-- not untouched.

MERGE INTO metadata.ILS_InstallationStatus k
USING (SELECT 'Installed' AS val, 1 AS id UNION ALL
       SELECT 'Failed',           2) v
ON k.ILS_InstallationStatus = v.val
WHEN NOT MATCHED THEN INSERT (ILS_ID, ILS_InstallationStatus) VALUES (v.id, v.val);

-- ============================================================
-- TASK RUN STATUS
-- ============================================================
-- The outcome a task run reached. Set once, when the run ends. A task run with a start
-- time and no status is either still running or died without being able to report, which
-- is why StartedAt is recorded separately rather than inferred from a 'Running' status.

MERGE INTO metadata.TRS_TaskRunStatus k
USING (SELECT 'Succeeded' AS val, 1 AS id UNION ALL
       SELECT 'Failed',           2) v
ON k.TRS_TaskRunStatus = v.val
WHEN NOT MATCHED THEN INSERT (TRS_ID, TRS_TaskRunStatus) VALUES (v.id, v.val);
