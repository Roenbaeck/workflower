<center><img src="webapp/android-chrome-192x192.png" alt="Workflower icon" width="96" /></center>

# Workflower


Sisula for Snowflake: a template renderer, deployment surface, and workflow editor for generating and managing Snowflake task graphs from JSON workflow definitions.

Live web app: [https://roenbaeck.github.io/workflower/](https://roenbaeck.github.io/workflower/)

![Workflow Editor screenshot](docs/workflow-editor.png)

## What This Repo Contains

- A Snowflake implementation of the Sisula templating engine, exposed through the `SISULATE` function and helper procedures.
- A task-graph template flow that renders workflow JSON into Snowflake `CREATE TASK` SQL.
- Metadata deployment SQL for logging and workflow support tables.
- A browser-based workflow editor for inspecting and editing workflow graphs, backed by a minimal FastAPI server.

## Core Docs

- [Sisula language reference](docs/SISULA.md)
- [Workflow JSON format](docs/WorkflowFormat.md)

Use `docs/SISULA.md` as the primary language reference for the Snowflake Sisula engine.

## Repo Layout

- `sql/`: deploys the Snowflake Sisula engine and SQL-based tests.
- `metadata/`: metadata schema, model, knot values, logging procedures, and configuration procedures.
- `webapp/`: the workflow editor UI, FastAPI adapter, shared Python workflow service, CLI adapter, and browser assets.
- `webapp/templates/`: template sources deployed into Snowflake metadata storage; also used for the browser's local preview.
- `examples/`: example workflow bindings and rendered SQL output.
- `sisula-mssql/`: the older SQL Server CLR implementation kept as a reference implementation and compatibility baseline.

## Typical Flow

1. Deploy the Snowflake Sisula engine.
2. Deploy the metadata objects if you want workflow logging and task-graph support.
3. Author or edit workflow JSON.
4. Render and optionally deploy task graph SQL from the workflow definition.
5. Use the web app to inspect or edit workflows visually.

## Scripts

### Snowflake repo scripts

| Script | Purpose | Notes |
|---|---|---|
| `deploy.sh` | Deploys the Snowflake Sisula engine from `sql/deploy.sql`. | Requires the Snowflake CLI `snow` and a configured connection name. |
| `deploy_metadata.sh` | Deploys the metadata schema and supporting procedures from `metadata/`. | Runs the install steps in order, seeds `CreateTaskGraph` into metadata template storage, and stops on the first failure. |
| `read.sh` | Reverse engineers existing Snowflake task graphs into native Workflower JSON. | Uses `SHOW TASKS` and `GET_DDL`; no Workflower metadata installation required. |
| `install.sh` | Uses the shared Python service to render workflow JSON in Snowflake and optionally execute the SQL. | Default template is `CreateTaskGraph`; `--dry-run` requires Snowflake and writes SQL to `<directory>/rendered/` without executing it. |
| `test_all.sh` | Runs the Snowflake SQL test suite in `sql/`. | Validates deployed behavior in Snowflake. |
| `test_local.js` | Runs a local Node.js smoke test against `webapp/sisula.js`. | Fast check for parser and renderer behavior without Snowflake. |
| `webapp/run.sh` | Starts the workflow editor and API server. | Creates `webapp/.venv` on first run and serves the editor on `http://localhost:8000/` by default. |

### Legacy reference scripts

These belong to the SQL Server CLR reference implementation in `sisula-mssql/` rather than the Snowflake deployment path:

| Script | Purpose |
|---|---|
| `sisula-mssql/scripts/build.ps1` | Builds the SQL CLR assembly from `clr/SisulaRenderer.cs`. |
| `sisula-mssql/scripts/install.ps1` | Installs the SQL CLR assembly and function into SQL Server. |
| `sisula-mssql/scripts/format-json.ps1` | Pretty-prints JSON from the clipboard in PowerShell. |

## Quick Start

### 1. Deploy the Sisula engine

```bash
./deploy.sh <connection_name>
```

### 2. Deploy metadata support

```bash
./deploy_metadata.sh <connection_name>
```

### 3. Render or deploy workflow SQL from JSON

```bash
./install.sh <connection_name> ./examples --dry-run
./install.sh <connection_name> ./examples --template CreateTaskGraph
```

Both commands use the **deployed** template in Snowflake metadata storage. Deploy metadata support first. `--template` names a stored template, not a local file. The installer writes the rendered SQL before execution and stops on the first failure. It does not save the input JSON as a configuration; save it through the editor if you want it in the workflow library.

### Import existing Snowflake tasks

```bash
# Export each visible graph in a schema to its own JSON file.
./read.sh <connection_name> ./imported --schema MY_DATABASE.MY_SCHEMA

# Export one root and its connected graph, including its finalizer.
./read.sh <connection_name> ./imported --schema MY_DATABASE.MY_SCHEMA --root ROOT_TASK

# SQL quotes preserve mixed-case names and dots inside identifiers.
./read.sh <connection_name> ./imported --schema 'MY_DATABASE."Mixed.Schema"' --root '"Root Task"' --mfa-passcode
```

This reads native tasks rather than saved Workflower configurations. It needs a role that can see the complete graph and retrieve each task's DDL, but it does not require Workflower's metadata schema or stored procedures. It creates one JSON file per graph, refuses to overwrite existing files, and does not alter Snowflake. Missing visible predecessors/finalizers or cycles cause an error. Snowflake only exposes tasks visible to the current role, so an entirely hidden child cannot be discovered.

Use **Import workflow JSON** in the editor to open an exported file. The graph shows dependencies, the Task tab shows preserved settings, and the Steps tab lets you edit the original SQL body. Native tasks run directly without Workflower's logging wrappers. Per-task warehouses, serverless options, conditions, schedules, session parameters, notifications and finalizer clauses remain in the `GET_DDL` header. Finalizer edges indicate their root and do not mean a normal `AFTER` dependency.

Imports default to **suspended** for installation; the original state is retained as metadata. Native settings and graph structure are read-only in the form editor. Advanced changes require updating both the native header and graph fields in JSON. Referenced procedures, tables, streams, integrations, privileges and grants are not exported or reconstructed. Unqualified references retain their original SQL, and settings inherited from the account are not captured independently. Review before installing into a different environment.

To render or reinstall, deploy the updated `CreateTaskGraph` template using `./deploy_metadata.sh <connection_name>` in your Workflower installation, then use the editor's Save/Install or `./install.sh <connection_name> ./imported --dry-run`. An older deployed template is rejected rather than silently dropping native task bodies. Installation suspends existing imported roots before replacing tasks and enables roots last if you explicitly change their state to running. Fully qualified task names target their original database/schema; installation is a separate, modifying action.

Source metadata: [SHOW TASKS](https://docs.snowflake.com/en/sql-reference/sql/show-tasks) and [GET_DDL](https://docs.snowflake.com/en/sql-reference/functions/get_ddl).

### 4. Run tests

```bash
./test_all.sh <connection_name>
node test_local.js
node --test test_workflow_read.js test_editor_ui.js test_install_ui.js test_connection_ui.js test_native_tasks.js
python3 -m venv webapp/.venv
webapp/.venv/bin/python -m pip install -r webapp/requirements-dev.txt
webapp/.venv/bin/python -m unittest -v test_workflows.py test_connections.py test_reverse_engineer.py
```

### 5. Start the workflow editor

```bash
./webapp/run.sh <connection_name>
```

The editor uses a full-height task graph beside an independently scrolling inspector. Select a graph node or use the task picker to edit its properties and steps. Workflow settings, JSON, and SQL each have their own inspector tab; the inspector can be expanded for longer definitions.

Save and Install remain in the top bar. Export and delete actions are in More. The workflow library supports filtering, JSON import, and Read from Snowflake without a local configuration file. On smaller screens the library opens as a drawer, and Graph / Details switches between the canvas and inspector.

The editor regression tests require Node.js 18 or later. The Python tests cover the service and both adapters with mocked Snowflake connections, including render failures, partial execution, connection reuse, concurrent leases, expired sessions, authentication failures, stream cleanup, dry runs, and HTTP boundaries. They do not replace live Snowflake integration tests or browser layout checks. Fonts and Lucide icons load from CDNs, with local font and text fallbacks when unavailable.

## Architecture

The browser calls the local FastAPI API. The API and `install.sh` both use `webapp/workflows.py` to connect through the Snowflake Python connector, call `SP_SISULA_RENDER` with bound parameters, and execute the returned SQL statement by statement. The service has no HTTP or command-line dependencies. Snowpark is not required.

The local web server owns a single-slot connection pool. Click **Connect / reconnect** in the Snowflake connection panel to authenticate once. Each API operation leases that connection exclusively, with a streaming installation retaining its lease until completion or disconnection. Competing requests receive a busy response rather than opening more connections or queuing more MFA prompts. The server closes the connection at shutdown. Run one server worker for this single-user tool; each additional process would have its own pool and login.

Before lending the connection, the pool checks session validity. An expired or unavailable session is discarded and requires an explicit reconnect. Connection loss during an operation is reported without replaying the operation. Reconnecting refreshes the workflow library but preserves the current draft and does not retry failed saves or installations. The CLI still owns one connection for its entire batch. Importing the server, loading the editor, and disconnected API requests do not initiate authentication.

Both Python entry points read `[connections.<name>]` from `~/.snowflake/config.toml`, falling back to `~/Library/Application Support/snowflake/config.toml`. Set `SNOWFLAKE_CONFIG_FILE` to select another file for these entry points. Connection parameters, including `authenticator`, are passed to the connector; CLI `private_key_path` is translated to `private_key_file`. Password authentication is not hard-coded. Supported connector authentication parameters are described in the [Snowflake documentation](https://docs.snowflake.com/en/developer-guide/python-connector/python-connector-connect).

### MFA and browser sign-in

For Snowflake password authentication with MFA, add these settings to your existing connection profile:

```toml
[connections.my_connection]
account = "my-org-my-account"
user = "my-user"
password = "my-password"
authenticator = "username_password_mfa"
client_request_mfa_token = true
```

Keep your database, schema, role, and warehouse settings in this profile too. In the editor's connection panel, leave the one-time-code field blank for push approval, or enter a current authenticator code if your account requires it. The field is cleared immediately when submitted; Workflower does not write codes to configuration files or browser storage. For the command-line installer, use `--mfa-passcode` to enter a code through a hidden terminal prompt, rather than passing the code as a command-line argument.

For configured federated SSO, use `authenticator = "externalbrowser"` in the profile and complete sign-in in the browser opened by the Python connector on the machine running the server. Leave the editor's code field blank.

The connector's `secure-local-storage` extra is installed by the launchers. Workflower defaults `client_request_mfa_token` to `true` for `username_password_mfa`, and `client_store_temporary_credential` to `true` for `externalbrowser`; explicit `false` values in the profile are respected. These settings request credential caching through the connector's supported secure storage. They do not bypass MFA or extend server session policy.

MFA token caching requires an administrator to enable `ALLOW_CLIENT_MFA_CACHING` in Snowflake. Browser SSO caching requires the applicable account settings, including `ALLOW_ID_TOKEN`. Workflower does not change these settings. Without caching, connection reuse still avoids signing in for every operation, but an explicit reconnect may prompt again. See [Snowflake MFA caching](https://docs.snowflake.com/en/user-guide/security-mfa) and [SSO caching](https://docs.snowflake.com/en/user-guide/admin-security-fed-auth-use).

`deploy.sh`, `deploy_metadata.sh`, and `test_all.sh` still use the Snowflake CLI for bootstrapping and SQL integration tests. They do not implement a second workflow installation path. The browser's SQL tab remains an offline preview using the bundled JavaScript renderer and template; installation always uses the deployed Snowflake version, which may differ until template changes are deployed.

The server binds to `127.0.0.1`, accepts local hostnames, rejects cross-origin browser writes, and serves only explicitly listed browser assets. It is a local administrative tool without multi-user authentication. Shared hosting would require an authentication and authorization design.

Installations are not atomic: earlier DDL may remain applied if a later statement fails. The service stops on failure without automatic retries. The browser requires an explicit completion event and treats a truncated stream as incomplete; inspect Snowflake before retrying.

## Requirements

- Snowflake CLI `snow`
- Node.js 18+ for JavaScript regression tests
- Python 3.11+ for the workflow editor backend and workflow installer
- A configured Snowflake connection name available to the CLI and workflow editor

The Python launchers share `webapp/.venv` and install dependencies on first use or when `requirements.txt` changes.
