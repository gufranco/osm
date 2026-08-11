import http.server
import socketserver
import sys

ROOT = sys.argv[1]


STATUS_PREFIX = "/status"


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def do_GET(self):
        if self.path.startswith(STATUS_PREFIX):
            digits = "".join(c for c in self.path if c.isdigit())
            self.send_error(int(digits))
            return
        super().do_GET()

    def log_message(self, fmt, *args):
        pass


class Server(socketserver.TCPServer):
    allow_reuse_address = True


with Server(("127.0.0.1", 0), Handler) as httpd:
    sys.stdout.write("%d\n" % httpd.server_address[1])
    sys.stdout.flush()
    httpd.serve_forever()
