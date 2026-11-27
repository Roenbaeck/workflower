#!/bin/sh
# Tests of the shell script's own work, with no Snowflake: a canned `snow` (tests/fake-snow/snow-canned) returns the answer that
# each test makes, so what is checked is how the script builds a request, decodes an answer, writes files and exits. It runs on
# macOS and Linux (CI does both), where `base64` differs (GNU wraps lines and decodes with -d; BSD does not and may need -D).
#
#   sh unix/tests/test-shell.sh

here=$(cd "$(dirname "$0")" && pwd)
script=$here/../workflower
export WORKFLOWER_SNOW=$here/fake-snow/snow-canned
export WORKFLOWER_ENGINE=$here/stub-engine.js
export WORKFLOWER_CONNECTION=test
work=$(mktemp -d "${TMPDIR:-/tmp}/wf-test.XXXXXX")
trap 'rm -rf "$work"' EXIT

passed=0
failed=0
ok() { passed=$((passed + 1)); printf '  ok    %s\n' "$1"; }
fail() { failed=$((failed + 1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
check() { # check NAME EXPECTED ACTUAL
    if [ "$2" = "$3" ]; then ok "$1"; else fail "$1" "expected [$2] but got [$3]"; fi
}

enc() { printf '%s' "$1" | base64 | tr -d '\n\r'; }

# canned LINES...: the answer of the engine (one argument for each line, base64 where the protocol says so is the caller's job)
canned() {
    body=
    for line in "$@"; do
        if [ -z "$body" ]; then body=$line; else body="$body
$line"; fi
    done
    CANNED_ANSWER_B64=$(printf '%s' "$body" | base64 | tr -d '\n\r')
    export CANNED_ANSWER_B64
}

run() { # run ARGS...: output in $work/out, errors in $work/err, code in $code
    code=0
    sh "$script" "$@" >"$work/out" 2>"$work/err" || code=$?
}

echo 'Answers'
canned 'STATUS ok' "TEXT $(enc 'hello world')" "JSON $(enc '{"a":1}')"
run graphs -d DB
check 'a text is printed' 'hello world' "$(cat "$work/out")"
check 'the exit code is 0' 0 "$code"
run graphs -d DB --json
check 'the JSON is printed with --json' 'hello world
{"a":1}' "$(cat "$work/out")"

canned 'STATUS ok' "TEXT $(enc 'line one
line two
')" "TEXT $(enc 'second')"
run graphs -d DB
check 'a multi-line text, and a text that ends with a line break, are printed as they are' 'line one
line two
second' "$(cat "$work/out")"

canned 'STATUS ok' "TEXT $(enc "quote ' double \" backslash \\ dollar \$ caf$(printf '\303\251')")"
run graphs -d DB
check 'quotes, backslash, dollar and a non-ASCII letter survive' "quote ' double \" backslash \\ dollar \$ caf$(printf '\303\251')" "$(cat "$work/out")"

canned 'STATUS error' "TEXT $(enc 'it went wrong')"
run graphs -d DB
check 'an error goes to stderr' 'it went wrong' "$(cat "$work/err")"
check 'and nothing to stdout' '' "$(cat "$work/out")"
check 'and the exit code is 1' 1 "$code"

canned 'STATUS ok' "TEXT $(enc 'found a problem')" 'EXIT 1'
run graphs -d DB
check 'EXIT sets the exit code' 1 "$code"

echo 'Files'
canned 'STATUS ok' "FILE a.b.json $(enc '{"x": 1}
')" "FILE a.b.d/task_1.sql $(enc 'SELECT 1;
')"
run export -d DB -s S -o "$work/out1"
check 'a file is written' '{"x": 1}' "$(cat "$work/out1/a.b.json")"
check 'and one in a folder' 'SELECT 1;' "$(cat "$work/out1/a.b.d/task_1.sql")"
run export -d DB -s S -o "$work/out1"
check 'files are not overwritten' 2 "$code"
run export -d DB -s S -o "$work/out1" --force
check 'unless --force' 0 "$code"
run export -d DB -s S
check 'a folder is needed' 64 "$code"
for bad in '../evil.sql' '/etc/evil' '.hidden' 'a/b/c.sql' 'sp ace.sql'; do
    canned 'STATUS ok' "FILE $bad $(enc 'x')"
    run export -d DB -s S -o "$work/out2"
    check "the file name '$bad' is refused" 2 "$code"
done
check 'and nothing was written outside' 'no' "$([ -e "$work/evil.sql" ] && echo yes || echo no)"

echo 'Requests'
canned 'STATUS ok' 'STEPS 0' "TEXT $(enc 'nothing to change')"
printf '{"format":"workflower-graph","tasks":[{"name":"A","definitionFile":"A.d/x y.sql"}]}\n' >"$work/g.json"
mkdir -p "$work/A.d"
printf 'SELECT 1\n' >"$work/A.d/x y.sql"
run plan "$work/g.json" -d 'My "DB"' --warehouse WH
check 'plan of a file works' 0 "$code"
check 'and says which file' "== $work/g.json
nothing to change" "$(cat "$work/out")"
run plan "$work/g.json" "$work/g.json"
check 'two files are two requests' 2 "$(grep -c '^== ' "$work/out")"
run plan
check 'a file is needed for plan' 64 "$code"
run plan "$work/nothere.json"
check 'a file that is not there is refused' 64 "$code"
printf '{"tasks":[{"name":"A","definitionFile":"../secret.sql"}]}\n' >"$work/h.json"
run plan "$work/h.json"
check 'a definitionFile that leaves the folder is refused' 64 "$code"
run frobnicate
check 'an unknown command is refused' 64 "$code"
run graphs
check 'graphs needs a database' 64 "$code"
run runs -d D -s S
check 'runs needs a root' 64 "$code"
run runs -d D -s S -r R --hours abc
check 'hours must be a number' 64 "$code"
run help
check 'help works' 0 "$code"

echo 'Apply'
canned 'STATUS ok' 'STEPS 3' "TEXT $(enc 'the plan')"
run apply "$work/g.json" -y
check 'apply -y runs without asking' 0 "$code"
run apply "$work/g.json" </dev/null
check 'apply without an answer does not apply' 'yes' "$(grep -q 'not applied' "$work/out" && echo yes || echo no)"

echo 'View'
canned 'STATUS ok' "TEXT $(enc '1 graphs')" "JSON $(enc '{"session":{},"graphs":[],"runs":{}}')"
run view -d DB -o "$work/viewer" --no-open
check 'view works' 0 "$code"
check 'the data is wrapped for the page' 'window.WORKFLOWER_DATA = {"session":{},"graphs":[],"runs":{}};' "$(cat "$work/viewer/data.js")"
check 'the page is copied' 'yes' "$([ -f "$work/viewer/index.html" ] && [ -f "$work/viewer/app.js" ] && echo yes || echo no)"
check 'but not the self-test' 'no' "$([ -e "$work/viewer/selftest.js" ] && echo yes || echo no)"
canned 'STATUS ok' "TEXT $(enc 'no json here')"
run view -d DB -o "$work/viewer2" --no-open
check 'view without data from the engine fails' 2 "$code"
run view
check 'view needs a database' 64 "$code"

echo 'snow fails'
export CANNED_FAIL=1
run graphs -d DB
check 'a failing snow gives exit 2' 2 "$code"
unset CANNED_FAIL

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
