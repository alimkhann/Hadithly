import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class ReaderScrollBudgetTests(unittest.TestCase):
    def check(self, ratios, durations=None, frames=None, region='Scroll_DraggingAndDeceleration'):
        metrics = {
            f'Hitch Time Ratio ({region}), ms per s': ratios,
            f'Duration ({region}), s': durations or [10, 10, 10],
            'CPU Time (app), s': [1, 1, 1],
        }
        if frames is not None:
            metrics[f'Frame Count ({region}), frames'] = frames
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'metrics.json'
            path.write_text(json.dumps(metrics))
            return subprocess.run([
                sys.executable, str(Path(__file__).with_name('check-reader-scroll-metrics.py')),
                '--ios-json', str(path), '--each-scroll-hitch-below', '1',
                '--scroll-region', region,
            ], capture_output=True, text=True)

    def test_low_average_cannot_hide_a_bad_run(self):
        result = self.check([0, 0, 2])
        self.assertEqual(result.returncode, 1)
        self.assertLess(json.loads(result.stdout)['ios']['scroll_hitch_ms_per_second']['mean'], 1)

    def test_threshold_is_strict_for_every_run(self):
        self.assertEqual(self.check([0, 0, 1]).returncode, 1)
        self.assertEqual(self.check([0.5, 0.6, 0.9]).returncode, 0)

    def test_empty_scroll_and_nonfinite_metrics_cannot_pass(self):
        self.assertNotEqual(self.check([0, 0, 0], [10, 0, 10]).returncode, 0)
        self.assertNotEqual(self.check([0, float('nan'), 0]).returncode, 0)

    def test_native_scroll_requires_positive_frame_evidence(self):
        self.assertNotEqual(self.check([0, 0, 0], frames=[0, 0, 0], region='ReaderActiveScroll').returncode, 0)
        self.assertEqual(self.check([0, 0, 0], frames=[600, 600, 600], region='ReaderActiveScroll').returncode, 0)


if __name__ == '__main__':
    unittest.main()
