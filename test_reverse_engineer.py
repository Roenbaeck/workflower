import io
import json
import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path
from unittest.mock import MagicMock, patch

from webapp import read
from webapp.reverse_engineer import export_graphs, identifier_parts, quoted, split_task_ddl, TaskImportError


def task(name, parents=(), **extras):
    return dict(database_name='DB', schema_name='SC', name=name, predecessors=json.dumps(list(parents)),
                task_relations='{}', comment="A task's comment", warehouse=None, state='started', schedule=None, **extras)


class ReverseTests(unittest.TestCase):
    def setUp(self):
        self.connection = MagicMock()
        self.cursor = self.connection.cursor.return_value.__enter__.return_value
        self.cursor.fetchone.side_effect = lambda: (f'create or replace task {self.cursor.execute.call_args.args[1][0]} USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE=\'XSMALL\' AS BEGIN SELECT \'x;y\'; END;',)

    def export(self, rows, root=None):
        with patch('webapp.reverse_engineer.read_tasks', return_value=rows):
            return export_graphs(self.connection, 'DB.SC', root)

    def test_quoted_identifiers_and_unsafe_input(self):
        self.assertEqual(identifier_parts('db."Mixed.schema"."a""b"'), ('DB', 'Mixed.schema', 'a"b'))
        self.assertEqual(quoted(('D', 'a"b')), '"D"."a""b"')
        for value in ('db.sc; DROP TASK x', 'db.', '', 'db..sc'):
            with self.assertRaises(TaskImportError):
                identifier_parts(value)

    def test_split_ignores_literals_comments_and_execute_as_user(self):
        ddl = '''create or replace task "AS" COMMENT='AS ''test''' + "'" + '''
        -- AS is a comment
        EXECUTE AS USER "somebody" WHEN SYSTEM$STREAM_HAS_DATA('stream')
        AS BEGIN SELECT 'AS;'; END;'''
        header, body = split_task_ddl(ddl)
        self.assertIn('EXECUTE AS USER', header)
        self.assertTrue(header.endswith('AS'))
        self.assertEqual(body, "BEGIN SELECT 'AS;'; END")

    def test_diamond_sorted_and_preserved_without_inferred_lineage(self):
        graphs = self.export([task('JOIN', ['DB.SC.A', 'DB.SC.B']), task('B', ['DB.SC.ROOT']), task('ROOT'), task('A', ['DB.SC.ROOT'])])
        self.assertEqual(len(graphs), 1)
        tasks = graphs[0]['TASKS']
        self.assertEqual([t['name'] for t in tasks], ['"DB"."SC"."ROOT"', '"DB"."SC"."A"', '"DB"."SC"."B"', '"DB"."SC"."JOIN"'])
        self.assertEqual(len(tasks[-1]['after']), 2)
        self.assertTrue(all(t['state'] == 'suspended' and t['steps'] == [] for t in tasks))
        self.assertIn("SELECT 'x;y'", tasks[0]['native']['body'])
        self.assertEqual(tasks[0]['native']['source_state'], 'started')
        self.assertIn('USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE', tasks[0]['native']['header'])
        for call in self.cursor.execute.call_args_list:
            self.assertEqual(call.args[0], "SELECT GET_DDL('TASK', ?, TRUE)")

    def test_root_selection_excludes_other_graphs(self):
        graphs = self.export([task('ROOT'), task('CHILD', ['DB.SC.ROOT']), task('OTHER')], 'root')
        self.assertEqual(len(graphs), 1)
        self.assertEqual(len(graphs[0]['TASKS']), 2)
        with self.assertRaisesRegex(TaskImportError, 'root or standalone'):
            self.export([task('ROOT'), task('CHILD', ['DB.SC.ROOT'])], 'child')

    def test_finalizer_retains_semantics_and_is_created_last(self):
        root, finalizer = task('ROOT'), task('FINAL')
        root['task_relations'] = '{"FinalizerTask":"DB.SC.FINAL","Predecessors":[]}'
        finalizer['task_relations'] = '{"FinalizedRootTask":"DB.SC.ROOT","Predecessors":[]}'
        graph = self.export([root, finalizer, task('CHILD', ['DB.SC.ROOT'])])[0]
        self.assertEqual(graph['TASKS'][-1]['name'], '"DB"."SC"."FINAL"')
        self.assertEqual(graph['TASKS'][-1]['native']['finalizes'], '"DB"."SC"."ROOT"')
        self.assertFalse(graph['TASKS'][-1]['is_root'])

    def test_incomplete_graph_and_cycles_fail(self):
        for rows in ([task('CHILD', ['DB.SC.HIDDEN'])], [task('A', ['DB.SC.B']), task('B', ['DB.SC.A'])]):
            with self.assertRaises(TaskImportError):
                self.export(rows)
        self.cursor.execute.assert_not_called()

    def test_schema_show_is_read_only_and_quotes_names(self):
        from webapp.reverse_engineer import read_tasks
        self.cursor.description = [('name',)]
        self.cursor.fetchall.return_value = []
        self.assertEqual(read_tasks(self.connection, 'db."Mixed.schema"'), [])
        self.cursor.execute.assert_called_once_with('SHOW TASKS IN SCHEMA "DB"."Mixed.schema" LIMIT 10000')

    def test_cli_exports_importable_json_and_never_overwrites(self):
        graphs = self.export([task('ROOT')])
        @contextmanager
        def service(*args, **kwargs):
            yield MagicMock(connection=self.connection)
        with tempfile.TemporaryDirectory() as directory, patch.object(read, 'open_service', service), patch.object(read, 'export_graphs', return_value=graphs), patch('sys.stdout', new_callable=io.StringIO), patch('sys.stderr', new_callable=io.StringIO):
            self.assertEqual(read.main(['test', directory, '--schema', 'DB.SC']), 0)
            files = list(Path(directory).glob('*.json'))
            self.assertEqual(len(files), 1)
            self.assertEqual(json.loads(files[0].read_text())['IMPORT']['format'], 'snowflake-native-v1')
            original = files[0].read_bytes()
            self.assertEqual(read.main(['test', directory, '--schema', 'DB.SC']), 1)
            self.assertEqual(files[0].read_bytes(), original)


if __name__ == '__main__':
    unittest.main()
