-- sisula-snowflake deployment script
-- Creates the SISULATE JavaScript UDF and supporting objects

-- ============================================================
-- 1. Metadata-backed template CRUD stored procedure
-- ============================================================
CREATE OR REPLACE PROCEDURE SP_SISULA_TEMPLATE_CRUD(
    OPERATION   VARCHAR,
    TPL_NAME    VARCHAR,
    TPL_CONTENT VARCHAR
)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
AS $$
    var op = OPERATION ? OPERATION.toUpperCase() : '';
    var name = TPL_NAME;
    var content = TPL_CONTENT;

    if (op === 'UPSERT') {
        snowflake.createStatement({
            sqlText: 'CALL metadata._TemplateUpsert(?, ?)',
            binds: [name, content]
        }).execute();
        return 'OK';
    } else if (op === 'DELETE') {
        var deleteRs = snowflake.createStatement({
            sqlText: 'CALL metadata._TemplateDelete(?)',
            binds: [name]
        }).execute();
        if (deleteRs.next()) {
            return deleteRs.getColumnValue(1);
        }
        return 'OK';
    } else if (op === 'GET') {
        var rs = snowflake.createStatement({
            sqlText: 'SELECT TP_CNT_Template_Content FROM metadata.lTP_Template WHERE TP_NAM_Template_Name = ?',
            binds: [name]
        }).execute();
        if (rs.next()) {
            return rs.getColumnValue(1);
        }
        return null;
    } else if (op === 'LIST') {
        var sb = [];
        var rs = snowflake.createStatement({
            sqlText: 'SELECT TP_NAM_Template_Name, TP_CNT_ChangedAt FROM metadata.lTP_Template ORDER BY TP_NAM_Template_Name'
        }).execute();
        while (rs.next()) {
            sb.push(rs.getColumnValue(1) + ' | ' + rs.getColumnValue(2));
        }
        return sb.join('\n');
    }
    return 'ERROR: Unknown operation ' + op;
$$;

-- ============================================================
-- 2. Helper: render a template by name from metadata template storage
-- ============================================================
CREATE OR REPLACE PROCEDURE SP_SISULA_RENDER(
    TPL_NAME  VARCHAR,
    BINDINGS  VARCHAR
)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
AS $$
    var rs = snowflake.createStatement({
        sqlText: 'SELECT TP_CNT_Template_Content FROM metadata.lTP_Template WHERE TP_NAM_Template_Name = ?',
        binds: [TPL_NAME]
    }).execute();
    var template = null;
    if (rs.next()) {
        template = rs.getColumnValue(1);
    }
    if (!template) {
        return 'ERROR: Template not found: ' + TPL_NAME;
    }
    var sql = 'SELECT SISULATE(?, ?) AS RENDERED';
    var stmt = snowflake.createStatement({sqlText: sql, binds: [template, BINDINGS || '{}']});
    var result = stmt.execute();
    if (result.next()) {
        return result.getColumnValue(1);
    }
    return null;
$$;

-- ============================================================
-- 3. Core render function
-- ============================================================
CREATE OR REPLACE FUNCTION SISULATE(TEMPLATE VARCHAR, BINDINGS VARCHAR)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
AS $$
// __SISULA_JS_SOURCE__
return sisulate(TEMPLATE, BINDINGS);
$$;

-- ============================================================
-- 5. Grant access
-- ============================================================
GRANT USAGE ON FUNCTION SISULATE(VARCHAR, VARCHAR) TO PUBLIC;
GRANT USAGE ON PROCEDURE SP_SISULA_TEMPLATE_CRUD(VARCHAR, VARCHAR, VARCHAR) TO PUBLIC;
GRANT USAGE ON PROCEDURE SP_SISULA_RENDER(VARCHAR, VARCHAR) TO PUBLIC;
