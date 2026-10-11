"""Private E2 byte processor. Input is data; no model or prompt interface exists."""

from __future__ import annotations

import base64
import hashlib
import html
from html.parser import HTMLParser
import http.client
import ipaddress
import json
import os
import socket
import shutil
import ssl
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urljoin, urlsplit, urlunsplit
import zlib

import dns.exception
import dns.resolver
from PIL import Image, UnidentifiedImageError

MAX_FILE_BYTES = 10_000_000
MAX_EXPANDED_BYTES = 20_000_000
MAX_TEXT = 100_000
MAX_REDIRECTS = 3
MAX_PAGES = 25
MAX_DIMENSION = 12_000
MAX_PIXELS = 40_000_000
MAX_RATIO = 20
FETCH_SECONDS = 20
PROCESS_SECONDS = 45
CHUNK = 64 * 1024
ALLOWED_MIME = {"image/png", "image/jpeg", "image/webp", "application/pdf", "text/html"}
SPECIAL_NETWORKS = tuple(ipaddress.ip_network(value) for value in (
    "0.0.0.0/8", "100.64.0.0/10", "192.0.0.0/24", "192.88.99.0/24",
    "198.18.0.0/15", "224.0.0.0/4", "240.0.0.0/4", "2001::/23", "2002::/16",
))
OCR_LANGUAGE = {
    "en": "eng", "ar": "ara", "ru": "rus", "kk": "kaz", "ky": "kir",
    "uz": "uzb+uzb_cyrl", "tr": "tur", "id": "ind", "ur": "urd",
    "fr": "fra", "es": "spa", "pt": "por", "sw": "swa", "hi": "hin", "bn": "ben",
}


def ocr_languages(language: str) -> str:
    target = OCR_LANGUAGE.get(language.split("-", 1)[0].lower())
    if target is None:
        raise Rejected("language")
    return "+".join(dict.fromkeys(("eng", "ara", *target.split("+"))))


class Rejected(Exception):
    """Permanent input failure with no user-visible diagnostic detail."""


class TemporaryFailure(Exception):
    """A retryable processing failure."""


@dataclass(frozen=True)
class Fetched:
    body: bytes
    mime: str
    url: str


def safe_url(raw: str) -> str:
    if len(raw) > 2048 or any(ord(c) < 32 or ord(c) == 127 for c in raw):
        raise Rejected("url")
    parts = urlsplit(raw)
    if parts.scheme != "https" or not parts.hostname or parts.username or parts.password:
        raise Rejected("url")
    try:
        if parts.port not in (None, 443):
            raise Rejected("port")
    except ValueError as exc:
        raise Rejected("port") from exc
    if parts.hostname.endswith("."):
        raise Rejected("host")
    try:
        ipaddress.ip_address(parts.hostname)
    except ValueError:
        pass
    else:
        raise Rejected("ip literal")
    return urlunsplit(("https", parts.netloc, parts.path or "/", parts.query, ""))


def bounded_getaddrinfo(host: str, port: int, type: int, deadline: float | None = None):
    resolver = dns.resolver.Resolver()
    resolver.timeout = 1.5
    resolver.lifetime = 3
    answers = []
    for record_type, family in (("A", socket.AF_INET), ("AAAA", socket.AF_INET6)):
        try:
            remaining = min(3, deadline - time.monotonic()) if deadline is not None else 3
            if remaining <= 0: raise TemporaryFailure("dns timeout")
            records = resolver.resolve(host, record_type, lifetime=remaining)
            answers.extend((family, type, 6, "", (str(record), port)) for record in records)
        except dns.resolver.NoAnswer:
            continue
        except (dns.exception.DNSException, OSError) as exc:
            raise TemporaryFailure("dns") from exc
    return answers


def public_addresses(host: str, resolver=bounded_getaddrinfo, deadline: float | None = None) -> list[str]:
    try:
        answers = resolver(host, 443, type=socket.SOCK_STREAM, deadline=deadline) if resolver is bounded_getaddrinfo else resolver(host, 443, type=socket.SOCK_STREAM)
    except OSError as exc:
        raise TemporaryFailure("dns") from exc
    addresses = list(dict.fromkeys(answer[4][0] for answer in answers))
    if not addresses:
        raise TemporaryFailure("dns")
    for address in addresses:
        try:
            parsed = ipaddress.ip_address(address)
            if not parsed.is_global or any(parsed.version == network.version and parsed in network for network in SPECIAL_NETWORKS) or (
                isinstance(parsed, ipaddress.IPv6Address) and (parsed.ipv4_mapped or parsed not in ipaddress.ip_network("2000::/3"))
            ):
                raise Rejected("destination")
        except ValueError as exc:
            raise Rejected("destination") from exc
    return addresses


class PinnedHTTPS(http.client.HTTPSConnection):
    def __init__(self, host: str, address: str, timeout: float):
        super().__init__(host, port=443, timeout=timeout, context=ssl.create_default_context())
        self.address = address

    def connect(self) -> None:
        # The socket never repeats DNS resolution. SNI and certificate checks
        # still use the URL hostname, not the vetted numeric address.
        raw = socket.create_connection((self.address, 443), timeout=self.timeout)
        try:
            self.sock = self._context.wrap_socket(raw, server_hostname=self.host)
        except BaseException:
            raw.close()
            raise


def bounded_body(response: http.client.HTTPResponse, deadline: float) -> bytes:
    encoding = response.getheader("Content-Encoding", "identity").lower().strip()
    if encoding not in {"identity", "gzip", "deflate"}:
        raise Rejected("encoding")
    advertised = response.getheader("Content-Length")
    if advertised:
        try:
            if int(advertised) > MAX_FILE_BYTES:
                raise Rejected("bytes")
        except ValueError as exc:
            raise Rejected("length") from exc
    decoder = zlib.decompressobj(31 if encoding == "gzip" else zlib.MAX_WBITS) if encoding != "identity" else None
    compressed = expanded = 0
    chunks: list[bytes] = []
    while True:
        if time.monotonic() > deadline:
            raise TemporaryFailure("timeout")
        part = response.read1(CHUNK)
        if time.monotonic() > deadline:
            raise TemporaryFailure("timeout")
        if not part:
            break
        compressed += len(part)
        if compressed > MAX_FILE_BYTES:
            raise Rejected("bytes")
        try:
            output = decoder.decompress(part, MAX_EXPANDED_BYTES - expanded + 1) if decoder else part
        except zlib.error as exc:
            raise Rejected("encoding") from exc
        expanded += len(output)
        if expanded > MAX_EXPANDED_BYTES or expanded > max(compressed * MAX_RATIO, CHUNK):
            raise Rejected("expansion")
        chunks.append(output)
    if decoder:
        try:
            tail = decoder.flush(MAX_EXPANDED_BYTES - expanded + 1)
        except zlib.error as exc:
            raise Rejected("encoding") from exc
        expanded += len(tail)
        if not decoder.eof or expanded > MAX_EXPANDED_BYTES or expanded > max(compressed * MAX_RATIO, CHUNK):
            raise Rejected("expansion")
        chunks.append(tail)
    return b"".join(chunks)


def safe_fetch(raw: str, resolver=bounded_getaddrinfo, connection_factory=PinnedHTTPS) -> Fetched:
    current = safe_url(raw)
    visited: set[str] = set()
    deadline = time.monotonic() + FETCH_SECONDS
    for hop in range(MAX_REDIRECTS + 1):
        if current in visited:
            raise Rejected("redirect loop")
        visited.add(current)
        parts = urlsplit(current)
        addresses = public_addresses(parts.hostname or "", resolver, deadline)
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TemporaryFailure("timeout")
        connection = connection_factory(parts.hostname or "", addresses[0], min(5, remaining))
        timer = None
        try:
            connection.connect()
            checked_socket = connection.sock
            def expire():
                if checked_socket:
                    try: checked_socket.shutdown(socket.SHUT_RDWR)
                    except OSError: pass
            timer = threading.Timer(max(0, deadline - time.monotonic()), expire)
            timer.daemon = True
            timer.start()
            target = parts.path + ("?" + parts.query if parts.query else "")
            connection.request("GET", target, headers={
                "Host": parts.hostname or "", "User-Agent": "HadithlyEvidence/1",
                "Accept": "text/html,application/pdf,image/png,image/jpeg,image/webp",
                "Accept-Encoding": "gzip, deflate", "Connection": "close",
            })
            response = connection.getresponse()
            if response.status in (301, 302, 303, 307, 308):
                if hop == MAX_REDIRECTS:
                    raise Rejected("redirect limit")
                location = response.getheader("Location")
                if not location:
                    raise Rejected("redirect")
                current = safe_url(urljoin(current, location))
                continue
            if response.status != 200:
                raise TemporaryFailure("upstream") if response.status >= 500 or response.status == 429 else Rejected("upstream")
            mime = response.getheader("Content-Type", "").split(";")[0].lower().strip()
            if mime not in ALLOWED_MIME:
                raise Rejected("mime")
            body = bounded_body(response, deadline)
            if not body:
                raise Rejected("empty")
            return Fetched(body, mime, current)
        except (socket.timeout, ssl.SSLError, OSError, http.client.HTTPException) as exc:
            raise TemporaryFailure("network") from exc
        finally:
            if timer: timer.cancel()
            connection.close()
    raise Rejected("redirect limit")


def scan_file(path: Path) -> bool:
    """True means infected. Unknown, stale, or scanner errors never mean clean."""
    database = Path(os.environ.get("CLAMAV_DB_DIR", "/var/lib/clamav"))
    daily = [candidate for candidate in (database / "daily.cvd", database / "daily.cld") if candidate.is_file()]
    main = [candidate for candidate in (database / "main.cvd", database / "main.cld") if candidate.is_file()]
    if not daily or not main or time.time() - max(candidate.stat().st_mtime for candidate in daily) > 72 * 60 * 60:
        raise TemporaryFailure("scanner signatures")
    try:
        with tempfile.TemporaryDirectory(prefix="scan-") as directory:
            scan_path = Path(directory) / "source"
            scan_path.write_bytes(path.read_bytes())
            Path(directory).chmod(0o755)
            scan_path.chmod(0o444)
            args = [shutil.which("clamscan") or "clamscan", f"--database={database}", "--no-summary", "--infected", "--max-scansize=50M",
                    "--max-filesize=20M", "--max-recursion=3", "--max-files=50", "--alert-exceeds-max=yes", str(scan_path)]
            identity = {}
            if sys.platform == "linux":
                args = ["prlimit", "--as=2000000000", "--cpu=25", "--", sys.executable, str(Path(__file__).with_name("sandbox_exec.py"))] + args
                identity = {"user": 10002, "group": 10002, "extra_groups": ()}
            result = subprocess.run(args, capture_output=True, timeout=25, check=False, env={"PATH": "/usr/bin:/bin:/opt/homebrew/bin"}, **identity)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise TemporaryFailure("scanner") from exc
    if result.returncode == 1:
        if b"Heuristics.Limits.Exceeded" in result.stdout:
            raise Rejected("scan limit")
        return True
    if result.returncode != 0:
        raise TemporaryFailure("scanner")
    return False


def check_image(path: Path, expected_mime: str | None = None) -> None:
    try:
        with Image.open(path) as image:
            if expected_mime and image.format != {"image/png": "PNG", "image/jpeg": "JPEG", "image/webp": "WEBP"}[expected_mime]:
                raise Rejected("image mime")
            width, height = image.size
            if width < 1 or height < 1 or width > MAX_DIMENSION or height > MAX_DIMENSION or width * height > MAX_PIXELS:
                raise Rejected("dimensions")
            image.verify()
    except (UnidentifiedImageError, OSError, ValueError) as exc:
        raise Rejected("image") from exc


def run_tool(args: list[str], timeout: float, isolated: bool = False) -> str:
    try:
        with tempfile.TemporaryFile() as output:
            if sys.platform == "linux":
                sandbox = [sys.executable, str(Path(__file__).with_name("sandbox_exec.py"))] if isolated else []
                bounded_args = ["prlimit", "--as=700000000", "--fsize=10000000", f"--cpu={60 if isolated else 20}", "--"] + sandbox + args
            else:
                bounded_args = args
            identity = {"user": 10002, "group": 10002, "extra_groups": ()} if isolated and sys.platform == "linux" else {}
            result = subprocess.run(bounded_args, stdout=output, stderr=subprocess.DEVNULL, timeout=timeout, check=False,
                                    env={"PATH": "/usr/bin:/bin:/opt/homebrew/bin" + (":" + os.environ["EVIDENCE_TOOL_DIR"] if "EVIDENCE_TOOL_DIR" in os.environ else ""), "LANG": "C.UTF-8",
                                         "TESSDATA_PREFIX": os.environ.get("TESSDATA_PREFIX", "/usr/share/tesseract-ocr/5/tessdata")}, **identity)
            if output.tell() > 4_000_000:
                raise Rejected("tool output")
            output.seek(0)
            text = output.read().decode("utf-8", "replace")
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise TemporaryFailure("tool") from exc
    if result.returncode != 0:
        raise Rejected("document")
    return text


def ocr_page(path: Path, page: int, deadline: float, languages: str) -> list[dict]:
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise TemporaryFailure("timeout")
    tsv = run_tool(["tesseract", str(path), "stdout", "-l", languages, "tsv"], min(15, remaining))
    spans = []
    characters = 0
    for line in tsv.splitlines()[1:]:
        fields = line.split("\t", 11)
        if len(fields) != 12 or not fields[11].strip():
            continue
        try:
            x, y, width, height = (int(fields[index]) for index in (6, 7, 8, 9))
        except ValueError:
            continue
        spans.append({"text": fields[11].strip(), "source": {"kind": "page_box", "page": page, "x": x, "y": y, "width": width, "height": height}})
        characters += len(fields[11].strip())
        if len(spans) >= 3_000 or characters >= MAX_TEXT:
            raise Rejected("ocr output")
    return spans


def pdf_pages(path: Path, workdir: Path, deadline: float):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise TemporaryFailure("timeout")
    info = run_tool(["pdfinfo", str(path)], min(8, remaining))
    page_line = next((line for line in info.splitlines() if line.startswith("Pages:")), None)
    if not page_line:
        raise Rejected("pdf")
    try:
        count = int(page_line.split(":", 1)[1].strip())
    except ValueError as exc:
        raise Rejected("pdf") from exc
    if count < 1 or count > MAX_PAGES:
        raise Rejected("pages")
    for page in range(1, count + 1):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TemporaryFailure("timeout")
        prefix = workdir / f"page-{page}"
        run_tool(["pdftoppm", "-f", str(page), "-l", str(page), "-singlefile", "-scale-to", "2500", "-png", str(path), str(prefix)], min(12, remaining))
        output = prefix.with_suffix(".png")
        if not output.is_file() or output.stat().st_size > MAX_FILE_BYTES:
            raise Rejected("render")
        check_image(output)
        try:
            yield output
        finally:
            output.unlink(missing_ok=True)


class VisibleHTML(HTMLParser):
    SKIP = {"script", "style", "noscript", "template", "svg", "iframe"}

    def __init__(self, source: str):
        super().__init__(convert_charrefs=False)
        self.source = source
        self.line_starts = [0]
        self.line_starts.extend(index + 1 for index, char in enumerate(source) if char == "\n")
        self.hidden = 0
        self.used = 0
        self.spans: list[dict] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in self.SKIP:
            self.hidden += 1

    def handle_endtag(self, tag: str) -> None:
        if tag in self.SKIP and self.hidden:
            self.hidden -= 1

    def _add(self, raw: str, rendered: str) -> None:
        if self.hidden or not rendered.strip():
            return
        self.used += len(rendered.strip().encode("utf-16-le")) // 2 + 1
        if len(self.spans) >= 3_000 or self.used > MAX_TEXT:
            raise Rejected("html output")
        line, column = self.getpos()
        start = self.line_starts[line - 1] + column
        self.spans.append({"text": rendered.strip(), "source": {"kind": "html_chars", "start": start, "end": start + len(raw)}})

    def handle_data(self, data: str) -> None:
        self._add(data, data)

    def handle_entityref(self, name: str) -> None:
        self._add("&" + name + ";", html.unescape("&" + name + ";"))

    def handle_charref(self, name: str) -> None:
        self._add("&#" + name + ";", html.unescape("&#" + name + ";"))


def extract_clean_file(path: Path, mime: str, languages: str) -> dict:
    deadline = time.monotonic() + PROCESS_SECONDS
    with tempfile.TemporaryDirectory(prefix="extract-") as directory:
        workdir = Path(directory)
        if mime == "text/html":
            parser = VisibleHTML(path.read_bytes().decode("utf-8", "replace"))
            parser.feed(parser.source)
            spans = parser.spans
        elif mime == "application/pdf":
            if not path.read_bytes().startswith(b"%PDF-"):
                raise Rejected("pdf")
            spans = []
            for page, image_path in enumerate(pdf_pages(path, workdir, deadline), start=1):
                spans.extend(ocr_page(image_path, page, deadline, languages))
                if len(spans) > 3_000 or sum(len(entry["text"]) for entry in spans) > MAX_TEXT:
                    raise Rejected("ocr output")
        elif mime in {"image/png", "image/jpeg", "image/webp"}:
            check_image(path, mime)
            spans = ocr_page(path, 1, deadline, languages)
        else:
            raise Rejected("mime")
    text_parts: list[str] = []
    bounded_spans: list[dict] = []
    used = 0
    for span in spans:
        piece = span["text"]
        units = len(piece.encode("utf-16-le")) // 2
        if not piece or used + units + 1 > MAX_TEXT or len(bounded_spans) >= 3_000:
            raise Rejected("output limit")
        if text_parts:
            text_parts.append(" ")
            used += 1
        start = used
        text_parts.append(piece)
        used += units
        bounded_spans.append({"start": start, "end": used, "source": span["source"]})
    return {"text": "".join(text_parts), "spans": bounded_spans}


def extraction(body: bytes, mime: str, final_url: str | None = None, languages: str = "eng+ara") -> dict:
    if len(body) < 1 or len(body) > MAX_EXPANDED_BYTES:
        raise Rejected("bytes")
    if mime != "text/html" and len(body) > MAX_FILE_BYTES:
        raise Rejected("bytes")
    if mime == "text/html" and len(body) > 2_000_000:
        raise Rejected("bytes")
    with tempfile.TemporaryDirectory(prefix="evidence-", dir=os.environ.get("EVIDENCE_WORK_DIR")) as directory:
        workdir = Path(directory)
        path = workdir / "source"
        path.write_bytes(body)
        if scan_file(path):
            return {"kind": "infected"}
        if sys.platform == "linux":
            workdir.chmod(0o755)
            path.chmod(0o444)
            output = run_tool([sys.executable, str(Path(__file__).with_name("extract_worker.py")), str(path), mime, languages], PROCESS_SECONDS, isolated=True)
            extracted = json.loads(output)
            if extracted.get("kind") == "failed":
                raise TemporaryFailure("extractor") if extracted.get("retryable") else Rejected("extractor")
        else:
            extracted = extract_clean_file(path, mime, languages)
    if not isinstance(extracted, dict) or not isinstance(extracted.get("text"), str) or not isinstance(extracted.get("spans"), list) or len(extracted["text"].encode("utf-16-le")) // 2 > MAX_TEXT or len(extracted["spans"]) > 3_000:
        raise Rejected("extractor output")
    return {"kind": "ready", "mime": mime, "sha256": hashlib.sha256(body).hexdigest(), "text": extracted["text"], "spans": extracted["spans"], "finalUrl": final_url,
            **({"sourceBytesBase64": base64.b64encode(body).decode()} if final_url else {})}


def process_request(request: dict) -> dict:
    language = request.get("language", "en")
    if not isinstance(language, str):
        raise Rejected("language")
    languages = ocr_languages(language)
    if request.get("kind") == "url" and isinstance(request.get("url"), str):
        fetched = safe_fetch(request["url"])
        return extraction(fetched.body, fetched.mime, fetched.url, languages)
    if request.get("kind") == "file" and request.get("mime") in ALLOWED_MIME - {"text/html"}:
        try:
            body = base64.b64decode(request["bytesBase64"], validate=True)
        except (KeyError, TypeError, ValueError) as exc:
            raise Rejected("bytes") from exc
        if len(body) > MAX_FILE_BYTES or hashlib.sha256(body).hexdigest() != request.get("sha256"):
            raise Rejected("checksum")
        return extraction(body, request["mime"], languages=languages)
    raise Rejected("request")


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        self.send_response(200 if self.path == "/health" else 404)
        self.end_headers()

    def do_POST(self) -> None:
        if self.path != "/process":
            self.send_error(404)
            return
        try:
            self.connection.settimeout(15)
            size = int(self.headers.get("Content-Length", "0"))
            if size < 1 or size > 14_000_000:
                raise Rejected("request size")
            request = json.loads(self.rfile.read(size))
            if not isinstance(request, dict):
                raise Rejected("request")
            result = process_request(request)
        except Rejected:
            result = {"kind": "failed", "retryable": False}
        except TemporaryFailure:
            result = {"kind": "failed", "retryable": True}
        except (ValueError, UnicodeError, KeyError, TypeError):
            result = {"kind": "failed", "retryable": False}
        except Exception:
            result = {"kind": "failed", "retryable": True}
        data = json.dumps(result, separators=(",", ":")).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format: str, *args: object) -> None:
        # Requests contain private URLs; do not put them in platform logs.
        return


if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as directory:
        control = Path(directory) / "control"
        control.write_text("Hadithly clean scanner control")
        if scan_file(control): raise RuntimeError("scanner control failed")
        control.write_bytes(b"X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*")
        if not scan_file(control): raise RuntimeError("scanner detection failed")
    if sys.platform == "linux":
        probe = "import os,socket\nassert os.getuid()==10002\ntry:\n socket.socket()\nexcept PermissionError:\n print('denied')\nelse:\n raise RuntimeError('network allowed')"
        if run_tool([sys.executable, "-c", probe], 5, isolated=True).strip() != "denied":
            raise RuntimeError("network sandbox unavailable")
    ThreadingHTTPServer(("0.0.0.0", int(os.environ.get("PORT", "8080"))), Handler).serve_forever()
