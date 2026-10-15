"""Verify real browser CORS and image loading; credentials stay in memory.

Serves a page on the recorded test origin (http://localhost:5173) and drives a
headless browser at it. The page posts its report back to the local server
instead of the result being scraped out of --dump-dom: under
--virtual-time-budget the page's setTimeout callbacks fire in virtual time, so
image-load timeouts expire almost immediately and healthy images get reported as
failures.

Failures are reported as a named stage with a hint, because "the browser did not
work" is not actionable.

Never prints credentials.
"""

import argparse
import base64
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

spec = importlib.util.spec_from_file_location("local_check",
                                              Path(__file__).with_name("check-local-miniflux.py"))
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)

JSON_HEADERS = {"Content-Type": "application/json"}

BROWSER_CANDIDATES = [
    ("Edge", r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"),
    ("Edge", r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"),
    ("Chrome", r"C:\Program Files\Google\Chrome\Application\chrome.exe"),
    ("Chrome", r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"),
    ("Chrome", os.path.expandvars(r"%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe")),
]

BASE_FLAGS = [
    "--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check",
    "--no-proxy-server", "--disable-extensions", "--disable-background-networking",
    "--disable-sync", "--disable-default-apps", "--disable-component-update",
    "--metrics-recording-only", "--no-pings", "--mute-audio", "--disable-renderer-backgrounding",
    "--disable-backgrounding-occluded-windows",
]

# Added only if the standard flag set produces no result. The sandbox and GPU
# subprocesses are a known startup failure on this machine, and these weaken
# isolation. Acceptable for a throwaway profile driving a localhost page, but it
# is reported so the weaker mode is never silent.
REDUCED_ISOLATION_FLAGS = ["--no-sandbox", "--disable-gpu-sandbox", "--in-process-gpu"]

WAIT_SECONDS = 90

STAGE_HINTS = {
    "browser_not_found": "未找到 Edge 或 Chrome 可执行文件；用 --browser 指定路径",
    "bind_failed": "端口被占用；用 --port 换一个端口（注意文档记录的 Origin 会随之改变）",
    "browser_spawn_failed": "浏览器进程无法启动，见 diagnostics.stderr_tail",
    "no_page_result": "浏览器启动了但页面没有回传结果；见 diagnostics 与 stderr_tail",
    "page_reported_error": "页面已运行，但原生 API 请求失败，见 browser_check.native_error",
    "page_timeout_no_postback": "页面未在等待时间内回传结果",
}


def find_browser(explicit=None):
    if explicit:
        return ("custom", explicit) if Path(explicit).exists() else (None, None)
    for name, path in BROWSER_CANDIDATES:
        if Path(path).exists():
            return name, path
    for command, name in (("msedge", "Edge"), ("chrome", "Chrome")):
        found = shutil.which(command)
        if found:
            return name, found
    return None, None


def build_page(auth_headers, auth_type):
    return """<!doctype html><meta charset="utf-8"><pre id="result">running</pre>
<script>
(async () => {
 const base = __BASE__;
 const headers = __AUTH_HEADERS__;
 const report = {origin: location.origin, authentication: __AUTH_TYPE__, stage: 'start'};
 async function read(path) {
   const r = await fetch(base + path, {headers, credentials:'omit', signal:AbortSignal.timeout(15000)});
   if (!r.ok) throw new Error('HTTP ' + r.status);
   return r.json();
 }
 try {
   report.stage = 'native_auth';
   await read('/v1/me');
   report.native_auth = 'passed';
   report.stage = 'feeds';
   const feeds = await read('/v1/feeds');
   report.feed_count = feeds.length;
   report.stage = 'entries';
   const entries = await read('/v1/entries?limit=100&order=id&direction=desc');
   report.entry_total = entries.total;
   report.stage = 'images';
   const images = [];
   const serverOrigin = new URL(__SERVER__).origin;
   for (const entry of entries.entries) {
     const doc = new DOMParser().parseFromString(entry.content || '', 'text/html');
     for (const node of doc.querySelectorAll('img[src]')) {
       let url = new URL(node.getAttribute('src'), entry.url);
       const rewritten = url.origin === serverOrigin;
       if (rewritten) url = new URL(url.pathname + url.search, base);
       if (!images.some(i => i.url === url.href)) images.push({url:url.href, rewritten});
     }
   }
   report.extracted_images = images.length;
   report.image_samples = [];
   for (const candidate of images.slice(0, 3)) {
     const image = new Image();
     const shown = await new Promise(resolve => {
       const timer = setTimeout(() => resolve(false), 15000);
       image.onload = () => {clearTimeout(timer); resolve(true)};
       image.onerror = () => {clearTimeout(timer); resolve(false)};
       image.src = candidate.url;
     });
     let readable = false;
     try {
       const r = await fetch(candidate.url, {credentials:'omit', signal:AbortSignal.timeout(10000)});
       readable = r.ok && (await r.blob()).size > 0;
     } catch (error) {
       // An unreadable image is usually a CORS refusal, which the page cannot
       // distinguish from a network failure beyond the error name.
       readable = false;
     }
     report.image_samples.push({host:new URL(candidate.url).host,
       local_proxy_rewrite:candidate.rewritten, displayed:shown,
       width:image.naturalWidth, height:image.naturalHeight, js_readable:readable});
   }
 } catch (error) {
   report.native_error = {name: error.name, message: String(error), stage: report.stage};
 }
 report.stage = 'greader';
 try {
   const r = await fetch(base + '/reader/api/0/subscription/list?output=json', {
     headers:{Authorization:'GoogleLogin auth=invalid-connectivity-test'},
     credentials:'omit', signal:AbortSignal.timeout(10000)});
   report.greader = {readable_response: true, status:r.status};
 } catch (error) {
   // Under CORS the fetch rejects with a TypeError: the browser never sees the
   // 401/405 status, so reporting a status here would be a fabrication.
   report.greader = {readable_response:false, blocked_by_cors:true, error_name:error.name};
 }
 report.stage = 'done';
 document.getElementById('result').textContent = JSON.stringify(report);
 try {
   await fetch('/result', {method:'POST', body: JSON.stringify(report), keepalive:true});
 } catch (error) {}
})();
</script>""".replace("__BASE__", json.dumps(check.BASE)) \
   .replace("__AUTH_HEADERS__", json.dumps(auth_headers)) \
   .replace("__AUTH_TYPE__", json.dumps(auth_type)) \
   .replace("__SERVER__", json.dumps(check.config_value("BASE_URL")))


def kill_tree(process):
    """Kill the browser and its children; proc.kill() alone leaves renderers
    alive holding the profile directory."""
    if process.poll() is not None:
        return
    try:
        subprocess.run(["taskkill", "/F", "/T", "/PID", str(process.pid)],
                       capture_output=True, timeout=20,
                       creationflags=subprocess.CREATE_NO_WINDOW)
    except (OSError, subprocess.SubprocessError):
        process.kill()
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()


def start_servers(port, handler_class):
    """Bind IPv4 and IPv6 on the same port.

    The browser is pointed at http://localhost:5173 so the Origin matches the
    recorded value, and on Windows 11 localhost often resolves to ::1 first. An
    IPv4-only listener then looks like an empty page with no obvious cause.
    """
    servers = []
    for family, address in ((None, "127.0.0.1"), (None, "::1")):
        try:
            server = ThreadingHTTPServer((address, port), handler_class)
        except OSError:
            continue
        threading.Thread(target=server.serve_forever, daemon=True).start()
        servers.append(server)
    return servers


def create_api_key():
    """Create a temporary API key and confirm it authenticates.

    The key is deliberately NOT deleted here: the browser page authenticates
    with it, so it has to outlive the browser run. delete_api_key() cleans it up.

    Miniflux rejects a duplicate key description, so a fixed description would
    make every run after an interrupted one fail forever -- and silently falling
    back to Basic auth would then report the API key row as verified anyway.
    """
    description = f"Album RSS temporary browser check {int(time.time())}-{os.getpid()}"
    record = {"requested": True}
    try:
        status, _, raw = check.send("POST", "/v1/api-keys",
                                    headers={**dict(_basic()), **JSON_HEADERS},
                                    body={"description": description})
    except (urllib.error.URLError, OSError) as error:
        record.update({"created": False, "reason": f"connection_error:{type(error).__name__}"})
        return record, None, None
    try:
        payload = json.loads(raw) if raw else {}
    except ValueError:
        payload = {}
    token = payload.get("token")
    key_id = payload.get("id")
    record.update({"created": status == 201, "status": status, "key_id": key_id,
                   "token_present": bool(token)})
    if token:
        try:
            me_status, _, _ = check.send("GET", "/v1/me",
                                         headers={"X-Auth-Token": token, "Origin": check.ORIGIN})
            record["authenticated_status"] = me_status
        except (urllib.error.URLError, OSError) as error:
            record["authenticated_status"] = None
            record["auth_error"] = type(error).__name__
    return record, token, key_id


def delete_api_key(record, key_id):
    """Remove the temporary key. An unguarded delete in a finally block would
    replace the real result with a traceback."""
    if not key_id:
        return
    try:
        status, _, _ = check.send("DELETE", f"/v1/api-keys/{key_id}", headers=dict(_basic()))
        record["deleted_status"] = status
    except (urllib.error.URLError, OSError) as error:
        record["deleted_status"] = None
        record["delete_error"] = type(error).__name__
        record["manual_cleanup"] = f"DELETE {check.BASE}/v1/api-keys/{key_id}"


def _basic():
    credentials = f"{check.config_value('ADMIN_USERNAME')}:{check.config_value('ADMIN_PASSWORD')}"
    return {"Authorization": "Basic " + base64.b64encode(credentials.encode()).decode()}


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="无头浏览器直连验证（CORS、图片显示与下载）")
    parser.add_argument("--port", type=int, default=5173,
                        help="测试页面端口，默认 5173；改动后文档记录的 Origin 不再适用")
    parser.add_argument("--browser", help="浏览器可执行文件路径，默认自动探测 Edge 然后 Chrome")
    args = parser.parse_args()

    document = {"origin": f"http://localhost:{args.port}", "base": check.BASE}

    browser_name, browser_path = find_browser(args.browser)
    document["browser"] = {"name": browser_name, "path": browser_path}
    if not browser_path:
        document.update({"stage": "browser_not_found", "hint": STAGE_HINTS["browser_not_found"]})
        print(json.dumps(document, ensure_ascii=False, indent=2))
        return 1

    # The page body is filled in once the temporary key exists, but the handler
    # is registered before that, so it reads the body out of this holder.
    page_holder = {"body": ""}
    received = {}
    posted = threading.Event()

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            body = page_holder["body"].encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self):
            length = int(self.headers.get("Content-Length") or 0)
            received["payload"] = self.rfile.read(length)
            self.send_response(204)
            self.end_headers()
            posted.set()

        def log_message(self, *args):
            pass

    try:
        servers = start_servers(args.port, Handler)
    except OSError as error:
        document.update({"stage": "bind_failed", "error": str(error),
                         "hint": STAGE_HINTS["bind_failed"]})
        print(json.dumps(document, ensure_ascii=False, indent=2))
        return 1
    if not servers:
        document.update({"stage": "bind_failed", "hint": STAGE_HINTS["bind_failed"]})
        print(json.dumps(document, ensure_ascii=False, indent=2))
        return 1

    cache = Path(__file__).resolve().parents[1] / ".local-check"
    cache.mkdir(exist_ok=True)
    profile = tempfile.mkdtemp(dir=cache)
    key_id = None
    try:
        # Created after the servers bind so that every early return above has
        # nothing to clean up, and kept alive for the whole browser run because
        # the page authenticates with it.
        api_key_record, token, key_id = create_api_key()
        document["api_key"] = api_key_record
        if token:
            page_holder["body"] = build_page({"X-Auth-Token": token}, "API Key")
        else:
            # Basic auth only because key creation genuinely failed, and the
            # reason is recorded in document.api_key rather than papered over.
            page_holder["body"] = build_page(dict(_basic()), "Basic")

        for mode, extra in (("standard", []), ("reduced_isolation", REDUCED_ISOLATION_FLAGS)):
            posted.clear()
            received.clear()
            command = [browser_path, *BASE_FLAGS, *extra, "--user-data-dir=" + profile,
                       f"http://localhost:{args.port}"]
            try:
                process = subprocess.Popen(
                    command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                    encoding="utf-8", errors="replace",
                    creationflags=subprocess.CREATE_NO_WINDOW | subprocess.CREATE_NEW_PROCESS_GROUP)
            except OSError as error:
                document.update({"stage": "browser_spawn_failed", "error": str(error),
                                 "hint": STAGE_HINTS["browser_spawn_failed"]})
                break
            document["flags_mode"] = mode
            if posted.wait(timeout=WAIT_SECONDS):
                kill_tree(process)
                drain(process, document)
                report = json.loads(received["payload"].decode("utf-8"))
                document["browser_check"] = report
                if report.get("native_error"):
                    document["stage"] = "page_reported_error"
                    document["hint"] = STAGE_HINTS["page_reported_error"]
                else:
                    document["stage"] = "completed"
                break
            kill_tree(process)
            drain(process, document)
            document.update({
                "stage": "page_timeout_no_postback",
                "hint": STAGE_HINTS["page_timeout_no_postback"] + f"（flags_mode={mode}）",
            })
        else:
            document.setdefault("stage", "no_page_result")
            document.setdefault("hint", STAGE_HINTS["no_page_result"])
    finally:
        if key_id:
            delete_api_key(document["api_key"], key_id)
        for server in servers:
            server.shutdown()
            server.server_close()
        shutil.rmtree(profile, ignore_errors=True)
        if Path(profile).exists():
            document["profile_left_behind"] = profile

    print(json.dumps(document, ensure_ascii=False, indent=2))
    return 0 if document.get("stage") == "completed" else 1


def drain(process, document):
    """Collect the process output. The GPU and sandbox errors that explain a
    failed start are written to stderr, which the old version discarded."""
    try:
        out, err = process.communicate(timeout=15)
    except subprocess.TimeoutExpired:
        kill_tree(process)
        out, err = "", ""
    # The browser is deliberately killed once it has posted back, so a non-zero
    # exit code here is expected and is not a failure signal.
    document["diagnostics"] = {"browser_exit_code_after_kill": process.returncode,
                               "stderr_tail": (err or "")[-1500:],
                               "stdout_tail": (out or "")[-500:]}


if __name__ == "__main__":
    sys.exit(main())
