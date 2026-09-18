/*
    STAGE RETENTION

    Snowflake has no expiry for staged files. Storage lifecycle policies apply to table
    rows, not to stages, so pruning has to be explicit.

    Two Snowflake limits shape this:

      LIST and REMOVE are both rejected inside a stored procedure ("Unsupported statement
      type 'LIST_FILES'" / "'REMOVE_FILES'"), so the prune cannot be a Snowflake task.
      Deletion is done by prune.ps1.

      DIRECTORY() is a table function and works anywhere, and it returns LAST_MODIFIED as a
      real timestamp rather than the RFC 1123 string LIST reports. That makes the view
      below exact, with no date parsing.

    The directory table on an internal stage does not refresh itself. prune.ps1 issues
    ALTER STAGE ... REFRESH before reading, so the refresh cost falls on the prune job
    rather than on every upload.

    Retention differs by area, because the three are worth different amounts:

      in/      the uploaded document. Redundant once the upsert succeeds, because the
               configuration itself is stored historized in the metadata model.
      out/     the SQL that was actually executed. This is the audit trail, kept longest.
      export/  reverse engineering output, already downloaded by the client.
*/

-- Idempotent: CREATE STAGE IF NOT EXISTS will not alter a stage made before directory
-- tables were enabled, so set it explicitly.
ALTER STAGE metadata.WORKFLOWER SET DIRECTORY = (ENABLE = TRUE);

-- What is on the stage and how old it is. Query this to decide a retention window, or to
-- find the rendered SQL for a past install.
CREATE OR REPLACE VIEW metadata.WORKFLOWER_STAGE_FILES AS
SELECT
    RELATIVE_PATH                                              AS PATH,
    SPLIT_PART(RELATIVE_PATH, '/', 1)                          AS AREA,
    SIZE                                                       AS BYTES,
    LAST_MODIFIED                                              AS LAST_MODIFIED,
    DATEDIFF('second', LAST_MODIFIED, CURRENT_TIMESTAMP()) / 86400.0 AS AGE_DAYS
FROM DIRECTORY(@metadata.WORKFLOWER);

COMMENT ON VIEW metadata.WORKFLOWER_STAGE_FILES IS
    'Workflower stage contents with age. Refresh with ALTER STAGE metadata.WORKFLOWER REFRESH first.';

/*
    Useful queries:

        ALTER STAGE metadata.WORKFLOWER REFRESH;

        -- How much is being kept, by area
        SELECT AREA, COUNT(*) AS FILES, SUM(BYTES) AS BYTES,
               MAX(AGE_DAYS) AS OLDEST_DAYS
        FROM metadata.WORKFLOWER_STAGE_FILES GROUP BY AREA;

        -- The oldest files
        SELECT PATH, LAST_MODIFIED, AGE_DAYS
        FROM metadata.WORKFLOWER_STAGE_FILES ORDER BY AGE_DAYS DESC LIMIT 20;

    Prune with:

        .\prune.ps1 <connection_name> -WhatIf
        .\prune.ps1 <connection_name>

    On the server, schedule prune.ps1 with Windows Task Scheduler. It cannot be a Snowflake
    task, because REMOVE is not permitted inside a stored procedure.
*/
