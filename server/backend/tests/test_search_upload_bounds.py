"""Exercise the production multipart reader through FastAPI."""
import unittest
from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient
from backend.app.config import MAX_UPLOAD_BYTES
from backend.app.search_upload import read_search_photo


class SearchUploadTests(unittest.TestCase):
    def setUp(self):
        app = FastAPI()

        @app.post('/')
        def probe(photo=Depends(read_search_photo)):
            data, crop = photo
            return [len(data), crop]

        self.client = TestClient(app)
        self.addCleanup(self.client.close)

    def test_file_and_crop(self):
        response = self.client.post('/', files={'file': ('p.jpg', b'photo')}, data={'crop': '0,0,1,1'})
        self.assertEqual(response.json(), [5, '0,0,1,1'])

    def test_exact_file_limit(self):
        response = self.client.post('/', files={'file': ('p.jpg', bytes(MAX_UPLOAD_BYTES))})
        self.assertEqual(response.json(), [MAX_UPLOAD_BYTES, ''])

    def test_oversize_file(self):
        response = self.client.post('/', files={'file': ('p.jpg', bytes(MAX_UPLOAD_BYTES + 1))})
        self.assertEqual(response.status_code, 413)

    def test_streamed_body_limit(self):
        def chunks():
            yield b'--s\r\nContent-Disposition: form-data; name="file"; filename="p"\r\n\r\n'
            for _ in range(9):
                yield bytes(1024 * 1024)
            yield b'\r\n--s--\r\n'
        response = self.client.post('/', content=chunks(), headers={'Content-Type': 'multipart/form-data; boundary=s'})
        self.assertEqual(response.status_code, 413)

    def test_missing_file(self):
        self.assertEqual(self.client.post('/', files={'other': ('p.jpg', b'p')}).status_code, 422)
