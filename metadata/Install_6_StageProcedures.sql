/*
    WORKFLOWER STAGE AND STAGE-BACKED PROCEDURES

    The Snowflake CLI has no bind variables, so anything the client interpolates into SQL
    would have to be hand-escaped. Instead payloads travel as staged files and the only
    value the client ever puts into SQL is a GUID, which these procedures re-validate.

    Stage layout:
        in/<run_id>.json    workflow JSON uploaded by the client
        in/<run_id>.sql     template source uploaded by the deployer
        out/<run_id>.sql    rendered DDL, executed with EXECUTE IMMEDIATE FROM
        export/<run_id>.json  reverse engineered graphs, downloaded by the client

    Files under out/ are kept as an audit trail of exactly what was executed. Nothing here
    deletes them.
*/

CREATE STAGE IF NOT EXISTS metadata.WORKFLOWER
    COMMENT = 'Workflower payload exchange. See Install_6_StageProcedures.sql.';

-- Reads a whole file back as one byte-exact string. Every option matters: the default
-- record delimiter would split on newlines, the default escape character would eat
-- backslashes, and the default compression would gzip unloaded files.
CREATE FILE FORMAT IF NOT EXISTS metadata.WF_RAW
    TYPE = CSV
    COMPRESSION = NONE
    FIELD_DELIMITER = NONE
    RECORD_DELIMITER = NONE
    ESCAPE_UNENCLOSED_FIELD = NONE
    FIELD_OPTIONALLY_ENCLOSED_BY = NONE;

-- ============================================================
-- RUN ID VALIDATION
-- ============================================================
-- A stage path cannot be bound, so these procedures build it with string concatenation.
-- The client only ever sends a GUID; this is the second check, not the only one.

CREATE OR REPLACE FUNCTION metadata._IsRunId(RUN_ID VARCHAR)
RETURNS BOOLEAN
AS
$$
    RUN_ID IS NOT NULL
    AND RLIKE(RUN_ID, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
$$;

-- ============================================================
-- READ A STAGED FILE AS TEXT
-- ============================================================
-- Note: two staged-file subqueries in one statement can return the same file, so every
-- read here is its own statement.

CREATE OR REPLACE PROCEDURE metadata._StageReadText(STAGE_PATH VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    content VARCHAR;
    rs RESULTSET;
BEGIN
    rs := (EXECUTE IMMEDIATE
        'SELECT $1 FROM @metadata.WORKFLOWER/' || :STAGE_PATH ||
        ' (FILE_FORMAT => metadata.WF_RAW)');
    LET cur CURSOR FOR rs;
    OPEN cur;
    FETCH cur INTO content;
    CLOSE cur;
    RETURN content;
END;
$$;

-- ============================================================
-- UPSERT A CONFIGURATION FROM A STAGED FILE
-- ============================================================

CREATE OR REPLACE PROCEDURE metadata._ConfigurationUpsertFromStage(RUN_ID VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
AS
$$
DECLARE
    content VARCHAR;
    doc VARIANT;
    wf_name VARCHAR;
    cf_id INT;
    bad_run_id EXCEPTION (-20001, 'Run id must be a GUID');
    bad_json EXCEPTION (-20002, 'Staged file is not valid JSON');
    no_name EXCEPTION (-20003, 'Workflow JSON has no WORKFLOW name');
BEGIN
    IF (NOT metadata._IsRunId(:RUN_ID)) THEN RAISE bad_run_id; END IF;

    content := (CALL metadata._StageReadText('in/' || :RUN_ID || '.json'));

    -- Parse for the name, but store the original text. The document is kept byte for byte
    -- as the client wrote it; TO_JSON would reorder object keys and drop formatting.
    doc := TRY_PARSE_JSON(:content);
    IF (doc IS NULL) THEN RAISE bad_json; END IF;

    wf_name := doc:WORKFLOW::VARCHAR;
    IF (wf_name IS NULL OR wf_name = '') THEN RAISE no_name; END IF;

    cf_id := (CALL metadata._ConfigurationUpsert(:wf_name, :content, 'Workflow'));

    RETURN OBJECT_CONSTRUCT('cf_id', :cf_id, 'name', :wf_name);
END;
$$;

-- ============================================================
-- DELETE A CONFIGURATION BY ID
-- ============================================================
-- The client addresses workflows by CF_ID so that a workflow name never has to be
-- interpolated into SQL. _ConfigurationDelete takes a name, so the lookup happens here.

CREATE OR REPLACE PROCEDURE metadata._ConfigurationDeleteById(CF_ID INT)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    wf_name VARCHAR;
    status VARCHAR;
    no_config EXCEPTION (-20006, 'Configuration not found');
BEGIN
    SELECT CF_NAM_Configuration_Name INTO :wf_name
    FROM metadata.lCF_Configuration
    WHERE CF_ID = :CF_ID AND CF_TYP_CFT_ConfigurationType = 'Workflow';
    IF (wf_name IS NULL) THEN RAISE no_config; END IF;

    status := (CALL metadata._ConfigurationDelete(:wf_name));
    RETURN status;
END;
$$;

-- ============================================================
-- UPSERT A TEMPLATE FROM A STAGED FILE
-- ============================================================

CREATE OR REPLACE PROCEDURE metadata._TemplateUpsertFromStage(RUN_ID VARCHAR, TEMPLATE_NAME VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    content VARCHAR;
    bad_run_id EXCEPTION (-20001, 'Run id must be a GUID');
    empty_template EXCEPTION (-20004, 'Staged template is empty');
BEGIN
    IF (NOT metadata._IsRunId(:RUN_ID)) THEN RAISE bad_run_id; END IF;

    content := (CALL metadata._StageReadText('in/' || :RUN_ID || '.sql'));
    IF (content IS NULL OR content = '') THEN RAISE empty_template; END IF;

    CALL metadata._TemplateUpsert(:TEMPLATE_NAME, :content);
    RETURN 'OK';
END;
$$;

-- ============================================================
-- RENDER A CONFIGURATION TO THE STAGE
-- ============================================================

-- The core. Both entry points below funnel through this so the native-task guard and the
-- unload options live in exactly one place.
CREATE OR REPLACE PROCEDURE metadata._RenderTextToStage(BINDINGS VARCHAR, TEMPLATE_NAME VARCHAR, RUN_ID VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
AS
$$
DECLARE
    template_text VARCHAR;
    rendered VARCHAR;
    missing_native INT;
    bad_run_id EXCEPTION (-20001, 'Run id must be a GUID');
    no_template EXCEPTION (-20005, 'Template not found');
    render_failed EXCEPTION (-20007, 'Template rendering produced no SQL');
    stale_template EXCEPTION (-20008, 'The deployed template does not support native tasks. Deploy the updated CreateTaskGraph template before installing this import.');
BEGIN
    IF (NOT metadata._IsRunId(:RUN_ID)) THEN RAISE bad_run_id; END IF;

    SELECT TP_CNT_Template_Content INTO :template_text
    FROM metadata.lTP_Template WHERE TP_NAM_Template_Name = :TEMPLATE_NAME;
    IF (template_text IS NULL) THEN RAISE no_template; END IF;

    LET config_text VARCHAR := :BINDINGS;
    rendered := (SELECT SISULATE(:template_text, :BINDINGS));
    IF (rendered IS NULL OR TRIM(rendered) = '' OR STARTSWITH(LTRIM(rendered), 'ERROR:')) THEN
        RAISE render_failed;
    END IF;

    -- An older deployed template would silently drop native task bodies rather than fail.
    SELECT COUNT(*) INTO :missing_native
    FROM TABLE(FLATTEN(input => PARSE_JSON(:config_text):TASKS)) tasks
    WHERE tasks.value:native IS NOT NULL
      AND (tasks.value:native:header IS NULL
           OR POSITION(tasks.value:native:header::VARCHAR, :rendered) = 0);
    IF (missing_native > 0) THEN RAISE stale_template; END IF;

    -- COPY INTO cannot take the rendered text as a bind, and embedding it as a literal
    -- would reintroduce the escaping problem this design exists to remove. A session
    -- temporary table carries it across instead.
    CREATE OR REPLACE TEMPORARY TABLE metadata._RenderBuffer (content VARCHAR);
    INSERT INTO metadata._RenderBuffer (content) VALUES (:rendered);

    -- SINGLE = TRUE cannot overwrite, which is why the filename carries a fresh run id.
    EXECUTE IMMEDIATE
        'COPY INTO @metadata.WORKFLOWER/out/' || :RUN_ID || '.sql ' ||
        'FROM (SELECT content FROM metadata._RenderBuffer) ' ||
        'FILE_FORMAT = (FORMAT_NAME = ''metadata.WF_RAW'') SINGLE = TRUE';

    RETURN OBJECT_CONSTRUCT('run_id', :RUN_ID, 'bytes', LENGTH(:rendered),
                            'lines', ARRAY_SIZE(SPLIT(:rendered, '\n')));
END;
$$;

-- Render a stored configuration. Used by the editor's install.
CREATE OR REPLACE PROCEDURE metadata._RenderToStage(CF_ID INT, TEMPLATE_NAME VARCHAR, RUN_ID VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
AS
$$
DECLARE
    config_text VARCHAR;
    bindings VARCHAR;
    result VARIANT;
    no_config EXCEPTION (-20006, 'Configuration not found');
BEGIN
    SELECT CF_CNT_Configuration_Content INTO :config_text
    FROM metadata.lCF_Configuration
    WHERE CF_ID = :CF_ID AND CF_TYP_CFT_ConfigurationType = 'Workflow';
    IF (config_text IS NULL) THEN RAISE no_config; END IF;

    -- CF_ID is a render-time binding, not part of the stored document.
    bindings := (SELECT TO_JSON(OBJECT_INSERT(PARSE_JSON(:config_text), 'CF_ID', :CF_ID, TRUE)));

    result := (CALL metadata._RenderTextToStage(:bindings, :TEMPLATE_NAME, :RUN_ID));
    RETURN result;
END;
$$;

-- Render a staged file without storing it as a configuration. Used by install.ps1, which
-- has always rendered its input without adding it to the workflow library.
CREATE OR REPLACE PROCEDURE metadata._RenderStageFileToStage(IN_RUN_ID VARCHAR, TEMPLATE_NAME VARCHAR, OUT_RUN_ID VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
AS
$$
DECLARE
    content VARCHAR;
    result VARIANT;
    bad_run_id EXCEPTION (-20001, 'Run id must be a GUID');
    bad_json EXCEPTION (-20002, 'Staged file is not valid JSON');
BEGIN
    IF (NOT metadata._IsRunId(:IN_RUN_ID)) THEN RAISE bad_run_id; END IF;

    content := (CALL metadata._StageReadText('in/' || :IN_RUN_ID || '.json'));
    IF (TRY_PARSE_JSON(:content) IS NULL) THEN RAISE bad_json; END IF;

    result := (CALL metadata._RenderTextToStage(:content, :TEMPLATE_NAME, :OUT_RUN_ID));
    RETURN result;
END;
$$;
