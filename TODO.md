# TODO

Findings from a code review on 2026-09-17, covering the Python backend, the editor,
the Sisula renderer, the `CreateTaskGraph` template, and CI. Neither test suite was
run during the review (no `node` or `python` on PATH at the time), so every item below
comes from reading the code and should be confirmed before or while fixing.

Ordered by severity, not by effort.

## High

- [ ] **CI publishes the entire Python backend to a public site.**
  `.github/workflows/static.yml:33` uploads `path: webapp` to GitHub Pages, which
  includes `server.py`, `connections.py`, `workflows.py`, `read.py`,
  `reverse_engineer.py`, `run.sh`, and `python_env.sh`. That defeats the intent
  stated at `webapp/server.py:64` — *"Only browser assets are public; never serve
  Python, virtualenvs, or config files."* GitHub Pages has no equivalent allowlist,
  and the README never mentions Pages hosting.
  *Fix:* stage only the `PUBLIC_FILES` set into a separate directory and upload that,
  or drop the workflow if Pages hosting is no longer wanted.

- [ ] **Generated DDL breaks on ordinary input; the description field is multi-line.**
  The template interpolates raw values into SQL comments and string literals, and
  `webapp/sisula.js` escapes nothing:

  ```sql
  -- Execute: $step.description$                                    -- CreateTaskGraph.sql:47
  COMMENT = '$task.description$'                                    -- :87
  tr_id := (CALL metadata._TaskRunStarting('$task.name$', ...))     -- :44
  CALL SYSTEM$SET_RETURN_VALUE('$step.message$');                   -- :73
  ```

  The task description is a `<textarea>` (`webapp/index.html:1851`), so a two-line
  description puts line 2 outside the `--` comment as executable SQL. A single `'` in
  any name, description, source, target, or message terminates its literal. This is a
  data-integrity bug before it is a security one, and it reaches Snowflake via
  `install`.
  *Needs a design call:* escaping belongs in the renderer (a `$'escaped'$` token form,
  or a `sqlEscape()` applied at the quoted sites), not in field validation alone.

- [ ] **Third-party script with no integrity check in a session-holding tool.**
  `webapp/index.html:15` loads Lucide from unpkg with no `integrity`/`crossorigin`.
  This page holds an authenticated Snowflake lease and can render and execute DDL, so
  a compromised CDN response means arbitrary DDL against the account.
  *Fix:* vendor `lucide.min.js` locally (as `Snowflower.svg` already is) and add it to
  `PUBLIC_FILES`, or pin an SRI hash. Same reasoning, lower impact, for the Google
  Fonts stylesheet.

## Medium

- [ ] **`NodeType.ROOT_TASK` and `NodeType.TASK` do not exist.**
  `webapp/index.html:1413` passes them to `new Node(...)`, but
  `webapp/LayoutEngine.js:2-15` defines no such members. Both are `undefined`, so
  `LayoutEngine.js:20` silently assigns type `0` (UNKNOWN) to every task node, whose
  `mass` and `charge` are `null`. It works only because `simpleLayout` never reads
  mass or charge — `complexLayout` would propagate `NaN` through every position. Root
  and regular tasks are also meant to be physically distinct and currently are not.

- [ ] **Duplicate task names silently merge graph nodes.**
  `taskId()` keys on `task.name`, so two identically-named tasks share one `nodeMap`
  entry and one layout position. `nextTaskName()` (`webapp/index.html:220`) guards
  creation, but the rename path in `syncTask()` (`webapp/index.html:1887`) has no
  uniqueness check. Duplicates also emit two `CREATE OR REPLACE TASK` statements for
  the same object.

- [ ] **UI state is written to Snowflake.**
  `serializeWorkflow()` (`webapp/index.html:506`) strips `_x`/`_y`/`_fixed` from tasks
  but nothing strips `step._open`, set at `webapp/index.html:1998` and `:2123`.
  Expanding a step and saving persists `"_open": true` into the stored configuration
  and into exported JSON.

- [ ] **One unescaped interpolation.**
  `webapp/index.html:1989` builds the `rows` step inputs with
  `value="' + (step[f]||0) + '"` — the only `innerHTML` interpolation in the file not
  wrapped in `esc()`. These values come from imported workflow JSON and are not
  necessarily numeric.

- [ ] **Rename-on-save is not atomic.**
  `webapp/index.html:921-929` PUTs the new name, then DELETEs the old. If the DELETE
  fails, or the connection drops between the two, two copies remain and the UI still
  reports success.

- [ ] **Local layout is discarded before the delete is confirmed.**
  `webapp/index.html:1030` calls `clearLayoutState(current)` ahead of the API call, so
  a failed delete leaves the workflow alive with its saved positions gone.

## Low

- [ ] **`python_env.sh` does not work on Windows.** It hardcodes `.venv/bin/python3`
  (`webapp/python_env.sh:4`); a Windows venv puts the interpreter at
  `.venv/Scripts/python.exe`, so `run.sh`, `install.sh`, and `read.sh` all fail there.

- [ ] **JS tests slice source by string search.** e.g.
  `html.slice(html.indexOf('function requireSnowflakeConnection('), html.indexOf('async function loadWorkflows('))`
  at `test_connection_ui.js:6`. Renaming or reordering either function changes what is
  under test with no failure signal, and an unmatched marker yields `-1` rather than an
  error.

- [ ] **Install failures return HTTP 200.** `webapp/server.py:139-172` streams errors as
  log lines and the client decides success by substring-matching `[ERROR]` and `[DONE]`
  (`webapp/index.html:981-992`). A Snowflake message containing either token skews the
  result. A trailing structured status line would be more robust.

- [ ] **`deploy_metadata.sh` stages SQL in a default-permission temp file.**
  `seed_template()` writes the rendered template to `mktemp` output; `chmod 600` before
  writing would be cheap.

- [ ] **No CSP header** on the local server's responses, which would blunt the CDN and
  `innerHTML` items together.
