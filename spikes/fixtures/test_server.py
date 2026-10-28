import json
from pathlib import Path
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from server import make_server


class FixtureServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = make_server(0)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def test_loopback_binding_and_fixture_resources(self):
        self.assertEqual(self.server.server_address[0], "127.0.0.1")
        for path in ["/", "/login.html", "/wallet.html", "/blocking.html", "/wallet.js", "/storage.html", "/storage.js", "/ads/network-probe.js", "/control.js"]:
            with self.subTest(path=path), urlopen(self.base + path) as response:
                self.assertEqual(response.status, 200)
                self.assertEqual(response.headers["Cache-Control"], "no-store")
                self.assertGreater(len(response.read()), 20)

    def test_private_parent_and_directory_listing_unavailable(self):
        for path in ["/../server.py", "/%2e%2e/server.py", "/probe-extension/manifest.json", "/ads/"]:
            with self.subTest(path=path), self.assertRaises(HTTPError) as error:
                urlopen(self.base + path)
            self.assertIn(error.exception.code, [403, 404])
            error.exception.close()

    def test_server_does_not_accept_form_submission(self):
        with self.assertRaises(HTTPError) as error:
            urlopen(Request(self.base + "/", data=b"dummy=true", method="POST"))
        self.assertEqual(error.exception.code, 501)
        error.exception.close()

    def test_synthetic_manifest_resources_exist(self):
        root = Path(__file__).parent / "probe-extension"
        manifest = json.loads((root / "manifest.json").read_text())
        self.assertEqual(manifest["manifest_version"], 3)
        resources = [manifest["background"]["service_worker"], manifest["action"]["default_popup"]]
        resources += [js for entry in manifest["content_scripts"] for js in entry["js"]]
        for resource in resources:
            self.assertTrue((root / resource).is_file(), resource)


if __name__ == "__main__":
    unittest.main()
