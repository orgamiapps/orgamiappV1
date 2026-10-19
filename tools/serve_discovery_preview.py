"""Serve the isolated Discover fixture build on loopback only."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


class PreviewHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        if urlsplit(self.path).path.startswith('/app/'):
            self.path = '/index.html'
        super().do_GET()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8769)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1] / 'build' / 'discovery-preview'
    if not (root / 'index.html').is_file():
        parser.error('Build integration_test/discovery_preview.dart first.')
    server = ThreadingHTTPServer(
        ('127.0.0.1', args.port), partial(PreviewHandler, directory=str(root))
    )
    print(f'Discover fixture preview: http://127.0.0.1:{args.port}', flush=True)
    server.serve_forever()
