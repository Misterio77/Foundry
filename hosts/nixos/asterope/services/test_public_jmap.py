import http.client
import importlib.util
import json
import threading
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

spec = importlib.util.spec_from_file_location(
    "public_jmap", Path(__file__).with_name("public-jmap.py")
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PublicJmapTest(unittest.TestCase):
    def setUp(self):
        self.server = module.Server(("127.0.0.1", 0), module.Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def request(self, body, path="/jmap/"):
        connection = http.client.HTTPConnection(*self.server.server_address, timeout=3)
        connection.request("POST", path, body, {"Authorization": "Bearer test"})
        response = connection.getresponse()
        result = response.status, response.read()
        connection.close()
        return result

    def test_management_capability_rejected(self):
        status, _ = self.request(json.dumps({"using": ["urn:stalwart:jmap"]}))
        self.assertEqual(status, 403)

    def test_management_method_rejected_without_capability(self):
        status, _ = self.request('{"methodCalls":[["x\\u003aDomain/get",{},"0"]]}')
        self.assertEqual(status, 403)

    def test_invalid_requests_rejected(self):
        for body in ("", "not json", "null", "[]", '{"methodCalls":[[]]}'):
            with self.subTest(body=body):
                self.assertEqual(self.request(body)[0], 400)

    def test_alternate_paths_rejected(self):
        self.assertEqual(self.request("{}", "/jmap/session")[0], 400)

    def test_standard_mail_request_forwarded(self):
        body = json.dumps({"methodCalls": [["Mailbox/get", {"accountId": "b"}, "0"]]})
        response = MagicMock(status=200)
        response.read.return_value = b'{"methodResponses":[]}'
        response.getheaders.return_value = [("Content-Length", "22")]
        # Preserve the real connection used by the test client.
        original = http.client.HTTPConnection
        upstream = MagicMock()
        upstream.getresponse.return_value = response

        def connect(host, *args, **kwargs):
            if host == "127.0.0.1" and args == (8080,):
                return upstream
            return original(host, *args, **kwargs)

        with patch.object(module.http.client, "HTTPConnection", side_effect=connect):
            self.assertEqual(self.request(body), (200, b'{"methodResponses":[]}'))
        upstream.request.assert_called_once_with(
            "POST",
            "/jmap/",
            body=body.encode(),
            headers={"Authorization": "Bearer test", "Host": self.request_host},
        )

    @property
    def request_host(self):
        return f"127.0.0.1:{self.server.server_address[1]}"


if __name__ == "__main__":
    unittest.main()
