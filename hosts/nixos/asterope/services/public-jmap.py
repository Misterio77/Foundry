import http.client
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Server(ThreadingHTTPServer):
    slots = threading.BoundedSemaphore(4)

    def process_request(self, request, client_address):
        self.slots.acquire()
        try:
            super().process_request(request, client_address)
        except BaseException:
            self.slots.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.slots.release()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def respond(self, status, body, headers=None):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if self.path != "/jmap/" or not 0 < size <= 10_000_000:
                self.respond(400, b'{"error":"Invalid JMAP request"}')
                return
            body = self.rfile.read(size)
            request = json.loads(body)
            if "urn:stalwart:jmap" in request.get("using", []) or any(
                call[0].startswith("x:") for call in request.get("methodCalls", [])
            ):
                self.respond(403, b'{"error":"Management requires private access"}')
                return
        except (ValueError, TypeError, KeyError, IndexError, AttributeError):
            self.respond(400, b'{"error":"Invalid JMAP request"}')
            return
        connection = http.client.HTTPConnection("127.0.0.1", 8080, timeout=30)
        try:
            headers = {
                name: self.headers[name]
                for name in (
                    "Authorization",
                    "Content-Type",
                    "Host",
                    "X-Forwarded-For",
                    "X-Forwarded-Proto",
                    "X-Forwarded-Host",
                    "X-Real-IP",
                )
                if name in self.headers
            }
            connection.request("POST", "/jmap/", body=body, headers=headers)
            response = connection.getresponse()
            self.respond(
                response.status,
                response.read(),
                {
                    name: value
                    for name, value in response.getheaders()
                    if name.lower() in ("www-authenticate", "cache-control")
                },
            )
        except (OSError, http.client.HTTPException):
            self.respond(503, b'{"error":"Mail service unavailable"}')
        finally:
            connection.close()


if __name__ == "__main__":
    Server(("127.0.0.1", 8081), Handler).serve_forever()
