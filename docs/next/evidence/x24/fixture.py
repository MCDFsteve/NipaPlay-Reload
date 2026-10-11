"""Local protocol fixture for the X24 real-window experiment; no real accounts."""
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlsplit
from pathlib import Path
import json

class Handler(BaseHTTPRequestHandler):
    approved = False

    def log_message(self, *_):
        pass

    def reply(self, value, status=200):
        data = json.dumps(value, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = urlsplit(self.path).path
        if path.endswith('/api/v2/bangumi/7001'):
            self.reply({'success': True, 'bangumi': {
                'animeId': 7001, 'animeTitle': 'X24 catalogue fixture',
                'summary': 'Local protocol fixture, no real account.',
                'imageUrl': None, 'typeDescription': 'TV', 'type': 2,
                'isOnAir': False,
                'episodes': [{'episodeId': 7101, 'episodeTitle': 'X24 first episode',
                              'episodeNumber': '1', 'type': 1}]
            }})
        elif path in ['/System/Info/Public', '/System/Info']:
            self.reply({'Id': 'x24-fixture-server', 'ServerName': 'X24 fixture',
                        'Version': '10.10.0'})
        elif path == '/QuickConnect/Enabled':
            self.reply(True)
        elif path == '/QuickConnect/Initiate':
            self.reply({'Code': '246810', 'Secret': 'x24-synthetic-approval'})
        elif path == '/QuickConnect/Connect':
            self.reply({'Authenticated': Handler.approved})
        elif path == '/Users/x24-viewer':
            self.reply({'Id': 'x24-viewer', 'Name': 'x24-viewer', 'Policy': {}})
        elif path.startswith('/Users/') or path in ['/Library/VirtualFolders', '/UserViews', '/Items']:
            self.reply({'Items': [], 'TotalRecordCount': 0})
        else:
            self.reply({'error': 'Unknown fixture path', 'path': path}, 404)

    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length', 0)))
        path = urlsplit(self.path).path
        if path == '/fixture/approve':
            Handler.approved = True
            self.reply(True)
        elif path == '/QuickConnect/Initiate':
            self.reply({'Code': '246810', 'Secret': 'x24-synthetic-approval'})
        elif path in ['/Users/AuthenticateWithQuickConnect', '/Users/AuthenticateByName']:
            self.reply({'AccessToken': 'x24-synthetic-session',
                        'User': {'Id': 'x24-viewer', 'Name': 'x24-viewer'}})
        else:
            self.reply({'error': 'Unknown fixture path', 'path': path}, 404)

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=0)
    args = parser.parse_args()
    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    Path('/tmp/nipa-x24-fixture-port').write_text(str(server.server_port))
    print(json.dumps({'pid': __import__('os').getpid(), 'port': server.server_port}), flush=True)
    server.serve_forever()
