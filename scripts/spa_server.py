"""Static server for build/web that mirrors web/_redirects (`/* /index.html 200`):
a path with no file behind it gets index.html with a 200."""
import http.server, os, sys
ROOT, PORT = sys.argv[1], int(sys.argv[2])
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k): super().__init__(*a, directory=ROOT, **k)
    def send_head(self):
        path = self.translate_path(self.path)
        if not os.path.exists(path):
            self.path = "/index.html"
        return super().send_head()
http.server.ThreadingHTTPServer(("", PORT), H).serve_forever()
