"""Read-only local Miniflux API checks. Never print credentials or article content."""

import base64
import json
import re
import sys
import urllib.error
import urllib.request
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin, urlsplit, urlunsplit


BASE = "http://localhost:8880"
ORIGIN = "http://localhost:5173"
COMPOSE = Path(r"D:\CodeProject\Develop Environment\miniflux\docker-compose.yaml")

# Sent without the system proxy: the local entry point is not reachable through
# it, and routing a localhost check through an external proxy defeats the point.
# Shared by every script in this directory.
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))

MUTATING_METHODS = {"POST", "PUT", "PATCH", "DELETE"}

# Paths allowed to change state while write mode is off: the temporary API key
# that the authentication check creates and deletes. Anything else is refused.
STATE_ALLOWLIST = ("/v1/api-keys",)

# Every request issued through send() is recorded here so a run can show which
# state-changing calls it made instead of asking the reader to trust the source.
REQUEST_LEDGER = []


def config_value(name):
    match = re.search(r"^\s+" + name + r":\s*(.*?)\s*$", COMPOSE.read_text(encoding="utf-8"), re.M)
    if not match:
        raise RuntimeError(f"Missing configuration field: {name}")
    value = match.group(1)
    if value.startswith('"') and value.endswith('"'):
        return json.loads(value)
    if value.startswith("'") and value.endswith("'"):
        return value[1:-1].replace("''", "'")
    return value


class Images(HTMLParser):
    def __init__(self):
        super().__init__()
        self.images = []

    def handle_starttag(self, tag, attrs):
        if tag == "img":
            self.images.append(dict(attrs))


def split_header_tokens(value):
    """'X-Auth-Token, Authorization' -> {'x-auth-token', 'authorization'}.

    Access-Control-Allow-Headers and Access-Control-Allow-Methods are
    comma-separated lists and are case-insensitive, so compare them as token
    sets instead of substring-matching the raw header value.
    """
    return {token.strip().lower() for token in (value or "").split(",") if token.strip()}


def assertion(name, ok, expected=None, actual=None, required=None, missing=None, severity="error"):
    """Return one assertion record instead of raising, so a single bad header
    does not hide the remaining assertions on the same response."""
    return {"name": name, "ok": bool(ok), "severity": severity,
            "expected": expected, "actual": actual,
            "required": sorted(required) if required else None,
            "missing": sorted(missing) if missing else None}


def subset_assertion(name, required, allow_header_value):
    """Assert a CORS allow-list header contains every required token."""
    actual = split_header_tokens(allow_header_value)
    missing = {token.lower() for token in required} - actual
    return assertion(name, not missing, required=required,
                     actual=sorted(actual), missing=missing)


def enforce_read_only(method, path, allow_write):
    if allow_write or method not in MUTATING_METHODS:
        return
    if not path.startswith(STATE_ALLOWLIST):
        raise RuntimeError(f"read-only mode refused {method} {path}")


def send(method, path, headers=None, body=None, timeout=20, allow_write=False, base=None):
    """One HTTP request, recorded in REQUEST_LEDGER.

    Returns (status, headers, body). Error responses are returned rather than
    raised because several checks expect 4xx.
    """
    enforce_read_only(method, path, allow_write)
    REQUEST_LEDGER.append(f"{method} {path}")
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request((base or BASE) + path, method=method, data=data,
                                     headers=headers or {})
    try:
        with OPENER.open(request, timeout=timeout) as response:
            return response.status, response.headers, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.headers, error.read()


def main():
    # Redirected stdout falls back to the locale encoding (cp936 on this
    # machine). The output is declared UTF-8 JSON, so write it as UTF-8.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    username = config_value("ADMIN_USERNAME")
    password = config_value("ADMIN_PASSWORD")
    basic = base64.b64encode(f"{username}:{password}".encode()).decode()
    result = {"base": BASE, "origin": ORIGIN}

    def get(path):
        status, headers, body = send("GET", path, headers={"Authorization": "Basic " + basic,
                                                          "Origin": ORIGIN})
        metadata = {"status": status,
                    "allow_origin": headers.get("Access-Control-Allow-Origin")}
        return metadata, json.loads(body) if body and status < 400 else None

    metadata, me = get("/v1/me")
    result["authentication"] = metadata
    if me is None:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return
    metadata, version = get("/v1/version")
    result["version"] = {**metadata, "version": version.get("version") if version else None}
    metadata, feeds = get("/v1/feeds")
    result["feeds"] = {**metadata, "count": len(feeds) if feeds is not None else None}
    if feeds is not None:
        result["feed_details"] = []
        for feed in feeds:
            _, sample = get(f"/v1/feeds/{feed['id']}/entries?limit=1")
            result["feed_details"].append({"id": str(feed["id"]), "feed_url": feed["feed_url"],
                                          "parsing_error_count": feed.get("parsing_error_count"),
                                          "entry_count": sample.get("total") if sample else None})
    metadata, entries = get("/v1/entries?limit=200&order=id&direction=desc")
    result["entries"] = metadata
    if entries:
        parsed = []
        image_candidates = []
        sampled_feeds = set()
        for entry in entries["entries"]:
            parser = Images()
            parser.feed(entry.get("content", ""))
            for image in parser.images:
                if image.get("src"):
                    url = urljoin(entry["url"], image["src"])
                    if entry["feed_id"] not in sampled_feeds:
                        image_candidates.append((entry["feed_id"], url))
                        sampled_feeds.add(entry["feed_id"])
            attachments = [item for item in entry.get("enclosures") or []
                           if item.get("mime_type", "").startswith("image/")]
            parsed.append({"id": str(entry["id"]), "image_tags": len(parser.images),
                           "image_attachments": len(attachments),
                           "srcset_tags": sum("srcset" in image for image in parser.images)})
        result["entries"].update({"total": entries["total"], "sampled": len(parsed),
                                  "with_images": sum(bool(e["image_tags"] or e["image_attachments"])
                                                     for e in parsed),
                                  "image_tag_count": sum(e["image_tags"] for e in parsed),
                                  "multi_image_entries": sum(e["image_tags"] > 1 for e in parsed),
                                  "image_examples": [e for e in parsed if e["image_tags"] or e["image_attachments"]][:5]})
        result["media_http_samples"] = []
        configured = urlsplit(config_value("BASE_URL"))
        for feed_id, url in image_candidates:
            original = urlsplit(url)
            # A BASE_URL without a scheme yields an empty netloc, which compares
            # equal to any relative image src. Requiring a real netloc keeps a
            # bare-path src from being mistaken for a local proxy address.
            same_host = bool(configured.netloc) and original.netloc == configured.netloc
            # Only the media proxy route belongs to Miniflux. Another path on
            # the same host is a different service and must not be rewritten.
            local_rewrite = same_host and original.path.startswith("/proxy/")
            sample = {"feed_id": str(feed_id), "original_host": original.netloc or None,
                      "host": original.netloc, "local_proxy_rewrite": local_rewrite}
            if local_rewrite:
                local = urlsplit(BASE)
                url = urlunsplit((local.scheme, local.netloc, original.path, original.query, ""))
                sample["host"] = urlsplit(url).netloc
            elif same_host:
                # Same host, but not the proxy route. Skip instead of fetching:
                # the promise in docs/local-connectivity.md is that this check
                # never contacts the configured public instance.
                sample["host"] = None
                sample["skipped"] = "same_host_without_proxy_path"
                result["media_http_samples"].append(sample)
                continue
            request = urllib.request.Request(url, headers={"Origin": ORIGIN, "Range": "bytes=0-65535"})
            try:
                with OPENER.open(request, timeout=15) as response:
                    data = response.read(65536)
                    sample.update({"status": response.status,
                                   "content_type": response.headers.get("Content-Type"),
                                   "allow_origin": response.headers.get("Access-Control-Allow-Origin"),
                                   "sample_bytes": len(data)})
            except urllib.error.HTTPError as error:
                sample["status"] = error.code
            except urllib.error.URLError as error:
                # urllib wraps socket failures, timeouts included, in URLError.
                timed_out = isinstance(error.reason, TimeoutError)
                sample["error"] = "timeout" if timed_out else "network_error"
                sample["error_type"] = type(error.reason).__name__
                sample["error_reason"] = str(error.reason)
                sample["error_code"] = (getattr(error.reason, "winerror", None)
                                        or getattr(error.reason, "errno", None))
            except TimeoutError:
                sample["error"] = "timeout"
                sample["error_type"] = "TimeoutError"
            result["media_http_samples"].append(sample)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
