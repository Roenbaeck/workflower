/*
    CREATE LOGGING PROCEDURES FOR SNOWFLAKE METADATA

    Inserts directly into Anchor base tables and attribute tables.
    The latest/point-in-time/now/difference perspective views remain read-only.
    Called from Sisula templates during task execution.
*/

-- ============================================================
-- HELPERS
-- ============================================================

CREATE OR REPLACE FUNCTION metadata._Now()
RETURNS TIMESTAMP_TZ
AS $$
    SYSDATE()::TIMESTAMP_TZ
$$;

-- ============================================================
-- TASK RUN STARTING
-- ============================================================

CREATE OR REPLACE PROCEDURE metadata._TaskRunStarting(
    TASK_NAME            VARCHAR,
    GRAPH_RUN_GROUP_ID   VARCHAR,
    CONFIG_NAME          VARCHAR DEFAULT NULL
)
RETURNS INT
LANGUAGE SQL
AS
$$
BEGIN
    LET tr_id INT;
    LET tkn_id INT;
    LET grg_id INT;
    LET cf_id INT;

    -- Upsert task name knot
    MERGE INTO metadata.TKN_TaskName k
    USING (SELECT :TASK_NAME AS val) v
    ON k.TKN_TaskName = v.val
    WHEN NOT MATCHED THEN INSERT (TKN_TaskName) VALUES (v.val);

    SELECT TKN_ID INTO :tkn_id FROM metadata.TKN_TaskName WHERE TKN_TaskName = :TASK_NAME;

    -- Upsert graph run group ID knot
    MERGE INTO metadata.GRG_GraphRunGroupId k
    USING (SELECT :GRAPH_RUN_GROUP_ID AS val) v
    ON k.GRG_GraphRunGroupId = v.val
    WHEN NOT MATCHED THEN INSERT (GRG_GraphRunGroupId) VALUES (v.val);

    SELECT GRG_ID INTO :grg_id FROM metadata.GRG_GraphRunGroupId WHERE GRG_GraphRunGroupId = :GRAPH_RUN_GROUP_ID;

    -- Insert anchor using explicit sequence
    SELECT metadata.TR_TaskRun_ID_SEQ.NEXTVAL INTO :tr_id;
    INSERT INTO metadata.TR_TaskRun (TR_ID) VALUES (:tr_id);

    -- Insert knotted static attribute: TaskName
    INSERT INTO metadata.TR_NAM_TaskRun_TaskName (TR_NAM_TR_ID, TR_NAM_TKN_ID)
    VALUES (:tr_id, :tkn_id);

    -- Insert knotted static attribute: GraphRunGroupId
    INSERT INTO metadata.TR_GRG_TaskRun_GraphRunGroupId (TR_GRG_TR_ID, TR_GRG_GRG_ID)
    VALUES (:tr_id, :grg_id);

    -- When it started. The outcome is recorded separately by _TaskRunFinished or
    -- _TaskRunFailed; a run with a start and no status is still running or died without
    -- being able to report.
    INSERT INTO metadata.TR_BEG_TaskRun_StartedAt (TR_BEG_TR_ID, TR_BEG_TaskRun_StartedAt)
    VALUES (:tr_id, SYSDATE());

    -- Link to configuration if provided
    IF (:CONFIG_NAME IS NOT NULL) THEN
        SELECT cf.CF_ID INTO :cf_id
        FROM metadata.CF_Configuration cf
        JOIN metadata.CF_NAM_Configuration_Name nam ON nam.CF_NAM_CF_ID = cf.CF_ID
        WHERE nam.CF_NAM_Configuration_Name = :CONFIG_NAME;

        IF (:cf_id IS NOT NULL) THEN
            MERGE INTO metadata.TR_formed_CF_from t
            USING (SELECT :tr_id AS tr, :cf_id AS cf) v
            ON t.TR_ID_formed = v.tr
            WHEN NOT MATCHED THEN INSERT (TR_ID_formed, CF_ID_from) VALUES (v.tr, v.cf);
        END IF;
    END IF;

    RETURN :tr_id;
END;
$$;

-- ============================================================
-- TASK RUN COMPLETION
-- ============================================================
-- A task run used to record only that it started, so a graph could fail every night and
-- the metadata would look healthy. These close the record. They are called from the
-- generated task body, including from its exception handler, so they must never raise:
-- losing the log must not also mask the error that caused it.

CREATE OR REPLACE PROCEDURE metadata._TaskRunFinished(
    TR_ID   INT,
    STATUS  VARCHAR DEFAULT 'Succeeded',
    ERROR   VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    trs_id TINYINT;
BEGIN
    IF (TR_ID IS NULL) THEN RETURN 'skipped'; END IF;

    SELECT TRS_ID INTO :trs_id
    FROM metadata.TRS_TaskRunStatus WHERE TRS_TaskRunStatus = :STATUS;
    IF (trs_id IS NULL) THEN RETURN 'unknown status'; END IF;

    INSERT INTO metadata.TR_FIN_TaskRun_FinishedAt (TR_FIN_TR_ID, TR_FIN_TaskRun_FinishedAt)
    VALUES (:TR_ID, SYSDATE());

    INSERT INTO metadata.TR_STA_TaskRun_Status (TR_STA_TR_ID, TR_STA_TRS_ID)
    VALUES (:TR_ID, :trs_id);

    IF (ERROR IS NOT NULL) THEN
        INSERT INTO metadata.TR_ERR_TaskRun_Error (TR_ERR_TR_ID, TR_ERR_TaskRun_Error)
        VALUES (:TR_ID, LEFT(:ERROR, 2000));
    END IF;

    RETURN :STATUS;
EXCEPTION
    WHEN OTHER THEN
        -- Never let logging failure replace the real outcome.
        RETURN 'logging failed';
END;
$$;

CREATE OR REPLACE PROCEDURE metadata._TaskRunFailed(TR_ID INT, ERROR VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    result VARCHAR;
BEGIN
    result := (CALL metadata._TaskRunFinished(:TR_ID, 'Failed', :ERROR));
    RETURN result;
EXCEPTION
    WHEN OTHER THEN
        RETURN 'logging failed';
END;
$$;

-- ============================================================
-- TASK RUN SOURCE TO TARGET (LINEAGE)
-- ============================================================

CREATE OR REPLACE PROCEDURE metadata._TaskRunSourceToTarget(
    TR_ID        INT,
    SOURCE_NAME  VARCHAR,
    TARGET_NAME  VARCHAR,
    SOURCE_TYPE  VARCHAR DEFAULT 'Table',
    TARGET_TYPE  VARCHAR DEFAULT 'Table'
)
RETURNS INT
LANGUAGE SQL
AS
$$
BEGIN
    LET co_id_source INT;
    LET co_id_target INT;
    LET cot_id_src TINYINT;
    LET cot_id_tgt TINYINT;
    LET op_id INT;
    LET now_ts TIMESTAMP_TZ := SYSDATE();

    -- Look up container type IDs
    SELECT COT_ID INTO :cot_id_src FROM metadata.COT_ContainerType WHERE COT_ContainerType = :SOURCE_TYPE;
    SELECT COT_ID INTO :cot_id_tgt FROM metadata.COT_ContainerType WHERE COT_ContainerType = :TARGET_TYPE;

    -- --------------- source container ---------------

    SELECT co.CO_ID INTO :co_id_source
    FROM metadata.CO_Container co
    JOIN metadata.CO_NAM_Container_Name nam ON nam.CO_NAM_CO_ID = co.CO_ID
    JOIN metadata.CO_TYP_Container_Type typ ON typ.CO_TYP_CO_ID = co.CO_ID
    WHERE nam.CO_NAM_Container_Name = :SOURCE_NAME
      AND typ.CO_TYP_COT_ID = :cot_id_src;

    IF (:co_id_source IS NULL) THEN
        SELECT metadata.CO_Container_ID_SEQ.NEXTVAL INTO :co_id_source;
        INSERT INTO metadata.CO_Container (CO_ID) VALUES (:co_id_source);

        INSERT INTO metadata.CO_NAM_Container_Name (CO_NAM_CO_ID, CO_NAM_Container_Name)
        VALUES (:co_id_source, :SOURCE_NAME);

        INSERT INTO metadata.CO_TYP_Container_Type (CO_TYP_CO_ID, CO_TYP_COT_ID)
        VALUES (:co_id_source, :cot_id_src);

        INSERT INTO metadata.CO_DSC_Container_Discovered (CO_DSC_CO_ID, CO_DSC_Container_Discovered, CO_DSC_ChangedAt)
        VALUES (:co_id_source, :now_ts, :now_ts);
    ELSE
        UPDATE metadata.CO_DSC_Container_Discovered
        SET CO_DSC_Container_Discovered = :now_ts, CO_DSC_ChangedAt = :now_ts
        WHERE CO_DSC_CO_ID = :co_id_source;
    END IF;

    -- --------------- target container ---------------

    SELECT co.CO_ID INTO :co_id_target
    FROM metadata.CO_Container co
    JOIN metadata.CO_NAM_Container_Name nam ON nam.CO_NAM_CO_ID = co.CO_ID
    JOIN metadata.CO_TYP_Container_Type typ ON typ.CO_TYP_CO_ID = co.CO_ID
    WHERE nam.CO_NAM_Container_Name = :TARGET_NAME
      AND typ.CO_TYP_COT_ID = :cot_id_tgt;

    IF (:co_id_target IS NULL) THEN
        SELECT metadata.CO_Container_ID_SEQ.NEXTVAL INTO :co_id_target;
        INSERT INTO metadata.CO_Container (CO_ID) VALUES (:co_id_target);

        INSERT INTO metadata.CO_NAM_Container_Name (CO_NAM_CO_ID, CO_NAM_Container_Name)
        VALUES (:co_id_target, :TARGET_NAME);

        INSERT INTO metadata.CO_TYP_Container_Type (CO_TYP_CO_ID, CO_TYP_COT_ID)
        VALUES (:co_id_target, :cot_id_tgt);

        INSERT INTO metadata.CO_DSC_Container_Discovered (CO_DSC_CO_ID, CO_DSC_Container_Discovered, CO_DSC_ChangedAt)
        VALUES (:co_id_target, :now_ts, :now_ts);
    ELSE
        UPDATE metadata.CO_DSC_Container_Discovered
        SET CO_DSC_Container_Discovered = :now_ts, CO_DSC_ChangedAt = :now_ts
        WHERE CO_DSC_CO_ID = :co_id_target;
    END IF;

    -- --------------- operations anchor and tie ---------------

    SELECT OP_ID_with INTO :op_id
    FROM metadata.TR_operates_CO_source_CO_target_OP_with
    WHERE TR_ID_operates = :TR_ID
      AND CO_ID_source = :co_id_source
      AND CO_ID_target = :co_id_target;

    IF (:op_id IS NULL) THEN
        SELECT metadata.OP_Operations_ID_SEQ.NEXTVAL INTO :op_id;
        INSERT INTO metadata.OP_Operations (OP_ID) VALUES (:op_id);

        INSERT INTO metadata.OP_INS_Operations_RowsInserted (OP_INS_OP_ID, OP_INS_Operations_RowsInserted, OP_INS_ChangedAt)
        VALUES (:op_id, 0, :now_ts);

        INSERT INTO metadata.OP_UPD_Operations_RowsUpdated (OP_UPD_OP_ID, OP_UPD_Operations_RowsUpdated, OP_UPD_ChangedAt)
        VALUES (:op_id, 0, :now_ts);

        INSERT INTO metadata.OP_DEL_Operations_RowsDeleted (OP_DEL_OP_ID, OP_DEL_Operations_RowsDeleted, OP_DEL_ChangedAt)
        VALUES (:op_id, 0, :now_ts);

        INSERT INTO metadata.OP_MRG_Operations_RowsMerged (OP_MRG_OP_ID, OP_MRG_Operations_RowsMerged, OP_MRG_ChangedAt)
        VALUES (:op_id, 0, :now_ts);

        INSERT INTO metadata.TR_operates_CO_source_CO_target_OP_with
            (TR_ID_operates, CO_ID_source, CO_ID_target, OP_ID_with)
        VALUES (:TR_ID, :co_id_source, :co_id_target, :op_id);
    END IF;

    RETURN :op_id;
END;
$$;

-- ============================================================
-- SET OPERATION ROW COUNTS
-- ============================================================

CREATE OR REPLACE PROCEDURE metadata._TaskRunSetRows(
    OP_ID          INT,
    ROWS_INSERTED  INT DEFAULT 0,
    ROWS_UPDATED   INT DEFAULT 0,
    ROWS_DELETED   INT DEFAULT 0,
    ROWS_MERGED    INT DEFAULT 0
)
RETURNS INT
LANGUAGE SQL
AS
$$
BEGIN
    LET now_ts TIMESTAMP_TZ := SYSDATE();

    INSERT INTO metadata.OP_INS_Operations_RowsInserted (OP_INS_OP_ID, OP_INS_Operations_RowsInserted, OP_INS_ChangedAt)
    VALUES (:OP_ID, :ROWS_INSERTED, :now_ts);

    INSERT INTO metadata.OP_UPD_Operations_RowsUpdated (OP_UPD_OP_ID, OP_UPD_Operations_RowsUpdated, OP_UPD_ChangedAt)
    VALUES (:OP_ID, :ROWS_UPDATED, :now_ts);

    INSERT INTO metadata.OP_DEL_Operations_RowsDeleted (OP_DEL_OP_ID, OP_DEL_Operations_RowsDeleted, OP_DEL_ChangedAt)
    VALUES (:OP_ID, :ROWS_DELETED, :now_ts);

    INSERT INTO metadata.OP_MRG_Operations_RowsMerged (OP_MRG_OP_ID, OP_MRG_Operations_RowsMerged, OP_MRG_ChangedAt)
    VALUES (:OP_ID, :ROWS_MERGED, :now_ts);

    RETURN :OP_ID;
END;
$$;

-- ============================================================
-- DELETE OLD METADATA (PRUNING UTILITY)
-- ============================================================

CREATE OR REPLACE PROCEDURE metadata._DeleteMetadata(
    OLDER_THAN TIMESTAMP_TZ,
    DRY_RUN    BOOLEAN DEFAULT FALSE
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    old_ops CURSOR FOR
        SELECT DISTINCT op.OP_ID
        FROM metadata.OP_INS_Operations_RowsInserted ins
        JOIN metadata.OP_Operations op ON ins.OP_INS_OP_ID = op.OP_ID
        WHERE ins.OP_INS_ChangedAt < :OLDER_THAN;

    deleted INT DEFAULT 0;
BEGIN
    LET op_count INT;

    SELECT COUNT(DISTINCT op.OP_ID) INTO :op_count
    FROM metadata.OP_INS_Operations_RowsInserted ins
    JOIN metadata.OP_Operations op ON ins.OP_INS_OP_ID = op.OP_ID
    WHERE ins.OP_INS_ChangedAt < :OLDER_THAN;

    IF (:op_count = 0) THEN
        RETURN 'No operations older than ' || :OLDER_THAN;
    END IF;

    IF (DRY_RUN) THEN
        RETURN 'DRY RUN: ' || :op_count || ' operations would be deleted';
    END IF;

    FOR op IN old_ops DO
        DELETE FROM metadata.TR_operates_CO_source_CO_target_OP_with WHERE OP_ID_with = op.OP_ID;
        DELETE FROM metadata.OP_INS_Operations_RowsInserted WHERE OP_INS_OP_ID = op.OP_ID;
        DELETE FROM metadata.OP_UPD_Operations_RowsUpdated   WHERE OP_UPD_OP_ID = op.OP_ID;
        DELETE FROM metadata.OP_DEL_Operations_RowsDeleted   WHERE OP_DEL_OP_ID = op.OP_ID;
        DELETE FROM metadata.OP_MRG_Operations_RowsMerged    WHERE OP_MRG_OP_ID = op.OP_ID;
        DELETE FROM metadata.OP_Operations                  WHERE OP_ID = op.OP_ID;
        deleted := deleted + 1;
    END FOR;

    RETURN 'Deleted ' || :op_count || ' operations older than ' || :OLDER_THAN;
END;
$$;
