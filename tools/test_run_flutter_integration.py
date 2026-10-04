import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('runner', Path(__file__).with_name('run_flutter_integration.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class CallableReadinessTests(unittest.TestCase):
    def test_missing_metadata_socket_does_not_qualify_as_loaded_function(self):
        for status, payload in [(404, {}), (500, {'error': {'status': 'UNKNOWN'}}),
                                (200, {'status': 'ok'}), (503, {})]:
            self.assertFalse(runner.callable_ready(status, payload))

    def test_loaded_read_or_authenticated_callable_envelope_is_accepted(self):
        self.assertTrue(runner.callable_ready(200, {'result': {'events': []}}))
        self.assertTrue(runner.callable_ready(401, {'error': {'status': 'UNAUTHENTICATED'}}))
        self.assertTrue(runner.callable_ready(400, {'error': {'status': 'INVALID_ARGUMENT'}}))

    def test_readiness_cannot_target_cloud(self):
        with self.assertRaisesRegex(RuntimeError, 'loopback'):
            runner.wait_for_functions('attendus.app:443', timeout=0)

    def test_timeout_fails_before_any_browser_process(self):
        with self.assertRaisesRegex(RuntimeError, 'no browser tests started'):
            runner.wait_for_functions(timeout=0)


if __name__ == '__main__':
    unittest.main()
