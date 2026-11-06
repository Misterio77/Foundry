from io import BytesIO

from PIL import Image
from tornado.testing import AsyncHTTPTestCase
from tornado.web import Application

from robohash.webfront import ImgHandler


class TestAvatarHTTP(AsyncHTTPTestCase):
    def get_app(self):
        return Application([(r"/(.*)", ImgHandler)])

    def test_kitten_get_and_head(self):
        url = "/" + "4b227777d4dd1fc61c6f884f48641d02b4d121d3fd328cb08b5531fcacdabf8a"
        url += ".png?set=set4&size=200x200"
        response = self.fetch(url)
        assert response.code == 200
        assert response.headers["Content-Type"] == "image/png"
        assert Image.open(BytesIO(response.body)).size == (200, 200)
        assert self.fetch(url).body == response.body

        head = self.fetch(url, method="HEAD")
        assert head.code == 200
        assert head.headers["Content-Type"] == "image/png"
        assert head.body == b""
