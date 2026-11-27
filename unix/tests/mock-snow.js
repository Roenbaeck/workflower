// A stand-in for the Snowflake CLI, for tests that have no account (Node only; everything else is in mock-snowflake.js):
//   node mock-snow.js sql [-c NAME] [--role R] [--warehouse W] [--database D] [--schema S] --enable-templating NONE --format JSON -f FILE
// It prints what the CLI prints for the statement in FILE, a JSON array of row objects. The state (the tasks and the statements that
// were recorded) is kept between calls in the JSON file that the environment variable MOCK_SNOW_STATE names.
var fs = require('fs');
var mock = require('./mock-snowflake.js');

var argv = process.argv.slice(2);
var withValue = ['-c', '--connection', '--role', '--warehouse', '--database', '--schema', '--enable-templating', '--format'];
var file = null;
var i;
if (argv[0] !== 'sql') { console.error('mock-snow: only "sql" is supported'); process.exit(2); }
for (i = 1; i < argv.length; i++) {
  if (argv[i] === '-f') { file = argv[++i]; }
  else if (withValue.indexOf(argv[i]) >= 0) { i++; }
  else { console.error('mock-snow: unknown option ' + argv[i]); process.exit(2); }
}
if (!file) { console.error('mock-snow: no -f FILE'); process.exit(2); }

var statePath = process.env.MOCK_SNOW_STATE;
var state = (statePath && fs.existsSync(statePath)) ? JSON.parse(fs.readFileSync(statePath, 'utf8')) : mock.newState();
var code = 0;
try {
  console.log(JSON.stringify(mock.handleFile(state, fs.readFileSync(file, 'utf8'))));
} catch (e) {
  console.error(String(e.message));
  code = 1;
}
if (statePath) { fs.writeFileSync(statePath, JSON.stringify(state, null, 2)); }
process.exitCode = code;
