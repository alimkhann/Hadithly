from pathlib import Path
import runpy
import tempfile
import unittest

SUMMARIZE = runpy.run_path(str(Path(__file__).with_name("summarize-reader-hitches.py")))["summarize"]


class ReaderHitchSummaryTests(unittest.TestCase):
    def summarize(self, rows):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "hitches.xml"
            path.write_text("<trace-query-result><node>" + rows + "</node></trace-query-result>")
            return SUMMARIZE(path, 1)

    def test_anonymous_rows_remain_visible_without_app_attribution(self):
        result = self.summarize('<row><start-time>0</start-time><duration>10000000</duration><sentinel/></row>')
        self.assertEqual(result["app_hitches"], 0)
        self.assertEqual(result["unattributed_hitch_rows"], 1)

    def test_app_intervals_are_clipped_and_other_processes_excluded(self):
        result = self.summarize(
            '<row><start-time>990000000</start-time><duration>30000000</duration><process id="1" fmt="Hadithly (2)"/></row>'
            '<row><start-time>1100000000</start-time><duration>20000000</duration><process ref="1"/></row>'
            '<row><start-time>0</start-time><duration>900000000</duration><process fmt="Widget (3)"/></row>')
        self.assertEqual(result["app_hitches"], 1)
        self.assertEqual(result["app_hitches_outside_window"], 1)
        self.assertEqual(result["hitch_interval_union_ms"], 10)

    def test_overlapping_intervals_count_time_once(self):
        result = self.summarize(
            '<row><start-time>0</start-time><duration>20000000</duration><process id="1" fmt="Hadithly (2)"/></row>'
            '<row><start-time>10000000</start-time><duration>20000000</duration><process ref="1"/></row>')
        self.assertEqual(result["app_hitches"], 2)
        self.assertEqual(result["hitch_interval_union_ms"], 30)


if __name__ == "__main__":
    unittest.main()
