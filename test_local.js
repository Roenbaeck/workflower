// Quick local smoke test for sisula.js
var sisulate = require('./webapp/sisula.js');

function test(name, template, bindings, expected) {
    var result = sisulate(template, bindings);
    var pass = result === expected;
    console.log((pass ? 'PASS' : 'FAIL') + ': ' + name);
    if (!pass) {
        console.log('  Expected: ' + JSON.stringify(expected));
        console.log('  Got:      ' + JSON.stringify(result));
    }
    return pass;
}

var allPass = true;

// Test 1: Simple token
allPass = test('Simple token', 'Hello $name$!', '{"name":"World"}', 'Hello World!') && allPass;

// Test 2: Nested token
allPass = test('Nested token', 'By: $V.USER$ on $V.COMP$', '{"V":{"USER":"Lars","COMP":"Mac"}}', 'By: Lars on Mac') && allPass;

// Test 3: Foreach
allPass = test('Foreach', 
    '$/ foreach t in tables\n-- $t.table$\n$/ endfor',
    '{"tables":[{"table":"A"},{"table":"B"}]}',
    '-- A\n-- B\n') && allPass;

// Test 4: Foreach with order by
allPass = test('Foreach order by',
    '$/ foreach c in columns order by c.ordinal\n$c.name$\n$/ endfor',
    '{"columns":[{"ordinal":3,"name":"C"},{"ordinal":1,"name":"A"},{"ordinal":2,"name":"B"}]}',
    'A\nB\nC\n') && allPass;

// Test 5: Foreach with where
allPass = test('Foreach where',
    '$/ foreach c in columns where c.ordinal > 1\n$c.name$\n$/ endfor',
    '{"columns":[{"ordinal":1,"name":"A"},{"ordinal":2,"name":"B"},{"ordinal":3,"name":"C"}]}',
    'B\nC\n') && allPass;

// Test 6: If/else true
allPass = test('If/else true',
    '$/ if x\nYES\n$/ else\nNO\n$/ endif',
    '{"x":true}',
    'YES\n') && allPass;

// Test 7: If/else false
allPass = test('If/else false',
    '$/ if x\nYES\n$/ else\nNO\n$/ endif',
    '{"x":false}',
    'NO\n') && allPass;

// Test 8: Loop metadata
allPass = test('Loop metadata',
    '$/ foreach c in columns\n$c.index()$: $c.name$ $/ if c.first() (F) $/ endif $/ if c.last() (L) $/ endif\n$/ endfor',
    '{"columns":[{"name":"A"},{"name":"B"},{"name":"C"}]}',
    '0: A (F) \n1: B \n2: C (L) \n') && allPass;

// Test 9: Inline if - trailing whitespace preserved per spec
allPass = test('Inline if',
    '$/ foreach c in cols\nCol $c.name$ $/ if c.active Active $/ else Inactive $/ endif\n$/ endfor',
    '{"cols":[{"name":"id","active":true},{"name":"del","active":false}]}',
    'Col id Active \nCol del Inactive \n') && allPass;

// Test 10: Comments
allPass = test('Line comment',
    '$- hidden\nvisible',
    '{}',
    'visible') && allPass;

// Test 11: Inline comment
allPass = test('Inline comment',
    'A $- comment -$ B',
    '{}',
    'A  B') && allPass;

// Test 12: Block mode - leading newline from /*~\n is expected
allPass = test('Block mode',
    'PREFIX /*~\n$/ foreach t in tables\n-- $t.table$\n$/ endfor\n~*/ SUFFIX',
    '{"tables":[{"table":"A"},{"table":"B"}]}',
    'PREFIX \n-- A\n-- B\n SUFFIX') && allPass;

// Test 13: contains()
allPass = test('contains()',
    '$/ foreach c in columns\n$/ if contains(c.type,"char")\n$c.name$\n$/ endif\n$/ endfor',
    '{"columns":[{"name":"id","type":"int"},{"name":"code","type":"char(20)"}]}',
    'code\n') && allPass;

// Test 14: and/or
allPass = test('and/or',
    '$/ foreach item in items where item.price > 50 and item.category == "electronics"\n$item.name$\n$/ endfor',
    '{"items":[{"name":"Laptop","price":999,"category":"electronics"},{"name":"Mouse","price":25,"category":"electronics"}]}',
    'Laptop\n') && allPass;

// Test 15: Bracket indexing
allPass = test('Bracket index',
    'First: $tables[0].table$, Second: $tables[1].table$',
    '{"tables":[{"table":"A"},{"table":"B"}]}',
    'First: A, Second: B') && allPass;

// Test 16: Inline if with OR (from the original test)
allPass = test('Inline IF OR',
    '$/ foreach c in columns\n-- Found ordinal $c.ordinal$ $/ if c.type = "untyped" or c.type == "varchar(1000) null" with expected type $/ endif\n$/ endfor',
    '{"columns":[{"ordinal":10,"name":"b","type":"untyped"}]}',
    '-- Found ordinal 10 with expected type \n') && allPass;

// Test 17: endswith / startswith
allPass = test('startswith',
    '$/ if startswith(name,"test")\nMATCH\n$/ endif',
    '{"name":"test_table"}',
    'MATCH\n') && allPass;

allPass = test('endswith',
    '$/ if endswith(name,"_table")\nMATCH\n$/ endif',
    '{"name":"test_table"}',
    'MATCH\n') && allPass;

// Test 18: count() token
allPass = test('count token',
    '$/ foreach t in tables\nCount: $t.count()$\n$/ endfor',
    '{"tables":[{"table":"A"},{"table":"B"}]}',
    'Count: 2\nCount: 2\n') && allPass;

// Test 19: Nested loops
allPass = test('Nested loops',
    '$/ foreach t in tables\n$/ foreach c in t.columns\n$t.table$.$c.name$\n$/ endfor\n$/ endfor',
    '{"tables":[{"table":"T1","columns":[{"name":"C1"},{"name":"C2"}]}]}',
    'T1.C1\nT1.C2\n') && allPass;

// Test 20: SQL literal token doubles single quotes
allPass = test('SQL literal quote',
    'COMMENT = $\'d\'$', '{"d":"O\'Brien"}', "COMMENT = 'O''Brien'") && allPass;

// Test 21: SQL literal token escapes newline, backslash and dollar
allPass = test('SQL literal newline',
    '$\'d\'$', '{"d":"line1\\nline2"}', "'line1\\nline2'") && allPass;
allPass = test('SQL literal backslash',
    '$\'d\'$', '{"d":"a\\\\b"}', "'a\\\\b'") && allPass;
allPass = test('SQL literal dollar',
    '$\'d\'$', '{"d":"a$b"}', "'a\\x24b'") && allPass;

// Test 22: missing path yields an empty literal, keeping the SQL valid
allPass = test('SQL literal missing path',
    'COMMENT = $\'nope\'$', '{}', "COMMENT = ''") && allPass;

// Test 23: comment token flattens to one line and splits adjacent dollars
allPass = test('Comment token newline',
    '-- $|d|$', '{"d":"line1\\nline2"}', '-- line1 line2') && allPass;
allPass = test('Comment token dollars',
    '-- $|d|$', '{"d":"a$$b"}', '-- a$ $b') && allPass;

// Test 24: a rendered value is never rescanned for tokens
allPass = test('No rescan of rendered dollars',
    '$|d|$ and $name$', '{"d":"$name$","name":"Bob"}', '$name$ and Bob') && allPass;

console.log('\n' + (allPass ? 'ALL TESTS PASSED' : 'SOME TESTS FAILED'));
