import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('one_worker', Path(__file__).with_name('archive-one-worker.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class WorkerPolicy(unittest.TestCase):
    def test_every_item_in_order_without_pool(self):
        original = runner.parallel.processors
        seen = []
        with runner.one_worker(), patch.object(runner.parallel.concurrent.futures, 'ProcessPoolExecutor') as pool:
            result = list(runner.parallel.ordered(lambda x: seen.append(x) or x*x, range(7)))
            self.assertEqual(seen, list(range(7)))
            self.assertEqual(result, [x*x for x in range(7)])
            pool.assert_not_called()
        self.assertIs(runner.parallel.processors, original)

    def test_failure_propagates_and_policy_restores(self):
        original = runner.parallel.processors
        def fail(_):
            raise RuntimeError('qualification refusal')
        with self.assertRaisesRegex(RuntimeError, 'qualification refusal'):
            with runner.one_worker():
                list(runner.parallel.ordered(fail, [1]))
        self.assertIs(runner.parallel.processors, original)

    def test_release_status_is_not_rewritten(self):
        original = runner.parallel.processors
        with patch.object(runner.release, 'main', side_effect=lambda: 7 if runner.parallel.processors() == 1 else 0):
            self.assertEqual(runner.main(), 7)
        self.assertIs(runner.parallel.processors, original)

    def test_release_exit_is_not_caught(self):
        original = runner.parallel.processors
        with patch.object(runner.release, 'main', side_effect=SystemExit(6)):
            with self.assertRaises(SystemExit) as caught:
                runner.main()
        self.assertEqual(caught.exception.code, 6)
        self.assertIs(runner.parallel.processors, original)


if __name__ == '__main__':
    unittest.main()
