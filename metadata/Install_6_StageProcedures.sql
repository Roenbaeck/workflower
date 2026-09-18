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

-- The directory table is what prune.ps1 ages files by: DIRECTORY() reports LAST_MODIFIED
-- as a real timestamp, where LIST reports an RFC 1123 string. It does not refresh itself
-- on an internal stage, so the prune job refreshes it rather than every upload paying.
CREATE STAGE IF NOT EXISTS metadata.WORKFLOWER
    DIRECTORY = (ENABLE = TRUE)
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

-- PREVIOUS_CF_ID makes a rename atomic. The old client saved under the new name and then
-- issued a separate delete, so a failure between the two left two copies behind while the
-- UI reported success.
-- Snowflake will not overload an existing procedure with a differing argument list, so the
-- earlier single-argument form is dropped first.
DROP PROCEDURE IF EXISTS metadata._ConfigurationUpsertFromStage(VARCHAR);
DROP PROCEDURE IF EXISTS metadata._ConfigurationUpsertFromStage(VARCHAR, INT);

CREATE OR REPLACE PROCEDURE metadata._ConfigurationUpsertFromStage(
    RUN_ID VARCHAR,
    PREVIOUS_CF_ID INT DEFAULT NULL,
    CONFIG_TYPE VARCHAR DEFAULT 'Workflow'
)
RETURNS VARIANT
LANGUAGE SQL
AS
$$
DECLARE
    content VARCHAR;
    doc VARIANT;
    wf_name VARCHAR;
    cf_id INT;
    previous_name VARCHAR;
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

    -- A workflow names itself with WORKFLOW; an environment uses NAME.
    wf_name := (SELECT COALESCE(:doc:NAME::VARCHAR, :doc:WORKFLOW::VARCHAR));
    IF (wf_name IS NULL OR wf_name = '') THEN RAISE no_name; END IF;

    cf_id := (CALL metadata._ConfigurationUpsert(:wf_name, :content, :CONFIG_TYPE));

    -- A rename produced a new configuration; retire the one it replaced.
    IF (PREVIOUS_CF_ID IS NOT NULL AND :PREVIOUS_CF_ID <> :cf_id) THEN
        SELECT CF_NAM_Configuration_Name INTO :previous_name
        FROM metadata.lCF_Configuration
        WHERE CF_ID = :PREVIOUS_CF_ID AND CF_TYP_CFT_ConfigurationType = 'Workflow';
        IF (previous_name IS NOT NULL) THEN
            CALL metadata._ConfigurationDelete(:previous_name);
        END IF;
    END IF;

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

-- ============================================================
-- VALIDATE A WORKFLOW GRAPH
-- ============================================================
-- The import path has always checked graph shape rigorously, while the authoring path
-- checked nothing: a cycle or a duplicate name was only discovered when Snowflake rejected
-- the DDL, by which point earlier statements had already applied. This runs the same
-- checks before anything is rendered. Returns an array of problems; empty means valid.

CREATE OR REPLACE PROCEDURE metadata._ValidateWorkflow(BINDINGS VARCHAR)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
AS
$$
var problems = [];
function fail(message) { problems.push(message); }

var doc;
try { doc = JSON.parse(BINDINGS); }
catch (e) { return ['Workflow JSON is not valid: ' + e.message]; }
if (!doc || typeof doc !== 'object' || Array.isArray(doc)) return ['Workflow JSON must be an object'];

if (!doc.WORKFLOW) fail('WORKFLOW name is missing');

var tasks = doc.TASKS;
if (Object.prototype.toString.call(tasks) !== '[object Array]') return ['TASKS must be an array'];
if (!tasks.length) return ['TASKS is empty; a workflow needs at least one task'];

// ---- names -----------------------------------------------------------------
var byName = {};
for (var i = 0; i < tasks.length; i++) {
    var name = tasks[i] && tasks[i].name;
    if (!name) { fail('Task ' + (i + 1) + ' has no name'); continue; }
    if (byName.hasOwnProperty(name)) {
        // Duplicates collapse into one graph node in the editor and emit two
        // CREATE OR REPLACE TASK statements for the same object.
        fail('Duplicate task name: ' + name);
    }
    byName[name] = tasks[i];
}

// ---- predecessors ----------------------------------------------------------
var predecessors = {};
for (var n in byName) {
    if (!byName.hasOwnProperty(n)) continue;
    var after = byName[n].after;
    predecessors[n] = [];
    if (after === null || after === undefined) continue;
    if (Object.prototype.toString.call(after) !== '[object Array]') {
        fail('after must be an array on task ' + n);
        continue;
    }
    for (var a = 0; a < after.length; a++) {
        var parent = after[a] && after[a].name;
        if (!parent) { fail('An after entry on task ' + n + ' has no name'); continue; }
        if (!byName.hasOwnProperty(parent)) {
            fail('Task ' + n + ' runs after ' + parent + ', which is not in this workflow');
            continue;
        }
        if (parent === n) fail('Task ' + n + ' runs after itself');
        predecessors[n].push(parent);
    }
}

// ---- exactly one root ------------------------------------------------------
// A Snowflake task graph has one root: the only task carrying the schedule.
var roots = [];
for (var r in predecessors) {
    if (predecessors.hasOwnProperty(r) && predecessors[r].length === 0) roots.push(r);
}
if (roots.length === 0) fail('No root task: every task runs after another, which is a cycle');
if (roots.length > 1) fail('More than one root task: ' + roots.sort().join(', ') + '. A task graph has exactly one root.');

for (var f in byName) {
    if (!byName.hasOwnProperty(f)) continue;
    var declared = byName[f].is_root === true;
    var actual = predecessors[f] && predecessors[f].length === 0;
    if (declared && !actual) fail('Task ' + f + ' is marked is_root but runs after another task');
    if (!declared && actual && roots.length === 1) fail('Task ' + f + ' is the root but is not marked is_root');
    if (byName[f].schedule && !declared) fail('Task ' + f + ' has a schedule but is not the root task');
}

// ---- cycles ----------------------------------------------------------------
var pending = {};
for (var p in predecessors) if (predecessors.hasOwnProperty(p)) pending[p] = predecessors[p].slice();
var progressed = true;
while (progressed) {
    progressed = false;
    for (var q in pending) {
        if (!pending.hasOwnProperty(q)) continue;
        if (pending[q].length === 0) {
            delete pending[q];
            for (var s in pending) {
                if (!pending.hasOwnProperty(s)) continue;
                pending[s] = pending[s].filter(function (x) { return x !== q; });
            }
            progressed = true;
        }
    }
}
var stuck = Object.keys(pending).sort();
if (stuck.length) fail('Cycle between tasks: ' + stuck.join(', '));

// ---- steps -----------------------------------------------------------------
var REQUIRED = {
    proc: ['call'],
    sql: ['sql'],
    lineage: ['source', 'target'],
    rows: [],
    return_value: ['message']
};
for (var t in byName) {
    if (!byName.hasOwnProperty(t)) continue;
    if (byName[t].native) continue;  // a native task carries its own DDL, not steps
    var steps = byName[t].steps;
    if (steps === undefined || steps === null) continue;
    if (Object.prototype.toString.call(steps) !== '[object Array]') { fail('steps must be an array on task ' + t); continue; }
    for (var si = 0; si < steps.length; si++) {
        var step = steps[si], where = 'step ' + (si + 1) + ' of task ' + t;
        if (!step || !step.type) { fail(where + ' has no type'); continue; }
        if (!REQUIRED.hasOwnProperty(step.type)) { fail(where + ' has unknown type ' + step.type); continue; }
        var required = REQUIRED[step.type];
        for (var ri = 0; ri < required.length; ri++) {
            if (!step[required[ri]]) fail(where + ' (' + step.type + ') is missing ' + required[ri]);
        }
        if (step.type === 'sql' && (!step.lineage || !step.lineage.source || !step.lineage.target)) {
            fail(where + ' (sql) is missing lineage.source or lineage.target');
        }
    }
}

return problems;
$$;


-- Validate a stored configuration. The editor calls this before installing so the problems
-- can be listed, rather than discovering them when Snowflake rejects the DDL.
CREATE OR REPLACE PROCEDURE metadata._ValidateWorkflowById(CF_ID INT)
RETURNS VARIANT
LANGUAGE SQL
AS
$$
DECLARE
    config_text VARCHAR;
    problems VARIANT;
    no_config EXCEPTION (-20006, 'Configuration not found');
BEGIN
    SELECT CF_CNT_Configuration_Content INTO :config_text
    FROM metadata.lCF_Configuration
    WHERE CF_ID = :CF_ID AND CF_TYP_CFT_ConfigurationType = 'Workflow';
    IF (config_text IS NULL) THEN RAISE no_config; END IF;

    problems := (CALL metadata._ValidateWorkflow(:config_text));
    RETURN problems;
END;
$$;


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
    il_id INT;
    tp_id INT;
    problems VARIANT;
    now_ts TIMESTAMP_TZ := SYSDATE();
    bad_run_id EXCEPTION (-20001, 'Run id must be a GUID');
    invalid_workflow EXCEPTION (-20011, 'The workflow graph is not valid');
    no_template EXCEPTION (-20005, 'Template not found');
    render_failed EXCEPTION (-20007, 'Template rendering produced no SQL');
    stale_template EXCEPTION (-20008, 'The deployed template does not support native tasks. Deploy the updated CreateTaskGraph template before installing this import.');
BEGIN
    IF (NOT metadata._IsRunId(:RUN_ID)) THEN RAISE bad_run_id; END IF;

    -- Refuse to render a graph Snowflake would reject halfway through applying it. A
    -- declared exception carries a fixed message, so the problems themselves come from
    -- _ValidateWorkflowById, which the client calls before installing; this is the
    -- backstop for anything that reaches here another way.
    problems := (CALL metadata._ValidateWorkflow(:BINDINGS));
    IF (ARRAY_SIZE(:problems) > 0) THEN RAISE invalid_workflow; END IF;

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
    -- would reintroduce the escaping problem this design exists to remove. The rendered
    -- DDL is recorded against an Installation instead, which both carries it into the
    -- unload and keeps a durable record after the staged file is pruned.
    SELECT metadata.IL_Installation_ID_SEQ.NEXTVAL INTO :il_id;
    INSERT INTO metadata.IL_Installation (IL_ID) VALUES (:il_id);
    INSERT INTO metadata.IL_RID_Installation_RunId (IL_RID_IL_ID, IL_RID_Installation_RunId)
        VALUES (:il_id, :RUN_ID);
    INSERT INTO metadata.IL_DDL_Installation_RenderedSql (IL_DDL_IL_ID, IL_DDL_Installation_RenderedSql)
        VALUES (:il_id, :rendered);
    INSERT INTO metadata.IL_RAT_Installation_RenderedAt (IL_RAT_IL_ID, IL_RAT_Installation_RenderedAt)
        VALUES (:il_id, :now_ts);
    -- Status is set once, by _InstallationCompleted. An installation with no status row
    -- was rendered but never reported back on.

    -- SINGLE = TRUE cannot overwrite, which is why the filename carries a fresh run id.
    EXECUTE IMMEDIATE
        'COPY INTO @metadata.WORKFLOWER/out/' || :RUN_ID || '.sql ' ||
        'FROM (SELECT IL_DDL_Installation_RenderedSql FROM metadata.IL_DDL_Installation_RenderedSql ' ||
        'WHERE IL_DDL_IL_ID = ' || :il_id || ') ' ||
        'FILE_FORMAT = (FORMAT_NAME = ''metadata.WF_RAW'') SINGLE = TRUE';

    -- Record which template produced it.
    SELECT tp.TP_ID INTO :tp_id
    FROM metadata.TP_Template tp
    JOIN metadata.TP_NAM_Template_Name nam ON nam.TP_NAM_TP_ID = tp.TP_ID
    WHERE nam.TP_NAM_Template_Name = :TEMPLATE_NAME;
    IF (tp_id IS NOT NULL) THEN
        INSERT INTO metadata.IL_applies_TP_rendered (IL_ID_applies, TP_ID_rendered)
        VALUES (:il_id, :tp_id);
    END IF;

    RETURN OBJECT_CONSTRUCT('run_id', :RUN_ID, 'il_id', :il_id, 'bytes', LENGTH(:rendered),
                            'lines', ARRAY_SIZE(SPLIT(:rendered, '\n')));
END;
$$;

-- Render a stored configuration. Used by the editor's install.
--
-- ENV_CF_ID names an Environment configuration whose keys are merged over the workflow's
-- own, so the same definition installs into dev and production without being edited. The
-- environment is addressed by id rather than name, like everything else, so no user text
-- reaches SQL.
DROP PROCEDURE IF EXISTS metadata._RenderToStage(INT, VARCHAR, VARCHAR);

CREATE OR REPLACE PROCEDURE metadata._RenderToStage(CF_ID INT, TEMPLATE_NAME VARCHAR, RUN_ID VARCHAR, ENV_CF_ID INT DEFAULT NULL)
RETURNS VARIANT
LANGUAGE SQL
AS
$$
DECLARE
    config_text VARCHAR;
    env_text VARCHAR;
    merged VARIANT;
    bindings VARCHAR;
    result VARIANT;
    new_il_id INT;
    no_config EXCEPTION (-20006, 'Configuration not found');
    no_environment EXCEPTION (-20012, 'Environment configuration not found');
BEGIN
    SELECT CF_CNT_Configuration_Content INTO :config_text
    FROM metadata.lCF_Configuration
    WHERE CF_ID = :CF_ID AND CF_TYP_CFT_ConfigurationType = 'Workflow';
    IF (config_text IS NULL) THEN RAISE no_config; END IF;

    merged := (SELECT PARSE_JSON(:config_text));

    IF (ENV_CF_ID IS NOT NULL) THEN
        SELECT CF_CNT_Configuration_Content INTO :env_text
        FROM metadata.lCF_Configuration
        WHERE CF_ID = :ENV_CF_ID AND CF_TYP_CFT_ConfigurationType = 'Environment';
        IF (env_text IS NULL) THEN RAISE no_environment; END IF;

        -- Environment keys win. Snowflake has no object merge, so flatten both and keep
        -- the higher-priority row per key. The environment is also exposed whole as ENV,
        -- so a template can reach values that are not workflow-level fields.
        merged := (
            SELECT OBJECT_AGG(key, value)
            FROM (
                SELECT key, value
                FROM (
                    SELECT key, value, 1 AS priority FROM TABLE(FLATTEN(input => PARSE_JSON(:config_text)))
                    UNION ALL
                    SELECT key, value, 2            FROM TABLE(FLATTEN(input => PARSE_JSON(:env_text)))
                )
                QUALIFY ROW_NUMBER() OVER (PARTITION BY key ORDER BY priority DESC) = 1
            )
        );
        merged := (SELECT OBJECT_INSERT(:merged, 'ENV', PARSE_JSON(:env_text), TRUE));
    END IF;

    -- CF_ID is a render-time binding, not part of the stored document.
    bindings := (SELECT TO_JSON(OBJECT_INSERT(:merged, 'CF_ID', :CF_ID, TRUE)));

    result := (CALL metadata._RenderTextToStage(:bindings, :TEMPLATE_NAME, :RUN_ID));

    -- Tie the installation to the configuration it came from, so the audit trail survives
    -- the staged file being pruned. The identity is read into a variable first: a VARIANT
    -- path is not a valid expression inside a VALUES clause.
    new_il_id := (SELECT :result:il_id::INT);
    INSERT INTO metadata.IL_installs_CF_configuration (IL_ID_installs, CF_ID_configuration)
    VALUES (:new_il_id, :CF_ID);

    RETURN result;
END;
$$;

-- ============================================================
-- RECORD THE OUTCOME OF AN INSTALLATION
-- ============================================================
-- The client executes the staged DDL itself, so it reports back what happened. The outcome
-- is set once and never changes, which is why Status is a static knotted attribute; an
-- installation with no status row was rendered but never reported back on.

CREATE OR REPLACE PROCEDURE metadata._InstallationCompleted(RUN_ID VARCHAR, STATUS VARCHAR, ERROR VARCHAR DEFAULT NULL)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    il_id INT;
    ils_id TINYINT;
    now_ts TIMESTAMP_TZ := SYSDATE();
    bad_run_id EXCEPTION (-20001, 'Run id must be a GUID');
    no_installation EXCEPTION (-20009, 'No installation with that run id');
    bad_status EXCEPTION (-20010, 'Status must be Installed or Failed');
BEGIN
    IF (NOT metadata._IsRunId(:RUN_ID)) THEN RAISE bad_run_id; END IF;
    IF (:STATUS NOT IN ('Installed', 'Failed')) THEN RAISE bad_status; END IF;

    SELECT IL_RID_IL_ID INTO :il_id
    FROM metadata.IL_RID_Installation_RunId
    WHERE IL_RID_Installation_RunId = :RUN_ID;
    IF (il_id IS NULL) THEN RAISE no_installation; END IF;

    SELECT ILS_ID INTO :ils_id
    FROM metadata.ILS_InstallationStatus WHERE ILS_InstallationStatus = :STATUS;

    INSERT INTO metadata.IL_STA_Installation_Status (IL_STA_IL_ID, IL_STA_ILS_ID)
    VALUES (:il_id, :ils_id);

    IF (ERROR IS NOT NULL) THEN
        INSERT INTO metadata.IL_ERR_Installation_Error (IL_ERR_IL_ID, IL_ERR_Installation_Error)
        VALUES (:il_id, LEFT(:ERROR, 2000));
    END IF;

    RETURN :STATUS;
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
