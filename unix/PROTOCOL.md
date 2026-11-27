# The macOS and Linux version: protocol between the shell script and the engine

The PowerShell module in `Workflower/` is the Windows version. On macOS and Linux the only things that can be relied on are a POSIX
shell, the usual tools (`sed`, `tr`, `grep`, `base64`, `mktemp`) and the Snowflake CLI (`snow`). A shell script cannot parse JSON or
plan a change, so the logic runs **inside Snowflake**, as an anonymous JavaScript procedure that creates nothing:

```sql
WITH wf AS PROCEDURE (OP VARCHAR, ARGS VARCHAR) RETURNS VARCHAR LANGUAGE JAVASCRIPT AS
$$ <the text of engine.js> $$
CALL wf('plan', '<json>');
```

`unix/workflower` (the shell script) builds that statement into a temporary file, runs it with `snow sql -f <file> --format json`,
takes the one value of the one row, decodes it and acts on it. `unix/engine.js` is the body of the procedure. It runs with the rights of
the caller, so it sees and may change exactly what the user may.

## What the engine is

`engine.js` is plain **ES5** (no `let`, `const`, arrow functions, template strings; it is tested under Jint 2.11 as well as in Snowflake),
ASCII only, and must not contain two dollar signs in a row anywhere (they end the procedure body). It reads the procedure arguments
`OP` and `ARGS` (Snowflake makes JavaScript argument names upper case), does the work, and `return`s the answer as below.
All access to Snowflake goes through `snowflake.execute({sqlText: ..., binds: [...]})`.

It is the same logic as the PowerShell module (read it: `Workflower/Private/*.ps1`, `Workflower/Public/*.ps1`; the tests
`tests/Test-Offline.ps1` and `tests/Test-Live.ps1` state the behaviour). The plan for the same graphs must be **the same steps with the
same SQL text**; a script compares the two (`unix/tests/Compare-Engines.ps1`).

## The answer

The return value is **one base64 string** (standard alphabet, no line breaks, at least 24 characters) of the UTF-8 text of an answer in
lines. Each line is `KEYWORD`, a space, and the rest:

| line | meaning |
|---|---|
| `STATUS ok` or `STATUS error` | first line, always. `error` means the request failed; the first `TEXT` says why |
| `STEPS <n>` | for `plan` and `apply`: the number of steps in the plan (0 when there is nothing to change); the shell script uses it to decide whether to ask before applying |
| `EXIT <n>` | optional; the exit code for the shell script (default 0 for ok, 1 for error); 1 when a check finds an error |
| `TEXT <base64>` | a piece of text for a person, base64 of UTF-8; the texts are printed in order, each followed by a line break unless it ends with one |
| `JSON <base64>` | the machine readable result (one line of JSON); printed only with `--json` |
| `FILE <path> <base64>` | a file to write, relative to the output directory; `<path>` is only letters, digits, `_`, `.`, `-`, and at most one `/` (a folder and a file name), never starting with a dot |

Exceptions inside the engine are caught and become `STATUS error` and a `TEXT`; a procedure error that escapes is shown by `snow`.

## The request

`OP` is the operation; `ARGS` is a JSON object (the shell builds it with `printf`, so it holds only simple strings, numbers, booleans and
base64 text). Names that are not given are not sent. `database`, `schema`, `root` are exact Snowflake names.

| OP | ARGS | does |
|---|---|---|
| `graphs` | `database`, `schema` (optional), `root` (optional), `parameters` (bool, default false) | reads graphs (`SHOW TASKS`, and `SHOW PARAMETERS IN TASK` when `parameters`); TEXT: a table (root, state, tasks, schema; `!` for an incomplete graph); JSON: `{"graphs":[graph]}` |
| `export` | `database`, `schema`, `root` (optional), `split` (bool), `noState` (bool) | reads graphs with parameters; one `FILE <db>.<schema>.<root>.json` per graph (the file format of the README; with `split`, each task's SQL in `FILE <db>.<schema>.<root>.d/<task>.sql` and `definitionFile` in the JSON); TEXT: what was made |
| `check` | the input (below) | the problems of each graph; TEXT: one line per problem (`error`, `warning` or `info`, the task, the message), or `no problems`; JSON: `{"problems":[...]}`; `EXIT 1` if there is an error |
| `sql` | the input | TEXT: the script (`ConvertTo-TaskGraphSql -AsScript -IncludeState`) |
| `plan` | the input | reads the installed graph, TEXT: the steps in order (phase, reason and the SQL), or `nothing to change`; JSON: the plan; `EXIT 1` if the graph has errors (no plan is made) |
| `apply` | the input | plan, then runs the steps one by one (as `Publish-TaskGraph`); TEXT: what was done; on a failed step `STATUS error` and the message that says which steps were done |
| `operate` | `database`, `schema`, `root`, `action` = `resume`, `suspend`, `run` or `retry` | as `Resume-TaskGraph`, `Suspend-TaskGraph`, `Start-TaskGraph [-Retry]`; TEXT: what was done |
| `runs` | `database`, `schema`, `root`, `hours` (default 24), `limit` (default 20) | as `Get-TaskGraphRun`; TEXT: a table of runs and, for the failed tasks, the error; JSON: the runs |

The **input** of `check`, `sql`, `plan` and `apply` is a graph file:

- `doc`: the base64 of the UTF-8 text of the graph file (`{"format":"workflower-graph","version":1,"database":...,"schema":...,"tasks":[...]}`);
- `files`: an object that maps each `definitionFile` named in the document to the base64 of that file's text (the shell reads them);
- `database`, `schema`, `warehouse` (optional): replace the file's database and schema, and the warehouse of every task that has one
  (`Import-TaskGraph -Database -Schema -Warehouse`).

A task field that is not one of the known fields is an error (`STATUS error`, naming the field), as in `Import-TaskGraph`.

## Text of the answers

Plain text for a terminal, width-agnostic, ASCII (names from Snowflake may be anything). A plan reads like

```
Graph ETL.LOAD.LOAD_ROOT: 3 steps
  1. suspend  LOAD_ROOT   The root is suspended while the graph is changed.
       ALTER TASK "ETL"."LOAD"."LOAD_ROOT" SUSPEND
  2. alter    LOAD_A      Task 'LOAD_A': the definition is changed.
       ALTER TASK ...
```

and `apply` prints the same plan and then `done: 3 steps` (or the failure).
