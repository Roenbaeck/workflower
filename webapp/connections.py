"""A single authenticated connection, leased exclusively by the local editor."""

from contextlib import contextmanager
from threading import Lock

try:
    from .workflows import WorkflowService, connection_settings
except ImportError:  # python webapp/server.py
    from workflows import WorkflowService, connection_settings


class ConnectionRequired(Exception):
    pass


class ConnectionBusy(Exception):
    pass


class ConnectionPool:
    """One slot avoids concurrent session use and multiple interactive logins.

    Only explicit reconnect may authenticate. Failed operations are never replayed.
    A busy slot fails promptly rather than blocking web-server worker threads.
    """

    def __init__(self, connect=None):
        self._connect = connect
        self._connection = None
        self._lock = Lock()
        self._closed = False

    @contextmanager
    def _exclusive(self):
        if not self._lock.acquire(blocking=False):
            raise ConnectionBusy("Snowflake is busy with another operation or sign-in. Try again when it finishes.")
        try:
            if self._closed:
                raise ConnectionRequired("The Snowflake connection manager has shut down.")
            yield
        finally:
            self._lock.release()

    def _discard(self):
        connection, self._connection = self._connection, None
        if connection is not None:
            try:
                connection.close()
            except Exception:
                pass  # A broken connection must not mask the original failure.

    def reconnect(self, passcode=None):
        with self._exclusive():
            self._discard()
            try:
                import snowflake.connector

                settings = connection_settings()
                if passcode:
                    settings["passcode"] = passcode
                    settings["passcode_in_password"] = False
                self._connection = (self._connect or snowflake.connector.connect)(**settings)
            except Exception as exc:
                self._discard()
                # Never return connector diagnostics that could contain credentials.
                raise ConnectionRequired("Snowflake sign-in failed. Check your connection profile and complete MFA, then connect again.") from exc

    @contextmanager
    def service(self):
        with self._exclusive():
            if self._connection is None:
                raise ConnectionRequired("Connect to Snowflake to continue. Complete sign-in or MFA in the connection panel.")
            if not self._valid():
                self._discard()
                raise ConnectionRequired("The Snowflake session has expired or is unavailable. Reconnect, then retry your action.")
            try:
                yield WorkflowService(self._connection)
            except Exception as exc:
                if not self._valid():
                    self._discard()
                    raise ConnectionRequired("The Snowflake connection was lost. Reconnect; check Snowflake before retrying a save or installation because it may have partially completed.") from exc
                raise

    def _valid(self):
        try:
            return self._connection is not None and self._connection.is_valid()
        except Exception:
            return False

    def close(self):
        # Shutdown waits for a borrower; reconnect never closes an active lease.
        with self._lock:
            self._closed = True
            self._discard()
