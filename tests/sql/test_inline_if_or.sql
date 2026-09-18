-- Snowflake test: inline IF with OR operator
SELECT SISULATE(
    '$/ foreach c in columns\n-- Found ordinal $c.ordinal$ $/ if c.type = "untyped" or c.type == "varchar(1000) null" with expected type $/ endif\n$/ endfor',
    '{"columns":[{"ordinal": 10, "name": "b", "type": "untyped"}]}'
) AS test_inline_if_or;
