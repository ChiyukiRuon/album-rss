"""Add the user-provided feeds to the empty local test instance."""

import base64
import importlib.util
import json
import urllib.error
import urllib.request
from pathlib import Path

spec = importlib.util.spec_from_file_location("local_check", Path(__file__).with_name("check-local-miniflux.py"))
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)

FEEDS = [
    "https://rsshub.chiyukiruon.top/twitter/media/yokaikasa",
    "https://rsshub.chiyukiruon.top/twitter/media/__Nailis__",
    "https://rsshub.chiyukiruon.top/pixiv/user/77632588",
    "https://rsshub.chiyukiruon.top/pixiv/user/65407506",
    "https://rsshub.chiyukiruon.top/bilibili/user/dynamic/436197902",
    "https://rsshub.chiyukiruon.top/bilibili/user/dynamic/2119892830",
]

opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
auth = base64.b64encode(f"{check.config_value('ADMIN_USERNAME')}:{check.config_value('ADMIN_PASSWORD')}".encode()).decode()

request = urllib.request.Request(check.BASE + "/v1/feeds", headers={"Authorization": "Basic " + auth})
with opener.open(request, timeout=20) as response:
    existing = {feed["feed_url"] for feed in json.load(response)}

for url in FEEDS:
    if url in existing:
        print(json.dumps({"feed": url, "result": "already_exists"}), flush=True)
        continue
    request = urllib.request.Request(check.BASE + "/v1/feeds", method="POST",
                                     data=json.dumps({"feed_url": url}).encode(),
                                     headers={"Authorization": "Basic " + auth,
                                              "Content-Type": "application/json"})
    try:
        with opener.open(request, timeout=90) as response:
            data = json.load(response)
            print(json.dumps({"feed": url, "status": response.status, "feed_id": data.get("feed_id")}), flush=True)
    except urllib.error.HTTPError as error:
        # A proxy timeout does not prove that the upstream creation failed.
        verify = urllib.request.Request(check.BASE + "/v1/feeds", headers={"Authorization": "Basic " + auth})
        try:
            with opener.open(verify, timeout=20) as response:
                created = any(feed["feed_url"] == url for feed in json.load(response))
        except (urllib.error.URLError, TimeoutError):
            created = False
        print(json.dumps({"feed": url, "status": error.code,
                          "result": "exists_after_http_error" if created else "not_confirmed"}), flush=True)
    except (urllib.error.URLError, TimeoutError):
        print(json.dumps({"feed": url, "result": "request_failed_or_timed_out"}), flush=True)
