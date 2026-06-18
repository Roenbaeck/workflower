Here is my analysis and proposed plan for porting `sisula-mssql` to Snowflake.

---

## Feasibility: Yes, it's doable — and actually simpler

The port is not only feasible, but several aspects become **simpler** than the SQL Server CLR version. The main reason: JavaScript UDFs have native JSON parsing and string manipulation, eliminating the "context connection" hack that the CLR uses to delegate JSON operations back to SQL Server.

---

## Recommended Architecture: JavaScript UDF

| SQL Server CLR | Snowflake Equivalent |
|---|---|
| `dbo.fn_sisulate(@template NVARCHAR(MAX), @bindings NVARCHAR(MAX)) RETURNS NVARCHAR(MAX)` | `SISULATE(TEMPLATE VARCHAR, BINDINGS VARCHAR) RETURNS VARCHAR` |
| `SqlFunction` with `SAFE` permission | JavaScript UDF (sandboxed by default, no network/disk) |
| SQL Server JSON functions (`JSON_VALUE`, `JSON_QUERY`, `OPENJSON`) via context connection | `JSON.parse()` + native JS property access + array iteration |
| `SqlConnection("context connection=true")` | Not needed — all logic runs in a single JS context |
| .NET Framework build with `csc.exe` | No build step — UDF body is inline SQL |
| Assembly registration + SHA-512 trust | CREATE OR REPLACE FUNCTION statement |

---

## What Changes

### Gets Simpler
1. **No nested SQL calls** — the CLR's `ExecScalar("SELECT JSON_VALUE(@j, @p)", ...)` and `EnumerateJsonArray` with `OPENJSON` become plain JavaScript: `jsonObj.property`, `array.forEach()`, `array.filter()`, `array.sort()`
2. **No build step** — JavaScript UDFs are defined inline in SQL, no compiler needed
3. **No assembly registration** — just `CREATE OR REPLACE FUNCTION`
4. **JSON path building** — the `BuildJsonPath()` method that constructs `$."prop"."sub"` paths goes away; JavaScript uses direct property traversal

### Needs Adaptation
1. **JSON path resolution** — S-Path (`source.parts[0].name`) → JavaScript property traversal (`source.parts[0].name`). A simple path resolver function walks the parsed JS object.
2. **ORDER BY in foreach** — Snowflake's JS UDF doesn't have built-in sorting. Implement with `Array.sort()` in the UDF.
3. **WHERE filtering** — Implement inline in JavaScript instead of delegating to SQL.
4. **NVARCHAR(MAX) → VARCHAR(16MB)** — Snowflake's max VARCHAR is 16MB. This should be sufficient for template rendering.
5. **Argument case** — JavaScript UDFs require uppercase argument names (`TEMPLATE`, `BINDINGS`).

### Feature Parity Maintained
- All Sisula language features (foreach, if/else, comments, tokens, loop metadata, expressions, and/or, contains/startswith/endswith) port directly
- `/*~ ... ~*/` block delimiters
- Template storage in a `SisulaTemplates` table

---

## Proposed Plan

### Phase 1: Core Renderer (`sisula-snowflake/src/sisula.js`)
Port the single-file renderer (1306 lines of C#) to a single JavaScript file with these functions:
- `render(template, bindingsJson)` — main entry point
- `renderScript(text, ctx, loopVars)` — line-by-line directive parser
- `renderInline(text, ctx, loopVars)` — token expansion via regex
- `resolvePath(path, ctx, loopVars)` — JSON property traversal (replaces `JsonRead` + `BuildJsonPath`)
- `evalCondition(expr, ctx, loopVars, itemVar)` — expression evaluator (comparisons, and/or, functions, truthy)
- `expandInlineForeach` / `expandInlineIf` — embedded directive expansion

### Phase 2: SQL Deployment (`sisula-snowflake/sql/deploy.sql`)
- `CREATE OR REPLACE FUNCTION SISULATE(TEMPLATE VARCHAR, BINDINGS VARCHAR) RETURNS VARCHAR LANGUAGE JAVASCRIPT AS $$ ... $$`
- Template table DDL: `SisulaTemplates(name VARCHAR, content VARCHAR, modified_at TIMESTAMP_NTZ)`
- Helper stored procedure for CRUD on templates

### Phase 3: Tests (`sisula-snowflake/sql/`)
- Port existing test SQL scripts (`test_render.sql`, `test_and_or.sql`, `test_contains.sql`, etc.)
- Adapt bindings construction (no `STRING_ESCAPE`, use Snowflake's `PARSE_JSON()` or direct JSON construction)

### Phase 4: Documentation
- Port `SISULA.md` as-is (the language spec is platform-agnostic)
- Snowflake-specific deployment README

---

## Potential Concerns

| Concern | Mitigation |
|---|---|
| JavaScript UDF 1-minute timeout | Templates are rendered once, not per-row; increase timeout if needed or use a Stored Procedure instead |
| JS number precision loss for large integers | Bindings typically contain strings/JSON; numeric paths (ordinals, indexes) don't exceed safe integer range |
| No `SqlString.Null` equivalent | Return `null` from JS for SQL NULL |
| Unicode in regex | JavaScript's `/u` flag + `\p{L}` support in modern engines covers the Unicode token syntax |

---

## Recommended Repo Structure

```
sisula-snowflake/
├── README.md
├── SISULA.md                    # Language spec (copied/adapted)
├── src/
│   └── sisula.js                # Core JavaScript renderer
├── sql/
│   ├── deploy.sql               # Creates UDF + template table
│   ├── test_render.sql          # Main test
│   ├── test_and_or.sql
│   ├── test_contains.sql
│   ├── test_inline_if_or.sql
│   └── test_nested_inline_if.sql
├── templates/
│   └── CreateTypedTables.sql    # Example template
└── .github/
    └── copilot-instructions.md
```

