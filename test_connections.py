"""Connection reuse, exclusive leases, MFA recovery, and API lifecycle tests."""

import unittest
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient
from webapp import server
from webapp.connections import ConnectionPool, ConnectionRequired, ConnectionBusy


class PoolTests(unittest.TestCase):
    def setUp(self):
        self.connection = MagicMock()
        self.connection.is_valid.return_value = True
        self.connect = MagicMock(return_value=self.connection)
        self.pool = ConnectionPool(self.connect)
        self.settings = patch('webapp.connections.connection_settings', return_value={"account": "example"})
        self.settings.start()
        self.addCleanup(self.settings.stop)
        self.addCleanup(self.pool.close)

    def test_operations_do_not_initiate_interactive_authentication(self):
        for _ in range(3):
            with self.assertRaises(ConnectionRequired):
                with self.pool.service():
                    self.fail('Must sign in first')
        self.connect.assert_not_called()

    def test_one_login_is_reused_across_operations(self):
        self.pool.reconnect()
        for _ in range(4):
            with self.pool.service() as service:
                self.assertIs(service.connection, self.connection)
        self.connect.assert_called_once()
        self.connection.close.assert_not_called()

    def test_concurrent_lease_or_reconnect_cannot_touch_active_connection(self):
        from concurrent.futures import ThreadPoolExecutor
        self.pool.reconnect()
        with self.pool.service():
            with ThreadPoolExecutor(max_workers=1) as executor:
                with self.assertRaises(ConnectionBusy):
                    executor.submit(self.pool.reconnect).result(timeout=2)
                def borrow():
                    with self.pool.service():
                        self.fail('Cannot use a leased session')
                with self.assertRaises(ConnectionBusy):
                    executor.submit(borrow).result(timeout=2)
            self.connection.close.assert_not_called()
        self.connect.assert_called_once()

    def test_expired_connection_requires_explicit_reconnect_without_replay(self):
        self.pool.reconnect()
        self.connection.is_valid.return_value = False
        for _ in range(2):
            with self.assertRaises(ConnectionRequired):
                with self.pool.service():
                    self.fail('Expired connection must not execute an operation')
        self.connection.close.assert_called_once()
        self.connect.assert_called_once()
        replacement = MagicMock()
        replacement.is_valid.return_value = True
        self.connect.return_value = replacement
        self.pool.reconnect()
        with self.pool.service() as service:
            self.assertIs(service.connection, replacement)

    def test_failed_login_is_sanitized_and_does_not_retry(self):
        self.connect.side_effect = RuntimeError('secret password and code 123456')
        with self.assertRaises(ConnectionRequired) as error:
            self.pool.reconnect(passcode='123456')
        self.assertNotIn('123456', str(error.exception))
        for _ in range(2):
            with self.assertRaises(ConnectionRequired):
                with self.pool.service():
                    pass
        self.connect.assert_called_once_with(account='example', passcode='123456', passcode_in_password=False)

    def test_sql_failure_keeps_a_healthy_authenticated_session(self):
        self.pool.reconnect()
        with self.assertRaisesRegex(RuntimeError, 'bad SQL'):
            with self.pool.service():
                raise RuntimeError('bad SQL')
        with self.pool.service():
            pass
        self.connection.close.assert_not_called()
        self.connect.assert_called_once()

    def test_connection_loss_during_write_is_not_replayed(self):
        self.pool.reconnect()
        writes = []
        with self.assertRaisesRegex(ConnectionRequired, 'partially completed'):
            with self.pool.service():
                writes.append('write')
                self.connection.is_valid.return_value = False
                raise RuntimeError('network failure')
        self.assertEqual(writes, ['write'])
        self.connection.close.assert_called_once()
        self.connect.assert_called_once()

    def test_shutdown_closes_and_prevents_reopening(self):
        self.pool.reconnect()
        self.pool.close()
        self.pool.close()
        self.connection.close.assert_called_once()
        with self.assertRaises(ConnectionRequired):
            self.pool.reconnect()
        self.connect.assert_called_once()


class ConnectionApiTests(unittest.TestCase):
    def test_connect_once_reuse_and_close_at_shutdown(self):
        connection = MagicMock()
        connection.is_valid.return_value = True
        connection.cursor.return_value.__enter__.return_value.fetchall.return_value = []
        with patch('webapp.connections.connection_settings', return_value={}), patch('snowflake.connector.connect', return_value=connection) as connect:
            with TestClient(server.app, base_url='http://localhost') as client:
                self.assertEqual(client.get('/api/workflows').status_code, 428)
                connect.assert_not_called()
                self.assertEqual(client.post('/api/connection/reconnect', json={}).status_code, 200)
                self.assertEqual(client.get('/api/workflows').json(), [])
                self.assertEqual(client.get('/api/workflows').json(), [])
                connect.assert_called_once()
                connection.close.assert_not_called()
                with server.app.state.connections.service():
                    self.assertEqual(client.post('/api/connection/reconnect', json={}).status_code, 409)
            connection.close.assert_called_once()

    def test_sign_in_error_does_not_expose_connector_credentials(self):
        with patch('webapp.connections.connection_settings', return_value={}), patch('snowflake.connector.connect', side_effect=RuntimeError('code 123456')):
            with TestClient(server.app, base_url='http://localhost') as client:
                response = client.post('/api/connection/reconnect', json={"passcode": "123456"})
                self.assertEqual(response.status_code, 428)
                self.assertEqual(response.json()['code'], 'connection_required')
                self.assertNotIn('123456', response.text)
                self.assertEqual(response.headers['cache-control'], 'no-store')
                self.assertEqual(client.post('/api/connection/reconnect', json={}, headers={'origin': 'https://foreign.example'}).status_code, 403)

    def test_install_stream_reports_reconnect_required(self):
        with TestClient(server.app, base_url='http://localhost') as client:
            response = client.post('/api/workflows/42/install/stream')
            self.assertIn('[ERROR]', response.text)
            self.assertIn('[CONNECTION_REQUIRED]', response.text)
            self.assertNotIn('[DONE]', response.text)


class StreamCleanupTests(unittest.IsolatedAsyncioTestCase):
    async def test_abandoned_stream_releases_lease_without_closing_session(self):
        connection = MagicMock()
        connection.is_valid.return_value = True
        pool = ConnectionPool(MagicMock(return_value=connection))
        with patch('webapp.connections.connection_settings', return_value={}):
            pool.reconnect()
        try:
            with patch.object(server, 'open_service', pool.service):
                response = server.install_workflow_stream(42)
                iterator = response.body_iterator
                await anext(iterator)
                with self.assertRaises(ConnectionBusy):
                    with pool.service():
                        pass
                await iterator.aclose()
                with pool.service():
                    pass
                connection.close.assert_not_called()
        finally:
            pool.close()


if __name__ == '__main__':
    unittest.main()
