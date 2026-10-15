"""Local stand-in for Miniflux and Google Reader APIs, for end-to-end client checks.

Serves deterministic feeds, paged entries with HTML image content, generated PNG
images, read/star writes and unread counters on 127.0.0.1. Nothing is sent to
the network and nothing is written to disk. Optional failure injection:

    python3 scripts/stub-rss-server.py                  # http://127.0.0.1:8787
    python3 scripts/stub-rss-server.py --port 9000 --entries 300
    python3 scripts/stub-rss-server.py --rate-limit 5   # every 5th request gets 429
    python3 scripts/stub-rss-server.py --fail-writes    # writes return 503

Miniflux: base URL http://127.0.0.1:8787, API key "stub-token".
Google Reader: base URL http://127.0.0.1:8787/api/greader.php, user "reader", password "secret".
Proxy images use the public origin https://miniflux.example.com (fill it in as the
"service public address" to test the /proxy/ mapping).
"""

import argparse
import json
import random
import re
import struct
import threading
import time
import zlib
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, quote, unquote, urlsplit

API_KEY = "stub-token"
GREADER_USER = "reader"
GREADER_PASSWORD = "secret"
GREADER_TOKEN = "greader-token"
PUBLIC_ORIGIN = "https://miniflux.example.com"

CATEGORIES = [{"id": 1, "title": "插画"}, {"id": 2, "title": "摄影"}]
FEEDS = [
    {"id": 1, "title": "Sora Studio", "category": 1, "site": "https://example.com/sora"},
    {"id": 2, "title": "夜行列车", "category": 1, "site": "https://example.com/yako"},
    {"id": 3, "title": "Street Frames", "category": 2, "site": "https://example.com/frames"},
    {"id": 4, "title": "Proxy Feed", "category": 2, "site": "https://example.com/proxy-feed"},
]
COLORS = [(232, 99, 120), (90, 140, 210), (240, 180, 80), (70, 170, 140), (150, 110, 200), (60, 60, 70)]
SIZES = [(600, 900), (800, 600), (600, 600), (500, 1100), (900, 500)]


class State:
    """In-memory articles; writes change read/star state like a real service."""

    def __init__(self, count):
        self.lock = threading.Lock()
        self.requests = 0
        rng = random.Random(20261015)
        now = datetime(2026, 10, 15, 12, 0, tzinfo=timezone.utc)
        self.entries = []
        for index in range(count):
            entry_id = 1000 + count - index
            feed = FEEDS[index % len(FEEDS)]
            images = []
            for n in range(rng.choice([1, 1, 1, 2, 3, 4])):
                width, height = rng.choice(SIZES)
                images.append((f"/img/{entry_id}-{n}-{width}x{height}.png", width, height))
            self.entries.append({
                "id": entry_id,
                "feed_id": feed["id"],
                "title": f"{feed['title']} #{entry_id}",
                "author": feed["title"],
                "url": f"{feed['site']}/{entry_id}",
                "published_at": (now - timedelta(hours=index * 3)).strftime("%Y-%m-%dT%H:%M:%S.%f000+00:00"),
                "status": "unread" if index % 3 else "read",
                "starred": index % 11 == 0,
                "images": images,
                "text_only": index % 17 == 5,
            })

    def content(self, entry, base):
        if entry["text_only"]:
            return f"<p>这篇没有图片。</p><p>{entry['title']}</p>"
        parts = [f"<p>{entry['title']}</p>"]
        for n, (path, width, height) in enumerate(entry["images"]):
            if entry["feed_id"] == 4:
                encoded = quote(f"{base}{path}", safe="")
                # Miniflux 媒体代理：正文里的地址使用服务配置的公开地址
                parts.append(f'<img src="{PUBLIC_ORIGIN}/proxy/stub/{encoded}">')
            elif n % 2:
                parts.append(f'<img src="data:image/gif;base64,R0lGOD" data-src="{base}{path}" width="{width}" height="{height}">')
            else:
                parts.append(f'<figure><img src="{base}{path}"><figcaption>第 {n + 1} 张</figcaption></figure>')
        # 追踪像素
        parts.append(f'<img src="{base}/pixel.gif" width="1" height="1">')
        return "".join(parts)


def png(width, height, color):
    """Solid vertical gradient PNG built with the standard library."""
    rows = []
    for y in range(height):
        shade = 0.65 + 0.35 * (y / max(1, height - 1))
        pixel = bytes(min(255, int(channel * shade)) for channel in color)
        rows.append(b"\x00" + pixel * width)
    raw = zlib.compress(b"".join(rows), 6)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", raw) + chunk(b"IEND", b"")


class Handler(BaseHTTPRequestHandler):
    server_version = "AlbumRSSStub/1"
    state = None
    options = None

    def log_message(self, format, *args):
        # 只记录方法、路径和状态码，不输出凭据或正文
        print(f"{self.command} {urlsplit(self.path).path} -> {args[1] if len(args) > 1 else ''}", flush=True)

    def send(self, status, body=b"", content_type="application/json", headers=None):
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False).encode()
        elif isinstance(body, str):
            body = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length else b""

    def base(self):
        return f"http://{self.headers.get('Host', '127.0.0.1')}"

    def limited(self):
        with self.state.lock:
            self.state.requests += 1
            count = self.state.requests
        every = self.options.rate_limit
        if every and count % every == 0:
            self.send(429, {"error": "rate limited"}, headers={"Retry-After": "1"})
            return True
        return False

    def do_GET(self):
        self.route("GET")

    def do_PUT(self):
        self.route("PUT")

    def do_POST(self):
        self.route("POST")

    def route(self, method):
        url = urlsplit(self.path)
        path = url.path
        query = parse_qs(url.query, keep_blank_values=True)
        if path.startswith("/img/") or path.startswith("/proxy/"):
            return self.image(path)
        if path == "/pixel.gif":
            return self.send(200, b"GIF89a\x01\x00\x01\x00\x00\x00\x00;", "image/gif")
        if self.limited():
            return
        if path.startswith("/api/greader.php"):
            return self.greader(method, path[len("/api/greader.php"):], query)
        if path.startswith("/v1/"):
            if self.headers.get("X-Auth-Token") != API_KEY:
                return self.send(401, {"error_message": "Access Unauthorized"})
            return self.miniflux(method, path, query)
        return self.send(404, {"error": "not found"})

    def image(self, path):
        if path.startswith("/proxy/"):
            target = unquote(path.split("/", 3)[-1])
            path = urlsplit(target).path
        match = re.match(r"/img/(\d+)-(\d+)-(\d+)x(\d+)\.png$", path)
        if not match:
            return self.send(404, b"", "text/plain")
        entry_id, index, width, height = (int(value) for value in match.groups())
        color = COLORS[(entry_id + index) % len(COLORS)]
        time.sleep(0.05)
        return self.send(200, png(width, height, color), "image/png", {"Cache-Control": "max-age=3600"})

    # ---- Miniflux ----

    def miniflux_entry(self, entry):
        return {
            "id": entry["id"], "feed_id": entry["feed_id"], "title": entry["title"], "author": entry["author"],
            "url": entry["url"], "content": self.state.content(entry, self.base()),
            "published_at": entry["published_at"], "status": entry["status"], "starred": entry["starred"],
            "enclosures": None,
        }

    def miniflux(self, method, path, query):
        state = self.state
        if method == "GET" and path == "/v1/me":
            return self.send(200, {"id": 1, "username": "stub"})
        if method == "GET" and path == "/v1/feeds":
            return self.send(200, [
                {"id": feed["id"], "title": feed["title"], "site_url": feed["site"], "feed_url": feed["site"] + "/rss",
                 "category": {"id": feed["category"], "title": next(c["title"] for c in CATEGORIES if c["id"] == feed["category"])},
                 "checked_at": "2026-10-15T11:00:00Z", "parsing_error_count": 2 if feed["id"] == 3 else 0,
                 "parsing_error_message": "stub: timeout" if feed["id"] == 3 else ""}
                for feed in FEEDS
            ])
        if method == "GET" and path == "/v1/categories":
            return self.send(200, CATEGORIES)
        if method == "GET" and path == "/v1/feeds/counters":
            unreads = {}
            for entry in state.entries:
                if entry["status"] == "unread":
                    unreads[str(entry["feed_id"])] = unreads.get(str(entry["feed_id"]), 0) + 1
            return self.send(200, {"reads": {}, "unreads": unreads})
        match = re.match(r"^/v1/(?:feeds/(\d+)/|categories/(\d+)/)?entries$", path)
        if method == "GET" and match:
            feed_id, category_id = match.groups()
            statuses = query.get("status", ["read", "unread"])
            limit = int(query.get("limit", ["100"])[0])
            before = int(query.get("before_entry_id", ["0"])[0] or 0)
            starred = query.get("starred", [""])[0] == "true"
            feeds_in_category = {feed["id"] for feed in FEEDS if category_id and feed["category"] == int(category_id)}
            items = [
                entry for entry in state.entries
                if entry["status"] in statuses
                and (not feed_id or entry["feed_id"] == int(feed_id))
                and (not category_id or entry["feed_id"] in feeds_in_category)
                and (not starred or entry["starred"])
                and (not before or entry["id"] < before)
            ]
            items.sort(key=lambda entry: entry["id"], reverse=True)
            page = items[:limit]
            return self.send(200, {"total": len(items), "entries": [self.miniflux_entry(entry) for entry in page]})
        match = re.match(r"^/v1/entries/(\d+)$", path)
        if method == "GET" and match:
            entry = next((e for e in state.entries if e["id"] == int(match.group(1))), None)
            return self.send(200, self.miniflux_entry(entry)) if entry else self.send(404, {"error_message": "not found"})
        if method == "PUT" and path == "/v1/entries":
            if self.options.fail_writes:
                return self.send(503, {"error_message": "unavailable"})
            payload = json.loads(self.body() or b"{}")
            ids = set(payload.get("entry_ids", []))
            with state.lock:
                for entry in state.entries:
                    if entry["id"] in ids:
                        entry["status"] = payload.get("status", entry["status"])
            print(f"  status {payload.get('status')} -> {sorted(ids)}", flush=True)
            return self.send(204)
        match = re.match(r"^/v1/entries/(\d+)/bookmark$", path)
        if method == "PUT" and match:
            if self.options.fail_writes:
                return self.send(503, {"error_message": "unavailable"})
            with state.lock:
                for entry in state.entries:
                    if entry["id"] == int(match.group(1)):
                        entry["starred"] = not entry["starred"]
                        print(f"  starred {entry['id']} -> {entry['starred']}", flush=True)
            return self.send(204)
        if method == "PUT" and re.match(r"^/v1/feeds/\d+/refresh$", path):
            return self.send(204)
        return self.send(404, {"error_message": "not found"})

    # ---- Google Reader ----

    def greader(self, method, path, query):
        state = self.state
        if path == "/accounts/ClientLogin" and method == "POST":
            form = parse_qs(self.body().decode())
            if form.get("Email") == [GREADER_USER] and form.get("Passwd") == [GREADER_PASSWORD]:
                return self.send(200, f"SID=stub\nLSID=stub\nAuth={GREADER_TOKEN}\n", "text/plain")
            return self.send(401, "Error=BadAuthentication\n", "text/plain")
        if self.headers.get("Authorization") != f"GoogleLogin auth={GREADER_TOKEN}":
            return self.send(401, "Unauthorized", "text/plain")
        if path == "/reader/api/0/subscription/list":
            return self.send(200, {"subscriptions": [
                {"id": f"feed/{feed['id']}", "title": feed["title"], "htmlUrl": feed["site"], "url": feed["site"] + "/rss",
                 "categories": [{"id": f"user/-/label/{next(c['title'] for c in CATEGORIES if c['id'] == feed['category'])}",
                                 "label": next(c["title"] for c in CATEGORIES if c["id"] == feed["category"])}]}
                for feed in FEEDS
            ]})
        if path == "/reader/api/0/unread-count":
            counts = {}
            for entry in state.entries:
                if entry["status"] == "unread":
                    counts[entry["feed_id"]] = counts.get(entry["feed_id"], 0) + 1
            return self.send(200, {"max": 1000, "unreadcounts": [{"id": f"feed/{fid}", "count": count} for fid, count in counts.items()]})
        if path.startswith("/reader/api/0/stream/contents/"):
            stream = unquote(path[len("/reader/api/0/stream/contents/"):])
            limit = int(query.get("n", ["20"])[0])
            offset = int(query.get("c", ["0"])[0] or 0)
            exclude_read = query.get("xt", [""])[0].endswith("/state/com.google/read")
            items = [entry for entry in state.entries if not (exclude_read and entry["status"] == "read")]
            if stream.startswith("feed/"):
                items = [entry for entry in items if entry["feed_id"] == int(stream[5:])]
            elif "/label/" in stream:
                title = stream.split("/label/", 1)[1]
                category = next((c["id"] for c in CATEGORIES if c["title"] == title), None)
                items = [entry for entry in items if any(f["id"] == entry["feed_id"] and f["category"] == category for f in FEEDS)]
            elif stream.endswith("/state/com.google/starred"):
                items = [entry for entry in items if entry["starred"]]
            items.sort(key=lambda entry: entry["id"], reverse=True)
            page = items[offset:offset + limit]
            body = {"items": [{
                "id": f"tag:google.com,2005:reader/item/{entry['id']:016x}",
                "title": entry["title"], "author": entry["author"],
                "published": int(datetime.fromisoformat(entry["published_at"].replace("000+00:00", "+00:00")).timestamp()),
                "canonical": [{"href": entry["url"]}], "origin": {"streamId": f"feed/{entry['feed_id']}"},
                "summary": {"content": state.content(entry, self.base())},
                "categories": ["user/-/state/com.google/reading-list"]
                + (["user/-/state/com.google/read"] if entry["status"] == "read" else [])
                + (["user/-/state/com.google/starred"] if entry["starred"] else []),
            } for entry in page]}
            if offset + limit < len(items):
                body["continuation"] = str(offset + limit)
            return self.send(200, body)
        if path == "/reader/api/0/token":
            return self.send(200, "stub-csrf\n", "text/plain")
        if path == "/reader/api/0/edit-tag" and method == "POST":
            if self.options.fail_writes:
                return self.send(503, "unavailable", "text/plain")
            form = parse_qs(self.body().decode())
            if form.get("T") != ["stub-csrf"]:
                return self.send(401, "bad token", "text/plain")
            ids = {int(item.rsplit("/", 1)[1], 16) for item in form.get("i", [])}
            tag = (form.get("a") or form.get("r") or [""])[0]
            add = "a" in form
            with state.lock:
                for entry in state.entries:
                    if entry["id"] in ids:
                        if tag.endswith("/read"):
                            entry["status"] = "read" if add else "unread"
                        if tag.endswith("/starred"):
                            entry["starred"] = add
            print(f"  {'add' if add else 'remove'} {tag.rsplit('/', 1)[-1]} -> {sorted(ids)}", flush=True)
            return self.send(200, "OK", "text/plain")
        return self.send(404, "not found", "text/plain")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--entries", type=int, default=240)
    parser.add_argument("--rate-limit", type=int, default=0, help="every Nth API request returns 429")
    parser.add_argument("--fail-writes", action="store_true", help="read/star writes return 503")
    options = parser.parse_args()
    Handler.state = State(options.entries)
    Handler.options = options
    server = ThreadingHTTPServer(("127.0.0.1", options.port), Handler)
    print(f"Stub RSS service on http://127.0.0.1:{options.port} (Ctrl+C to stop)", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
