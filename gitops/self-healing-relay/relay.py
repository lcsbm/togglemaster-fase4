"""
Self-Healing Relay: receives any Grafana webhook and dispatches
the self-healing GitHub Actions workflow.
"""
import os
import json
import urllib.request
from http.server import HTTPServer, BaseHTTPRequestHandler

GITHUB_TOKEN = os.environ["GITHUB_TOKEN"]
GITHUB_URL = (
    "https://api.github.com/repos/lcsbm/togglemaster-fase4"
    "/actions/workflows/self-healing.yml/dispatches"
)
PAYLOAD = json.dumps({
    "ref": "main",
    "inputs": {"service": "auth-service", "namespace": "togglemaster"}
}).encode()


class RelayHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)

        try:
            alert = json.loads(body)
            status = alert.get("status", "unknown")
            print(f"Alert received — status: {status}")

            if status != "firing":
                print("Not firing — skipping dispatch")
                self._respond(200)
                return

            req = urllib.request.Request(
                GITHUB_URL,
                data=PAYLOAD,
                headers={
                    "Authorization": f"Bearer {GITHUB_TOKEN}",
                    "Accept": "application/vnd.github+json",
                    "Content-Type": "application/json",
                },
            )
            with urllib.request.urlopen(req) as resp:
                print(f"GitHub dispatch: {resp.status}")
            self._respond(204)

        except Exception as e:
            print(f"Error: {e}")
            self._respond(500)

    def _respond(self, code):
        self.send_response(code)
        self.end_headers()

    def log_message(self, fmt, *args):
        pass  # silencia o log padrão do BaseHTTPRequestHandler


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    print(f"Self-healing relay listening on :{port}")
    HTTPServer(("", port), RelayHandler).serve_forever()
