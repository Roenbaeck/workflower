-- Snowflake test: escaping token forms.
--
-- $'path'$ renders a quoted SQL string literal; $|path|$ renders text that is safe on one
-- SQL comment line. Expected values are built from CHAR(39) (single quote) and CHAR(92)
-- (backslash) rather than written as escaped literals, so the expectation is unambiguous.
--
-- Unlike the other files in this directory these are assertions: look for the STATUS
-- column. Any row reading FAIL is a regression.

WITH t AS (
    SELECT 'literal: single quote is doubled' AS NAME,
           SISULATE('COMMENT = $''d''$', '{"d":"O''Brien"}') AS ACTUAL,
           'COMMENT = ' || CHAR(39) || 'O' || REPEAT(CHAR(39), 2) || 'Brien' || CHAR(39) AS EXPECTED
    UNION ALL
    SELECT 'literal: newline becomes an escape',
           SISULATE('$''d''$', '{"d":"line1\\nline2"}'),
           CHAR(39) || 'line1' || CHAR(92) || 'nline2' || CHAR(39)
    UNION ALL
    SELECT 'literal: backslash is doubled',
           SISULATE('$''d''$', '{"d":"a\\\\b"}'),
           CHAR(39) || 'a' || REPEAT(CHAR(92), 2) || 'b' || CHAR(39)
    UNION ALL
    SELECT 'literal: dollar becomes hex escape',
           SISULATE('$''d''$', '{"d":"a$b"}'),
           CHAR(39) || 'a' || CHAR(92) || 'x24b' || CHAR(39)
    UNION ALL
    SELECT 'literal: missing path stays valid SQL',
           SISULATE('COMMENT = $''nope''$', '{}'),
           'COMMENT = ' || REPEAT(CHAR(39), 2)
    UNION ALL
    SELECT 'comment: newline is flattened',
           SISULATE('-- $|d|$', '{"d":"line1\\nline2"}'),
           '-- line1 line2'
    UNION ALL
    SELECT 'comment: adjacent dollars are separated',
           SISULATE('-- $|d|$', '{"d":"a$$b"}'),
           '-- a$ $b'
    UNION ALL
    SELECT 'rendered values are not rescanned for tokens',
           SISULATE('$|d|$ and $name$', '{"d":"$name$","name":"Bob"}'),
           '$name$ and Bob'
    UNION ALL
    SELECT 'plain tokens are unchanged',
           SISULATE('Hello, $name$!', '{"name":"World"}'),
           'Hello, World!'
)
SELECT NAME,
       CASE WHEN ACTUAL = EXPECTED THEN 'PASS' ELSE 'FAIL' END AS STATUS,
       ACTUAL,
       EXPECTED
FROM t
ORDER BY STATUS, NAME;
