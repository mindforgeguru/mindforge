"""
The payment QR code a school uploads is one parents and students can open.

Found 2026-10-16:

- the upload stored `mindforge-profiles/payment/...` and the student and parent
  fee screens were handed a MinIO presigned URL built from it — on the MinIO
  host the backend talks to (`http://minio:9000/...` locally), which no phone
  or browser can reach, so the QR never appeared;
- the object always had the same name, so a replaced QR kept its URL and an
  app that had cached the old image went on showing it;
- unlike a profile photo or the school logo, anything was accepted: an HTML
  file, 30 MB of zeros.

The QR now goes through the logo's checks, gets a fresh name on every upload,
and every response gives it as a media-proxy URL.
"""

import io

import pytest
from PIL import Image

from .conftest import auth
from .test_realtime_delivery import _mint_access_token


def _png(colour="black"):
    buf = io.BytesIO()
    Image.new("RGB", (48, 48), colour).save(buf, format="PNG")
    return buf.getvalue()


def _upload(api, headers, data, name="qr.png", ctype="image/png", slot=1):
    return api.post(f"/api/admin/fees/payment-info/{slot}/qr", headers=headers,
                    files={"file": (name, data, ctype)})


def _path(url):
    """The media URL's path, to fetch it from the API under test."""
    return url[url.index("/api/media/"):]


@pytest.fixture(scope="module")
def admin(two_schools):
    return auth(two_schools["a"]["admin_token"])


@pytest.fixture(scope="module")
def student(students):
    return auth(_mint_access_token(students["a"]))


def test_the_student_gets_a_qr_url_that_opens(api, admin, student):
    r = _upload(api, admin, _png())
    assert r.status_code == 200, r.text
    api.put("/api/admin/fees/payment-info/1", headers=admin, json={"upi_id": "school@upi"})

    r = api.get("/api/student/fees", headers=student)
    assert r.status_code == 200, r.text
    urls = [o["qr_code_url"] for o in r.json()["payment_options"] if o["slot"] == 1]
    assert urls and "/api/media/" in urls[0], urls
    assert "X-Amz-" not in urls[0], "a presigned MinIO URL, not one the app can open"

    img = api.get(_path(urls[0]))
    assert img.status_code == 200
    assert img.headers["content-type"] == "image/png"


def test_the_admin_sees_the_same_kind_of_url(api, admin):
    r = api.get("/api/admin/fees/payment-info", headers=admin)
    assert r.status_code == 200
    url = next(o["qr_code_url"] for o in r.json() if o["slot"] == 1)
    assert "/api/media/" in url, url


def test_a_replaced_qr_has_a_new_url_and_the_old_one_is_gone(api, admin):
    first = _upload(api, admin, _png("red"), slot=2).json()["qr_code_url"]
    second = _upload(api, admin, _png("green"), slot=2).json()["qr_code_url"]
    assert first != second
    assert api.get(_path(second)).status_code == 200
    assert api.get(_path(first)).status_code == 404


@pytest.mark.parametrize("name,data,ctype", [
    ("page.html", b"<script>alert(1)</script>", "text/html"),
    ("qr.png", b"not an image at all", "image/png"),
], ids=["html", "not an image"])
def test_a_qr_that_is_not_an_image_is_refused(api, admin, name, data, ctype):
    assert _upload(api, admin, data, name, ctype, slot=3).status_code == 400


def test_an_oversized_qr_is_refused(api, admin):
    r = _upload(api, admin, b"\0" * (6 * 1024 * 1024), slot=3)
    assert r.status_code in (400, 413), r.status_code
