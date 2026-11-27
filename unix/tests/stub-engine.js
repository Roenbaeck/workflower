// A stub engine for testing the shell script's plumbing: it echoes its request in the format of PROTOCOL.md.
function enc(text) {
    var r = snowflake.execute({ sqlText: 'SELECT BASE64_ENCODE(?)', binds: [text] });
    r.next();
    return r.getColumnValue(1);
}
var request = JSON.parse(ARGS);
var keys = [];
for (var k in request) { keys.push(k); }
keys.sort();
var lines = ['STATUS ok'];
lines.push('TEXT ' + enc('op=' + OP + ' keys=' + keys.join(',') + ' database=' + (request.database || '') + ' schema=' + (request.schema || '')));
if (OP === 'plan' || OP === 'apply') { lines.push('STEPS 2'); }
if (OP === 'export') {
    lines.push('FILE A.B.C.json ' + enc('{"format":"workflower-graph"}\n'));
    lines.push('FILE A.B.C.d/task_1.sql ' + enc('SELECT 1\n'));
}
if (OP === 'check') { lines.push('TEXT ' + enc('error  X  something is wrong')); lines.push('EXIT 1'); }
if (OP === 'fail') { lines[0] = 'STATUS error'; lines[1] = 'TEXT ' + enc('this failed'); }
lines.push('JSON ' + enc(JSON.stringify({ op: OP, request: request })));
return enc(lines.join('\n'));
