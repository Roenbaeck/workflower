/*
    CREATE CONFIGURATION AND TEMPLATE MANAGEMENT PROCEDURES

    Store and manage workflow JSON definitions and Sisula templates
    in the metadata model.
*/

-- ============================================================
-- UPSERT CONFIGURATION
-- ============================================================

DROP PROCEDURE IF EXISTS metadata._ConfigurationUpsert(VARCHAR, VARCHAR, VARCHAR);

CREATE OR REPLACE PROCEDURE metadata._ConfigurationUpsert(
    CONFIG_NAME VARCHAR,
    CONFIG_CONTENT VARCHAR,
    CONFIG_TYPE VARCHAR DEFAULT 'Workflow',
    TEMPLATE_NAME VARCHAR DEFAULT 'CreateTaskGraph'
)
RETURNS INT
LANGUAGE SQL
AS
$$
BEGIN
    LET cf_id INT;
    LET cft_id TINYINT;
    LET tp_id INT;
    LET now_ts TIMESTAMP_TZ := SYSDATE();

    -- Look up configuration type knot
    SELECT CFT_ID INTO :cft_id FROM metadata.CFT_ConfigurationType WHERE CFT_ConfigurationType = :CONFIG_TYPE;

    IF (:TEMPLATE_NAME IS NOT NULL) THEN
        SELECT tp.TP_ID INTO :tp_id
        FROM metadata.TP_Template tp
        JOIN metadata.TP_NAM_Template_Name nam ON nam.TP_NAM_TP_ID = tp.TP_ID
        WHERE nam.TP_NAM_Template_Name = :TEMPLATE_NAME;
    END IF;

    -- Find existing configuration by name
    SELECT cf.CF_ID INTO :cf_id
    FROM metadata.CF_Configuration cf
    JOIN metadata.CF_NAM_Configuration_Name nam ON nam.CF_NAM_CF_ID = cf.CF_ID
    WHERE nam.CF_NAM_Configuration_Name = :CONFIG_NAME;

    IF (:cf_id IS NULL) THEN
        -- Create new configuration
        SELECT metadata.CF_Configuration_ID_SEQ.NEXTVAL INTO :cf_id;
        INSERT INTO metadata.CF_Configuration (CF_ID) VALUES (:cf_id);

        INSERT INTO metadata.CF_NAM_Configuration_Name (CF_NAM_CF_ID, CF_NAM_Configuration_Name)
        VALUES (:cf_id, :CONFIG_NAME);

        INSERT INTO metadata.CF_TYP_Configuration_Type (CF_TYP_CF_ID, CF_TYP_CFT_ID)
        VALUES (:cf_id, :cft_id);

        INSERT INTO metadata.CF_CNT_Configuration_Content (CF_CNT_CF_ID, CF_CNT_Configuration_Content, CF_CNT_ChangedAt)
        VALUES (:cf_id, :CONFIG_CONTENT, :now_ts);
    ELSE
        -- Update content (historized: insert new version)
        INSERT INTO metadata.CF_CNT_Configuration_Content (CF_CNT_CF_ID, CF_CNT_Configuration_Content, CF_CNT_ChangedAt)
        VALUES (:cf_id, :CONFIG_CONTENT, :now_ts);
    END IF;

    IF (:tp_id IS NOT NULL) THEN
        DELETE FROM metadata.CF_uses_TP_template WHERE CF_ID_uses = :cf_id;
        INSERT INTO metadata.CF_uses_TP_template (CF_ID_uses, TP_ID_template)
        VALUES (:cf_id, :tp_id);
    END IF;

    RETURN :cf_id;
END;
$$;

-- ============================================================
-- UPSERT TEMPLATE
-- ============================================================

CREATE OR REPLACE PROCEDURE metadata._TemplateUpsert(
    TEMPLATE_NAME VARCHAR,
    TEMPLATE_CONTENT VARCHAR
)
RETURNS INT
LANGUAGE SQL
AS
$$
BEGIN
    LET tp_id INT;
    LET now_ts TIMESTAMP_TZ := SYSDATE();

    SELECT tp.TP_ID INTO :tp_id
    FROM metadata.TP_Template tp
    JOIN metadata.TP_NAM_Template_Name nam ON nam.TP_NAM_TP_ID = tp.TP_ID
    WHERE nam.TP_NAM_Template_Name = :TEMPLATE_NAME;

    IF (:tp_id IS NULL) THEN
        SELECT metadata.TP_Template_ID_SEQ.NEXTVAL INTO :tp_id;
        INSERT INTO metadata.TP_Template (TP_ID) VALUES (:tp_id);

        INSERT INTO metadata.TP_NAM_Template_Name (TP_NAM_TP_ID, TP_NAM_Template_Name)
        VALUES (:tp_id, :TEMPLATE_NAME);
    END IF;

    INSERT INTO metadata.TP_CNT_Template_Content (TP_CNT_TP_ID, TP_CNT_Template_Content, TP_CNT_ChangedAt)
    VALUES (:tp_id, :TEMPLATE_CONTENT, :now_ts);

    RETURN :tp_id;
END;
$$;

-- ============================================================
-- GET TEMPLATE
-- ============================================================

CREATE OR REPLACE PROCEDURE metadata._TemplateGet(
    TEMPLATE_NAME VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    LET result VARCHAR;

    SELECT TP_CNT_Template_Content INTO :result
    FROM metadata.lTP_Template
    WHERE TP_NAM_Template_Name = :TEMPLATE_NAME;

    RETURN :result;
END;
$$;

-- ============================================================
-- LIST TEMPLATES
-- ============================================================

CREATE OR REPLACE PROCEDURE metadata._TemplateList()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    LET result VARCHAR DEFAULT '';

    SELECT LISTAGG(TP_NAM_Template_Name || ' | ' || TP_CNT_ChangedAt, '\n')
    INTO :result
    FROM metadata.lTP_Template
    GROUP BY 1=1;

    RETURN :result;
END;
$$;

-- ============================================================
-- DELETE TEMPLATE
-- ============================================================

CREATE OR REPLACE PROCEDURE metadata._TemplateDelete(
    TEMPLATE_NAME VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    LET tp_id INT;

    SELECT tp.TP_ID INTO :tp_id
    FROM metadata.TP_Template tp
    JOIN metadata.TP_NAM_Template_Name nam ON nam.TP_NAM_TP_ID = tp.TP_ID
    WHERE nam.TP_NAM_Template_Name = :TEMPLATE_NAME;

    IF (:tp_id IS NULL) THEN
        RETURN 'Not found: ' || :TEMPLATE_NAME;
    END IF;

    DELETE FROM metadata.CF_uses_TP_template WHERE TP_ID_template = :tp_id;
    DELETE FROM metadata.TP_CNT_Template_Content WHERE TP_CNT_TP_ID = :tp_id;
    DELETE FROM metadata.TP_NAM_Template_Name WHERE TP_NAM_TP_ID = :tp_id;
    DELETE FROM metadata.TP_Template WHERE TP_ID = :tp_id;

    RETURN 'Deleted: ' || :TEMPLATE_NAME;
END;
$$;

-- ============================================================
-- GET CONFIGURATION
-- ============================================================

CREATE OR REPLACE PROCEDURE metadata._ConfigurationGet(
    CONFIG_NAME VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    LET result VARCHAR;

    SELECT CF_CNT_Configuration_Content INTO :result
    FROM metadata.lCF_Configuration
    WHERE CF_NAM_Configuration_Name = :CONFIG_NAME;

    RETURN :result;
END;
$$;

-- ============================================================
-- LIST CONFIGURATIONS
-- ============================================================

CREATE OR REPLACE PROCEDURE metadata._ConfigurationList()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    LET result VARCHAR DEFAULT '';

    SELECT LISTAGG(CF_NAM_Configuration_Name || ' | ' || CF_TYP_CFT_ConfigurationType || ' | ' || CF_CNT_ChangedAt, '\n')
    INTO :result
    FROM metadata.lCF_Configuration
    GROUP BY 1=1;

    RETURN :result;
END;
$$;

-- ============================================================
-- DELETE CONFIGURATION
-- ============================================================

CREATE OR REPLACE PROCEDURE metadata._ConfigurationDelete(
    CONFIG_NAME VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    LET cf_id INT;

    SELECT cf.CF_ID INTO :cf_id
    FROM metadata.CF_Configuration cf
    JOIN metadata.CF_NAM_Configuration_Name nam ON nam.CF_NAM_CF_ID = cf.CF_ID
    WHERE nam.CF_NAM_Configuration_Name = :CONFIG_NAME;

    IF (:cf_id IS NULL) THEN
        RETURN 'Not found: ' || :CONFIG_NAME;
    END IF;

    DELETE FROM metadata.CF_uses_TP_template WHERE CF_ID_uses = :cf_id;
    DELETE FROM metadata.CF_CNT_Configuration_Content WHERE CF_CNT_CF_ID = :cf_id;
    DELETE FROM metadata.CF_TYP_Configuration_Type WHERE CF_TYP_CF_ID = :cf_id;
    DELETE FROM metadata.CF_NAM_Configuration_Name WHERE CF_NAM_CF_ID = :cf_id;
    DELETE FROM metadata.TR_formed_CF_from WHERE CF_ID_from = :cf_id;
    DELETE FROM metadata.CF_Configuration WHERE CF_ID = :cf_id;

    RETURN 'Deleted: ' || :CONFIG_NAME;
END;
$$;
