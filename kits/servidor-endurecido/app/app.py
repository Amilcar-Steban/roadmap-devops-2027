# API mínima con la librería estándar: responde /api/health y /api/info
import json, os, socket, time
from http.server import BaseHTTPRequestHandler, HTTPServer

INICIO = time.time()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/api/health":
            body = {"status": "ok"}
        elif self.path == "/api/info":
            body = {"host": socket.gethostname(), "uptime_s": int(time.time() - INICIO)}
        else:
            self.send_error(404); return
        data = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

HTTPServer(("127.0.0.1", int(os.environ.get("PORT", "8080"))), Handler).serve_forever()