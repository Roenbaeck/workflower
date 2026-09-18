# TODO

Originally a code review from 2026-09-17. Updated 2026-09-18 during the PowerShell rewrite.

## Still open

- [ ] **Third-party script with no integrity check.**
  `webapp/index.html` loads Lucide from unpkg with no `integrity`/`crossorigin`. The page
  can render and execute DDL against the account, so a compromised CDN response means
  arbitrary DDL. The new server sets a CSP that names the allowed hosts, which narrows but
  does not close this.
  *Fix:* vendor `lucide.min.js` locally (as `Snowflower.svg` already is) and add it to the
  server's `PublicFiles`, or pin an SRI hash. Same reasoning, lower impact, for the Google
  Fonts stylesheet.

- [ ] **`NodeType.ROOT_TASK` and `NodeType.TASK` do not exist.**
  `webapp/index.html` passes them to `new Node(...)`, but `webapp/LayoutEngine.js` defines
  no such members. Both are `undefined`, so every task node silently gets type `0`
  (UNKNOWN), whose `mass` and `charge` are `null`. It works only because `simpleLayout`
  never reads them; `complexLayout` would propagate `NaN` through every position. Root and
  regular tasks are also meant to be physically distinct and currently are not.

- [ ] **Duplicate task names silently merge graph nodes.**
  `taskId()` keys on `task.name`, so two identically-named tasks share one `nodeMap` entry
  and one layout position. `nextTaskName()` guards creation, but the rename path in
  `syncTask()` has no uniqueness check. Duplicates also emit two `CREATE OR REPLACE TASK`
  statements for the same object.

- [ ] **One unescaped interpolation.**
  The `rows` step inputs are built with `value="' + (step[f]||0) + '"` — the only
  `innerHTML` interpolation in the file not wrapped in `esc()`. These values come from
  imported workflow JSON and are not necessarily numeric. (The *SQL* side of this is now
  handled: the template wraps them in `TRY_TO_NUMBER($'...'$)`.)

- [ ] **JS tests slice source by string search.** e.g.
  `html.slice(html.indexOf('async function api('), html.indexOf('async function saveWorkflow('))`.
  Renaming or reordering either function changes what is under test with no failure signal,
  and an unmatched marker yields `-1` rather than an error.

- [ ] **The JavaScript tests were not run during the rewrite.** Node is not installed on
  the development machine and will not be on the restricted server. `test_workflow_read.js`
  was updated for CF_ID addressing but has not been executed. Either install Node somewhere
  in the loop or port these to a runner that exists on the target.

- [ ] **Most SQL tests print rather than assert.** Only `sql/test_escaping.sql` reports a
  `STATUS` column that `test_all.ps1` checks. The other five files render a template and
  print the output for a human to read, so a regression in them is invisible to CI.

## Fixed

- [x] **Generated DDL broke on ordinary input.** The template interpolated raw values into
  SQL comments and string literals. Fixed by adding the `$'path'$` and `$|path|$` escaping
  token forms to Sisula and using them throughout `CreateTaskGraph.sql`. Asserted by
  `sql/test_escaping.sql` and verified end to end against Snowflake.
- [x] **CI published the entire Python backend to a public site.** GitHub Pages hosting was
  dropped and the Python backend no longer exists.
- [x] **UI state was written to Snowflake.** `step._open` is now stripped in
  `serializeWorkflow()`.
- [x] **Rename-on-save was not atomic.** A save that renames passes `?previous=<cf_id>` and
  Snowflake retires the old configuration in the same call.
- [x] **Local layout was discarded before the delete was confirmed.** `clearLayoutState` now
  runs only after Snowflake confirms.
- [x] **Install failures returned HTTP 200.** The CLI exit code drives a real status; a
  failure returns 502 with the failing line and the run id of the rendered SQL.
- [x] **`python_env.sh` did not work on Windows.** Removed with the rest of the Python.
- [x] **`deploy_metadata.sh` staged SQL in a default-permission temp file.** Template
  seeding now uploads the file to the Snowflake stage instead of building a `CALL` with
  escaped quotes.
- [x] **No CSP header.** The PowerShell server sets one, along with `nosniff` and
  `Referrer-Policy`.
