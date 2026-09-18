-- Snowflake test: sisula renderer basic functionality
-- Usage: Run the SELECT statements below to test the SISULATE function

-- Test 1: Simple token expansion
SELECT SISULATE(
    'Hello, $name$!',
    '{"name": "World"}'
) AS test1;

-- Test 2: Nested token expansion
SELECT SISULATE(
    '-- Generated: $VARIABLES.GENERATED_AT$ -- By: $VARIABLES.USERNAME$',
    '{"VARIABLES": {"GENERATED_AT": "2025-11-04T15:56:00Z", "USERNAME": "Lars"}}'
) AS test2;

-- Test 3: Foreach loop
SELECT SISULATE(
    '$/ foreach t in tables\n-- Table: $t.table$\n$/ endfor',
    '{"tables": [{"table": "EMPLOYMENT"}, {"table": "CLASS"}, {"table": "DOCUMENT_TYPE"}]}'
) AS test3;

-- Test 4: Foreach with order by
SELECT SISULATE(
    '$/ foreach c in columns order by c.ordinal\n-- $c.ordinal$: $c.name$\n$/ endfor',
    '{"columns": [{"ordinal": 3, "name": "C"}, {"ordinal": 1, "name": "A"}, {"ordinal": 2, "name": "B"}]}'
) AS test4;

-- Test 5: Foreach with where
SELECT SISULATE(
    '$/ foreach c in columns where c.ordinal > 1\n-- $c.name$ (ordinal $c.ordinal$)\n$/ endfor',
    '{"columns": [{"ordinal": 1, "name": "A"}, {"ordinal": 2, "name": "B"}, {"ordinal": 3, "name": "C"}]}'
) AS test5;

-- Test 6: If/else block
SELECT SISULATE(
    '$/ if enabled\n-- Enabled!\n$/ else\n-- Disabled\n$/ endif',
    '{"enabled": true}'
) AS test6_true;

SELECT SISULATE(
    '$/ if enabled\n-- Enabled!\n$/ else\n-- Disabled\n$/ endif',
    '{"enabled": false}'
) AS test6_false;

-- Test 7: Loop metadata (index, first, last)
SELECT SISULATE(
    '$/ foreach c in columns\n-- $c.index()$: $c.name$ $/ if c.first() (FIRST) $/ endif $/ if c.last() (LAST) $/ endif\n$/ endfor',
    '{"columns": [{"name": "A"}, {"name": "B"}, {"name": "C"}]}'
) AS test7;

-- Test 8: Inline if
SELECT SISULATE(
    '$/ foreach c in columns\nColumn $c.name$ $/ if c.active Active $/ else Inactive $/ endif\n$/ endfor',
    '{"columns": [{"name": "id", "active": true}, {"name": "deleted", "active": false}]}'
) AS test8;

-- Test 9: Comments
SELECT SISULATE(
    '$- this line is a comment\nVisible line\n$- another comment\nMore visible',
    '{}'
) AS test9;

-- Test 10: Inline comments
SELECT SISULATE(
    'This is $- a comment -$ visible text',
    '{}'
) AS test10;

-- Test 11: Block mode with /*~ ... ~*/
SELECT SISULATE(
    'PREFIX /*~\n$/ foreach t in tables\n-- $t.table$\n$/ endfor\n~*/ SUFFIX',
    '{"tables": [{"table": "A"}, {"table": "B"}]}'
) AS test11;

-- Test 12: Bracket indexing in paths
SELECT SISULATE(
    'First column: $tables[0].table$, Second column: $tables[1].table$',
    '{"tables": [{"table": "EMPLOYMENT"}, {"table": "CLASS"}]}'
) AS test12;

-- Test 13: SNOWFLAKE block → sisula blocks
SELECT SISULATE(
    'PREFIX /*~$/ if enabled\n-- BLOCK A\n$/ else\n-- BLOCK B\n$/ endif~*/ SUFFIX',
    '{"enabled": true}'
) AS test13;
