from pathlib import Path
import runpy
import tempfile
import unittest
import xml.etree.ElementTree as ET


TRACE = runpy.run_path(str(Path(__file__).with_name('summarize-reader-scroll-trace.py')))
SUMMARIZE = TRACE['summarize']


def table(path, fields, values):
    root = ET.Element('trace-query-result'); schema = ET.SubElement(root, 'schema')
    for field in fields:
        ET.SubElement(ET.SubElement(schema, 'col'), 'mnemonic').text = field
    for values_row in values:
        row = ET.SubElement(root, 'row')
        for field, value in zip(fields, values_row):
            node = ET.SubElement(row, field)
            if isinstance(value, str):
                node.set('fmt', value)
            else:
                node.text = str(value)
    ET.ElementTree(root).write(path)


class ReaderScrollTraceTests(unittest.TestCase):
    def fixture(self, folder, app_hitches=(), presentations=True, complete=True, runs=3, app_updates=True):
        path = Path(folder); points = []; frames = []; resources = []
        for index in range(runs):
            start = index * 40e9
            for name, process, begin, end in [
                ('ReaderMeasuredRun', 'Process (2)', start, start + 30e9),
                ('ReaderActiveScroll', 'Hadithly (1)', start + 5e9, start + 25e9),
                ('ReaderAnchorGeometry', 'Hadithly (1)', start + 6.02e9, start + 6.021e9),
            ]:
                subsystem = 'com.hadithly.reader.driver' if name == 'ReaderMeasuredRun' else 'com.hadithly.app.reader'
                points.append((begin, process, 'Begin', index, name, subsystem))
                if complete or name != 'ReaderMeasuredRun' or index != 2:
                    points.append((end, process, 'End', index, name, subsystem))
            frames += [(start + 6e9,), (start + 24e9,)]
            resources += [(start, 1e9, 'Hadithly (1)', start + 1e9, 100e6),
                          (start + 28e9, 1e9, 'Hadithly (1)', start + 10e9, 101e6)]
        table(path / 'points.xml', ['time', 'process', 'event-type', 'identifier', 'name', 'subsystem'], sorted(points))
        hitches = [(6e9, 200e6, 'HadithlyWidgets (3)')] + list(app_hitches)
        table(path / 'hitches.xml', ['start', 'duration', 'process'], hitches)
        table(path / 'frames.xml', ['timestamp'], frames if presentations else [])
        table(path / 'updates.xml', ['start', 'process'], [(row[0], 'Hadithly (1)') for row in frames] if app_updates else [])
        table(path / 'resources.xml', ['start', 'duration', 'process', 'cpu-total', 'memory-physical-footprint'], resources)
        return [path / name for name in ['points.xml', 'hitches.xml', 'frames.xml', 'resources.xml', 'updates.xml']] + [[1] * runs]

    def test_widget_hitches_do_not_contaminate_the_reader(self):
        with tempfile.TemporaryDirectory() as folder:
            result = SUMMARIZE(*self.fixture(folder))
            self.assertEqual(result['worst_hitch_ms_per_second'], 0)
            self.assertEqual(len(result['runs']), 3)
            self.assertEqual(result['runs'][0]['active_scroll_seconds'], 20)

    def test_overlapping_hitches_are_merged_and_a_bad_run_stays_visible(self):
        with tempfile.TemporaryDirectory() as folder:
            hitches = [(6e9, 30e6, 'Hadithly (1)'), (6.01e9, 30e6, 'Hadithly (1)')]
            result = SUMMARIZE(*self.fixture(folder, hitches))
            first = result['runs'][0]
            self.assertEqual(first['active_hitch_union_ms'], 40)
            self.assertEqual(first['active_hitch_ms_per_second'], 2)
            self.assertLess(sum(run['active_hitch_ms_per_second'] for run in result['runs']) / 3, 1)
            self.assertEqual(first['operations']['ReaderAnchorGeometry']['overlaps_hitch'], 1)

    def test_incomplete_capture_or_missing_frame_stream_cannot_pass(self):
        for options in [{'complete': False}, {'presentations': False}, {'app_updates': False}]:
            with self.subTest(options=options), tempfile.TemporaryDirectory() as folder:
                with self.assertRaises(ValueError):
                    SUMMARIZE(*self.fixture(folder, **options))

    def test_single_cooled_capture_needs_explicit_run_count(self):
        with tempfile.TemporaryDirectory() as folder:
            paths = self.fixture(folder, runs=1)
            with self.assertRaises(ValueError):
                SUMMARIZE(*paths)
            self.assertEqual(len(SUMMARIZE(*paths, expected_runs=1)['runs']), 1)

    def test_short_cpu_diagnostic_discards_partial_tail_without_relaxing_acceptance(self):
        with tempfile.TemporaryDirectory() as folder:
            paths = self.fixture(folder, runs=1)
            tree = ET.parse(paths[0]); root = tree.getroot()
            row = ET.SubElement(root, 'row')
            for key, value in zip(['time', 'process', 'event-type', 'identifier', 'name', 'subsystem'],
                                  [31e9, 'Hadithly (1)', 'Begin', 999, 'ReaderActiveScroll', 'com.hadithly.app.reader']):
                node = ET.SubElement(row, key)
                if isinstance(value, str): node.set('fmt', value)
                else: node.text = str(value)
            tree.write(paths[0])
            with self.assertRaisesRegex(ValueError, 'Trace ends inside'):
                SUMMARIZE(*paths, expected_runs=1)
            intervals = TRACE['signpost_intervals'](paths[0], complete_only=True)
            self.assertEqual(len([item for item in intervals if item[1] == 'ReaderActiveScroll']), 1)

    def test_partial_native_scroll_stream_cannot_pass_with_positive_frames(self):
        with tempfile.TemporaryDirectory() as folder:
            paths = self.fixture(folder)
            paths[-1] = [2, 1, 1]
            with self.assertRaisesRegex(ValueError, 'every driven gesture'):
                SUMMARIZE(*paths)


if __name__ == '__main__':
    unittest.main()
