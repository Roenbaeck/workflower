-- Snowflake test: contains() function
SELECT SISULATE(
    '$/ foreach c in columns\n$/ if contains(c.type, "char")\n-- Column $c.name$ is character-based (type: $c.type$)\n$/ endif\n$/ endfor',
    '{"columns": [{"name": "id", "type": "int not null"}, {"name": "name", "type": "varchar(100) null"}, {"name": "code", "type": "char(20) null"}, {"name": "amount", "type": "decimal(10,2) null"}, {"name": "description", "type": "nvarchar(max) null"}]}'
) AS test_contains;
