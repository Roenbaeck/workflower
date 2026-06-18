
-- ============================================================
-- Task graph: GolfDW_Load_Workflow Kaggle GolfDW
-- Generated from sisula-snowflake template
-- ============================================================


----------------------------------------------------------------
-- tsk_import_files
----------------------------------------------------------------
-- Procedure (wraps metadata logging + work)
CREATE OR REPLACE PROCEDURE sp_tsk_import_files()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    tr_id INT;
    op_id INT;
    grp_id VARCHAR;
    row_count INT;
    cfg VARCHAR;
BEGIN
    grp_id := (SELECT COALESCE(
        SYSTEM$TASK_RUNTIME_INFO('CURRENT_ROOT_TASK_UUID'),
        UUID_STRING()
    ));

    cfg := (SELECT SYSTEM$GET_TASK_GRAPH_CONFIG('workflow'));

    tr_id := (CALL metadata._TaskRunStarting('tsk_import_files', :grp_id, :cfg));

    -- Record lineage: Stage → Raw table
    op_id := (CALL metadata._TaskRunSourceToTarget(:tr_id, 'sisula.public.@golf_stage', 'golf_raw.public.PlayerImport'));

    -- COPY into raw table from stage
    op_id := (CALL metadata._TaskRunSourceToTarget(:tr_id, 'sisula.public.@golf_stage', 'golf_raw.public.PlayerImport'));
    COPY INTO golf_raw.public.PlayerImport FROM @golf_stage FILE_FORMAT = csv_ff ON_ERROR = CONTINUE;
    row_count := SQLROWCOUNT;
    CALL metadata._TaskRunSetRows(:op_id, :row_count, 0, 0, 0);

    -- Pass return value to child tasks
    CALL SYSTEM$SET_RETURN_VALUE('import complete');

    RETURN 'OK';
END;
$$;

-- Task (calls the procedure)
CREATE OR REPLACE TASK tsk_import_files
    WAREHOUSE = COMPUTE_WH
    USER_TASK_TIMEOUT_MS = 3600000
    SUSPEND_TASK_AFTER_NUM_FAILURES = 3
    COMMENT = 'Stage CSV files from external stage into raw tables'
    SCHEDULE = 'USING CRON 0 2 * * * UTC'
    CONFIG = '{"workflow":"GolfDW_Load_Workflow","environment":"production","source_path":"@golf_stage"}'
AS
    CALL sp_tsk_import_files();


----------------------------------------------------------------
-- tsk_create_typed_tables
----------------------------------------------------------------
-- Procedure (wraps metadata logging + work)
CREATE OR REPLACE PROCEDURE sp_tsk_create_typed_tables()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    tr_id INT;
    op_id INT;
    grp_id VARCHAR;
    row_count INT;
    cfg VARCHAR;
BEGIN
    grp_id := (SELECT COALESCE(
        SYSTEM$TASK_RUNTIME_INFO('CURRENT_ROOT_TASK_UUID'),
        UUID_STRING()
    ));

    cfg := (SELECT SYSTEM$GET_TASK_GRAPH_CONFIG('workflow'));

    tr_id := (CALL metadata._TaskRunStarting('tsk_create_typed_tables', :grp_id, :cfg));

    -- Execute: Create destination tables
    CALL golf_raw.sp_CreateTypedTables();

    RETURN 'OK';
END;
$$;

-- Task (calls the procedure)
CREATE OR REPLACE TASK tsk_create_typed_tables
    WAREHOUSE = COMPUTE_WH
    USER_TASK_TIMEOUT_MS = 3600000
    COMMENT = 'Create typed tables from raw import'
    AFTER tsk_import_files
AS
    CALL sp_tsk_create_typed_tables();


----------------------------------------------------------------
-- tsk_load_players
----------------------------------------------------------------
-- Procedure (wraps metadata logging + work)
CREATE OR REPLACE PROCEDURE sp_tsk_load_players()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    tr_id INT;
    op_id INT;
    grp_id VARCHAR;
    row_count INT;
    cfg VARCHAR;
BEGIN
    grp_id := (SELECT COALESCE(
        SYSTEM$TASK_RUNTIME_INFO('CURRENT_ROOT_TASK_UUID'),
        UUID_STRING()
    ));

    cfg := (SELECT SYSTEM$GET_TASK_GRAPH_CONFIG('workflow'));

    tr_id := (CALL metadata._TaskRunStarting('tsk_load_players', :grp_id, :cfg));

    -- Record lineage: Raw → DW
    op_id := (CALL metadata._TaskRunSourceToTarget(:tr_id, 'golf_raw.public.PlayerImport', 'golf_dw.public.lPL_Player'));

    -- Insert players into anchor
    op_id := (CALL metadata._TaskRunSourceToTarget(:tr_id, 'golf_raw.public.PlayerImport', 'golf_dw.public.lPL_Player'));
    INSERT INTO golf_dw.lPL_Player SELECT DISTINCT player_id, player_name FROM golf_raw.PlayerImport;
    row_count := SQLROWCOUNT;
    CALL metadata._TaskRunSetRows(:op_id, :row_count, 0, 0, 0);

    -- Pass return value to child tasks
    CALL SYSTEM$SET_RETURN_VALUE('players loaded');

    RETURN 'OK';
END;
$$;

-- Task (calls the procedure)
CREATE OR REPLACE TASK tsk_load_players
    WAREHOUSE = COMPUTE_WH
    USER_TASK_TIMEOUT_MS = 3600000
    COMMENT = 'Load Player entities'
    AFTER tsk_create_typed_tables
AS
    CALL sp_tsk_load_players();


----------------------------------------------------------------
-- tsk_load_stats
----------------------------------------------------------------
-- Procedure (wraps metadata logging + work)
CREATE OR REPLACE PROCEDURE sp_tsk_load_stats()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    tr_id INT;
    op_id INT;
    grp_id VARCHAR;
    row_count INT;
    cfg VARCHAR;
BEGIN
    grp_id := (SELECT COALESCE(
        SYSTEM$TASK_RUNTIME_INFO('CURRENT_ROOT_TASK_UUID'),
        UUID_STRING()
    ));

    cfg := (SELECT SYSTEM$GET_TASK_GRAPH_CONFIG('workflow'));

    tr_id := (CALL metadata._TaskRunStarting('tsk_load_stats', :grp_id, :cfg));

    -- Record lineage: Raw → DW
    op_id := (CALL metadata._TaskRunSourceToTarget(:tr_id, 'golf_raw.public.PlayerImport', 'golf_dw.public.lST_Statistic'));

    -- Insert statistics into anchor
    op_id := (CALL metadata._TaskRunSourceToTarget(:tr_id, 'golf_raw.public.PlayerImport', 'golf_dw.public.lST_Statistic'));
    INSERT INTO golf_dw.lST_Statistic SELECT DISTINCT stat_id, stat_name FROM golf_raw.PlayerImport WHERE stat_id IS NOT NULL;
    row_count := SQLROWCOUNT;
    CALL metadata._TaskRunSetRows(:op_id, :row_count, 0, 0, 0);

    -- Pass return value to child tasks
    CALL SYSTEM$SET_RETURN_VALUE('stats loaded');

    RETURN 'OK';
END;
$$;

-- Task (calls the procedure)
CREATE OR REPLACE TASK tsk_load_stats
    WAREHOUSE = COMPUTE_WH
    USER_TASK_TIMEOUT_MS = 3600000
    COMMENT = 'Load Statistic entities'
    AFTER tsk_create_typed_tables
AS
    CALL sp_tsk_load_stats();


----------------------------------------------------------------
-- tsk_load_measurements
----------------------------------------------------------------
-- Procedure (wraps metadata logging + work)
CREATE OR REPLACE PROCEDURE sp_tsk_load_measurements()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    tr_id INT;
    op_id INT;
    grp_id VARCHAR;
    row_count INT;
    cfg VARCHAR;
BEGIN
    grp_id := (SELECT COALESCE(
        SYSTEM$TASK_RUNTIME_INFO('CURRENT_ROOT_TASK_UUID'),
        UUID_STRING()
    ));

    cfg := (SELECT SYSTEM$GET_TASK_GRAPH_CONFIG('workflow'));

    tr_id := (CALL metadata._TaskRunStarting('tsk_load_measurements', :grp_id, :cfg));

    -- Record lineage: Raw → DW
    op_id := (CALL metadata._TaskRunSourceToTarget(:tr_id, 'golf_raw.public.PlayerImport', 'golf_dw.public.lME_Measurement'));

    -- Insert measurements with FK resolution
    op_id := (CALL metadata._TaskRunSourceToTarget(:tr_id, 'golf_raw.public.PlayerImport', 'golf_dw.public.lME_Measurement'));
    INSERT INTO golf_dw.lME_Measurement SELECT m.measurement_id, p.PL_ID, s.ST_ID, m.value FROM golf_raw.PlayerImport m JOIN golf_dw.lPL_Player p ON p.player_id = m.player_id JOIN golf_dw.lST_Statistic s ON s.stat_id = m.stat_id;
    row_count := SQLROWCOUNT;
    CALL metadata._TaskRunSetRows(:op_id, :row_count, 0, 0, 0);

    RETURN 'OK';
END;
$$;

-- Task (calls the procedure)
CREATE OR REPLACE TASK tsk_load_measurements
    WAREHOUSE = COMPUTE_WH
    USER_TASK_TIMEOUT_MS = 3600000
    COMMENT = 'Load Measurement entities (depends on Players + Stats)'
    AFTER tsk_load_players,tsk_load_stats
AS
    CALL sp_tsk_load_measurements();


-- ============================================================
-- Store workflow definition as a configuration
-- ============================================================

-- No configuration ID provided; tasks log without provenance

-- ============================================================
-- Set task state
-- ============================================================
ALTER TASK tsk_import_files SUSPEND;
ALTER TASK tsk_create_typed_tables SUSPEND;
ALTER TASK tsk_load_players SUSPEND;
ALTER TASK tsk_load_stats SUSPEND;
ALTER TASK tsk_load_measurements SUSPEND;


