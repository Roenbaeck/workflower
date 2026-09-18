-- Snowflake test: nested inline IF with OR and = alias
SELECT SISULATE(
    '$/ foreach c in columns\n$/ if c.ordinal == 10\n-- Found the 10th ordinal $/ if c.type = "untyped" or c.type == "varchar(1000) null" with expected type $/ endif\n$/ endif\n$/ endfor',
    '{"columns": [{"ordinal": 9, "name": "a", "type": "int"}, {"ordinal": 10, "name": "b", "type": "untyped"}, {"ordinal": 11, "name": "c", "type": "varchar(1000) null"}]}'
) AS test_nested_inline_if;
