#!/usr/bin/env python3
"""Local FastAPI adapter for the shared workflow service."""

from contextlib import asynccontextmanager
from datetime import datetime
import os
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
from starlette.middleware.trustedhost import TrustedHostMiddleware
from starlette.concurrency import iterate_in_threadpool, run_in_threadpool
from pydantic import BaseModel, SecretStr
import anyio

try:
    from .workflows import InvalidWorkflow, RenderError, WorkflowNotFound
    from .connections import ConnectionPool, ConnectionRequired, ConnectionBusy
except ImportError:  # python webapp/server.py
    from workflows import InvalidWorkflow, RenderError, WorkflowNotFound
    from connections import ConnectionPool, ConnectionRequired, ConnectionBusy


@asynccontextmanager
async def lifespan(app):
    app.state.connections = ConnectionPool()
    try:
        yield
    finally:
        await run_in_threadpool(app.state.connections.close)


app = FastAPI(title="Workflower", lifespan=lifespan)


def open_service():
    return app.state.connections.service()


class ConnectRequest(BaseModel):
    passcode: SecretStr | None = None


@app.exception_handler(ConnectionRequired)
async def connection_required(request, exc):
    return JSONResponse({"detail": str(exc), "code": "connection_required"}, status_code=428, headers={"Cache-Control": "no-store"})


@app.exception_handler(ConnectionBusy)
async def connection_busy(request, exc):
    return JSONResponse({"detail": str(exc), "code": "connection_busy"}, status_code=409)


@app.post("/api/connection/reconnect")
def reconnect(body: ConnectRequest):
    passcode = body.passcode.get_secret_value() if body.passcode else None
    if passcode and len(passcode) > 256:
        raise HTTPException(status_code=400, detail="MFA code is too long")
    app.state.connections.reconnect(passcode=passcode)
    return JSONResponse({"status": "connected"}, headers={"Cache-Control": "no-store"})

app.add_middleware(TrustedHostMiddleware, allowed_hosts=["localhost", "127.0.0.1", "[::1]"])
BASE_DIR = Path(__file__).resolve().parent
# Only browser assets are public; never serve Python, virtualenvs, or config files.
PUBLIC_FILES = {
    "index.html", "editor.css", "LayoutEngine.js", "sisula.js", "Snowflower.svg",
    "site.webmanifest", "favicon.ico", "favicon-16x16.png", "favicon-32x32.png",
    "apple-touch-icon.png", "android-chrome-192x192.png", "android-chrome-512x512.png",
    "templates/CreateTaskGraph.sql", "templates/CreateTypedTables.sql",
}


@app.middleware("http")
async def require_same_origin(request: Request, call_next):
    # This is a local, privileged tool. Reject browser requests from other sites.
    if request.method in {"POST", "PUT", "PATCH", "DELETE"}:
        origin = request.headers.get("origin")
        if (origin is not None and origin != str(request.base_url).rstrip("/")) or request.headers.get("sec-fetch-site") == "cross-site":
            return JSONResponse({"detail": "Cross-origin writes are not allowed"}, status_code=403)
    return await call_next(request)


@app.exception_handler(WorkflowNotFound)
async def workflow_not_found(request, exc):
    return JSONResponse({"detail": str(exc)}, status_code=404)


@app.exception_handler(InvalidWorkflow)
async def invalid_workflow(request, exc):
    return JSONResponse({"detail": str(exc)}, status_code=400)


@app.exception_handler(RenderError)
async def render_error(request, exc):
    return JSONResponse({"detail": str(exc)}, status_code=502)


@app.get("/api/workflows")
def list_workflows():
    with open_service() as service:
        return service.list_workflows()


@app.get("/api/workflows/{name:path}")
def get_workflow(name: str):
    with open_service() as service:
        return service.get_workflow(name=name)


@app.put("/api/workflows/{name:path}")
def save_workflow(name: str, body: dict):
    with open_service() as service:
        return service.save_workflow(name, body)


@app.delete("/api/workflows/{name:path}")
def delete_workflow(name: str):
    with open_service() as service:
        return service.delete_workflow(name)


def install_log_line(level, message):
    # Keep each event on one line, including multi-line Snowflake errors.
    message = " | ".join(str(message).splitlines())
    return f"{datetime.now():%H:%M:%S} [{level.upper()}] {message}\n"


@app.post("/api/workflows/{cf_id}/install")
def install_workflow(cf_id: int):
    with open_service() as service:
        workflow = service.get_workflow(cf_id=cf_id)
        sql = service.render_workflow(workflow)
        count = 0
        for result in service.execute(sql):
            count = result.number
        return {"name": workflow["name"], "cf_id": cf_id, "statement_count": count}


@app.post("/api/workflows/{cf_id}/install/stream")
def install_workflow_stream(cf_id: int):
    def generate():
        try:
            # Lease the connection for the entire stream, including execution.
            with open_service() as service:
                yield install_log_line("info", f"Loading workflow CF_ID={cf_id}")
                workflow = service.get_workflow(cf_id=cf_id)
                yield install_log_line("ok", f"Loaded workflow {workflow['name']}")
                yield install_log_line("info", "Rendering CreateTaskGraph template")
                sql = service.render_workflow(workflow)
                yield install_log_line("ok", f"Rendered {len(sql.splitlines())} lines of DDL")
                yield install_log_line("info", "Executing rendered SQL statements")
                count = 0
                for result in service.execute(sql):
                    count = result.number
                    yield install_log_line("ok", f"Statement {count} executed | sfqid={result.query_id} | rowcount={result.row_count}")
                yield install_log_line("done", f"Install completed for {workflow['name']} ({count} statements)")
        except ConnectionRequired as exc:
            yield install_log_line("error", f"[CONNECTION_REQUIRED] {exc}")
        except Exception as exc:
            yield install_log_line("error", f"Install failed: {exc}")

    async def stream():
        iterator = generate()
        try:
            async for line in iterate_in_threadpool(iterator):
                yield line
        finally:
            # Release the lease even if the browser disconnects between events.
            with anyio.CancelScope(shield=True):
                await run_in_threadpool(iterator.close)

    return StreamingResponse(stream(), media_type="text/plain", headers={"Cache-Control": "no-store", "X-Accel-Buffering": "no"})


@app.get("/{path:path}")
def static_file(path: str):
    path = path or "index.html"
    if path not in PUBLIC_FILES:
        raise HTTPException(status_code=404, detail="Not found")
    return FileResponse(BASE_DIR / path)


if __name__ == "__main__":
    import uvicorn

    port = int(os.environ.get("PORT", 8000))
    print(f"Starting server on http://localhost:{port}")
    uvicorn.run(app, host="127.0.0.1", port=port)
