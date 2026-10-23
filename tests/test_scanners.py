"""Offline regression checks; no TLS scans or API requests are sent."""
import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    with patch.dict('os.environ', {'TARGET_HOST': '', 'BGDB_EXTRA_HOSTS': ''}):
        spec.loader.exec_module(module)
    return module


ssl = load('ssllabs_scan')
pq = load('pq_tls_scan')


class ScannerTests(unittest.TestCase):
    def test_host_normalization(self):
        self.assertEqual(ssl.safe_host(' BGDB.EU. '), 'bgdb.eu')
        self.assertEqual(ssl.safe_host('bücher.example'), 'xn--bcher-kva.example')

    def test_invalid_hostname_labels(self):
        for host in ('good.-bad.example', 'bad-.example', 'a..example', 'https://bgdb.eu',
                     'a' * 64 + '.example'):
            with self.subTest(host=host), self.assertRaises(SystemExit):
                ssl.safe_host(host)

    def test_malformed_api_shapes_are_retried_and_logged(self):
        for payload in (b'[]', b'null', b'{}', b'{"status":42}'):
            with self.subTest(payload=payload):
                ssl.EVENTS.clear()
                def response(*args, **kwargs):
                    stream = io.BytesIO(payload)
                    stream.status = 200
                    return stream
                with patch.object(ssl.urllib.request, 'urlopen', side_effect=response), \
                     patch.object(ssl.time, 'sleep'), contextlib.redirect_stdout(io.StringIO()):
                    result = ssl.request('bgdb.eu', {'fromCache': 'on'}, 'test')
                self.assertEqual(result['status'], 'NETWORK_ERROR')
                self.assertEqual(len(ssl.EVENTS), 3)
                self.assertTrue(all(e['receive'] == 'no_usable_response' for e in ssl.EVENTS))

    def test_valid_api_response(self):
        stream = io.BytesIO(b'{"status":"READY"}')
        stream.status = 200
        with patch.object(ssl.urllib.request, 'urlopen', return_value=stream), \
             contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(ssl.request('bgdb.eu', {}, 'test')['status'], 'READY')

    def test_failed_openssl_is_inconclusive(self):
        for error in (b'Network is unreachable', b'Error setting groups list', b'certificate verify failed'):
            with self.subTest(error=error), patch.object(pq.subprocess, 'run', return_value=
                    subprocess.CompletedProcess([], 1, b'', error)):
                self.assertEqual(pq.scan_group('bgdb.eu', 'X25519MLKEM768')['result'], 'inconclusive')

    def test_confirmed_group_requires_matching_negotiation(self):
        for selected, expected in (('X25519MLKEM768', 'negotiated'), ('X25519', 'not_negotiated')):
            output = ('Protocol version: TLSv1.3\nNegotiated TLS1.3 group: ' + selected).encode()
            with self.subTest(selected=selected), patch.object(pq.subprocess, 'run', return_value=
                    subprocess.CompletedProcess([], 0, b'', output)):
                self.assertEqual(pq.scan_group('bgdb.eu', 'X25519MLKEM768')['result'], expected)


if __name__ == '__main__':
    unittest.main()
