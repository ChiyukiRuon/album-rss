"""Browser direct-connect contract checks for the local Miniflux entry point.

Every row of the "已验证项目" table in docs/local-connectivity.md maps to a check
here through its doc_row field, and --markdown renders those rows, so the table
is reproduced from a run instead of transcribed by hand.

Read-only by default: the only state-changing requests are the temporary API key
that the authentication check creates and deletes. Pass --allow-write to add the
read-state round trip, which flips one article and restores it.

Never prints credentials.

Exit codes: 0 all checks passed, 1 a check failed, 3 write mode left an article
in the wrong state and could not restore it.
"""

import argparse
import atexit
import base64
import importlib.util
import json
import os
import sys
import time
import urllib.error
from pathlib import Path

spec = importlib.util.spec_from_file_location("local_check",
                                              Path(__file__).with_name("check-local-miniflux.py"))
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)

BASIC = base64.b64encode(
    f"{check.config_value('ADMIN_USERNAME')}:{check.config_value('ADMIN_PASSWORD')}".encode()
).decode()
BASIC_HEADERS = {"Authorization": "Basic " + BASIC}
JSON_HEADERS = {**BASIC_HEADERS, "Content-Type": "application/json"}

GREADER_PATH = "/reader/api/0/subscription/list?output=json"

SENSITIVE_HEADERS = {"authorization", "x-auth-token", "cookie"}

EXIT_OK = 0
EXIT_CHECK_FAILED = 1
EXIT_DIRTY_STATE = 3

OUTCOME_LABEL = {"passed": "通过", "failed": "未通过", "dirty": "未通过", "skipped": "未运行"}


def redact_headers(headers):
    if not headers:
        return None
    return {name: "<redacted>" if name.lower() in SENSITIVE_HEADERS else value
            for name, value in headers.items()}


def parse_json(raw):
    try:
        return json.loads(raw) if raw else None
    except (ValueError, UnicodeDecodeError):
        return None


class Result:
    """One check: a single request plus the assertions made about its response."""

    def __init__(self, name, doc_row, method, path, expected, headers=None,
                 detail_zh=None, informational=False, pass_label=None):
        self.name = name
        self.doc_row = doc_row
        self.informational = informational
        self.detail_zh = detail_zh
        # Wording for the doc table when this check passes. The default reads
        # oddly on checks whose expectation is that a feature is unavailable.
        self.pass_label = pass_label or "通过"
        self.expected = expected
        self.assertions = []
        self.request = {"method": method, "path": path, "headers": redact_headers(headers)}
        self.status = None
        self.headers = {}
        self.body = b""
        self.outcome = "failed"
        self.reason = None

    def expect(self, name, ok, severity="error", **details):
        self.assertions.append(check.assertion(name, ok, severity=severity, **details))
        return self

    def expect_subset(self, name, required, header_name):
        self.assertions.append(
            check.subset_assertion(name, required, self.headers.get(header_name)))
        return self

    def expect_allow_origin(self):
        actual = self.headers.get("Access-Control-Allow-Origin")
        return self.expect("allow_origin", actual == "*", expected="*", actual=actual)

    def expect_no_allow_origin(self):
        actual = self.headers.get("Access-Control-Allow-Origin")
        return self.expect("no_allow_origin", actual is None, expected=None, actual=actual)

    def skipped(self, reason, detail_zh=None):
        self.reason = reason
        self.outcome = "skipped"
        if detail_zh:
            self.detail_zh = detail_zh
        return self

    def ok(self):
        if self.outcome == "skipped":
            return True
        if self.status not in self.expected:
            return False
        return all(a["ok"] for a in self.assertions if a["severity"] == "error")

    def to_json(self):
        if self.outcome != "skipped":
            self.outcome = "passed" if self.ok() else "failed"
        return {"name": self.name, "doc_row": self.doc_row,
                "informational": True if self.informational else None,
                "ok": self.ok(), "outcome": self.outcome, "reason": self.reason,
                "detail_zh": self.detail_zh, "pass_label": self.pass_label,
                "request": self.request,
                "status": self.status, "expected_status": sorted(self.expected),
                "assertions": self.assertions}


def perform(name, doc_row, method, path, expected, headers=None, body=None,
            timeout=20, informational=False, allow_write=False, detail_zh=None,
            pass_label=None):
    result = Result(name, doc_row, method, path, expected, headers, detail_zh,
                    informational, pass_label)
    try:
        result.status, result.headers, result.body = check.send(
            method, path, headers=headers, body=body, timeout=timeout, allow_write=allow_write)
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        # Being unable to connect at all is the most likely failure of a
        # connectivity check, so report it as a failed check rather than
        # letting it escape as a traceback with no exit code.
        reason = getattr(error, "reason", error)
        result.reason = f"connection_error:{type(reason).__name__}"
        result.detail_zh = f"未通过（无法连接 {check.BASE}，{type(reason).__name__}）"
        return result
    if result.status not in expected:
        result.reason = f"unexpected_status_{result.status}"
    return result


# --- checks -----------------------------------------------------------------

def check_healthcheck():
    result = perform("reachability_healthcheck", "健康检查", "GET", "/healthcheck", {200},
                     headers={"Origin": check.ORIGIN},
                     detail_zh="200，body 为 OK，且不带 CORS 头")
    body = result.body.strip().decode("utf-8", "replace")
    result.expect("body_is_ok", body == "OK", expected="OK", actual=body[:40])
    content_type = result.headers.get("Content-Type") or ""
    result.expect("content_type_is_text", content_type.startswith("text/plain"),
                  expected="text/plain", actual=content_type)
    # This route lives outside /v1 and carries no CORS header. That absence is
    # what proves the CORS support below comes from Miniflux's own /v1 router
    # and not from a blanket header added by the nginx gateway -- which is in
    # turn what makes the missing headers on the Google Reader paths meaningful.
    result.expect_no_allow_origin()
    return result


def check_basic_auth():
    result = perform("auth_basic", "Basic 认证", "GET", "/v1/me", {200},
                     headers={**BASIC_HEADERS, "Origin": check.ORIGIN},
                     detail_zh="Basic 认证 /v1/me 返回 200")
    result.expect_allow_origin()
    return result


def check_api_key_lifecycle():
    """Create a temporary API key, verify it, delete it, verify it is refused.

    The description carries a timestamp and pid: Miniflux rejects a duplicate
    description, so a fixed string would make every run after an interrupted one
    fail permanently -- and a silent fallback to Basic auth would then report
    this row as verified while only Basic auth was ever exercised.
    """
    description = f"Album RSS connectivity check {int(time.time())}-{os.getpid()}"
    results = []
    created = perform("api_key_create", "API Key 认证", "POST", "/v1/api-keys", {201},
                      headers=JSON_HEADERS, body={"description": description},
                      detail_zh="创建临时 Key 返回 201")
    payload = parse_json(created.body) or {}
    token = payload.get("token")
    key_id = payload.get("id")
    created.expect("has_id", bool(key_id))
    created.expect("has_token", bool(token), expected="present",
                   actual=f"<redacted, {len(token)} chars>" if token else None)
    results.append(created)

    if not token:
        for name in ("api_key_authenticated_me", "api_key_delete", "api_key_revoked"):
            skipped = Result(name, "API Key 认证", "GET", "/v1/me", {200})
            skipped.skipped("api_key_creation_failed",
                            detail_zh=f"{name} 未运行（临时 Key 创建失败）")
            results.append(skipped)
        return results

    try:
        authenticated = perform("api_key_authenticated_me", "API Key 认证", "GET", "/v1/me", {200},
                                headers={"X-Auth-Token": token, "Origin": check.ORIGIN},
                                detail_zh="X-Auth-Token 请求 /v1/me 返回 200")
        authenticated.expect_allow_origin()
        results.append(authenticated)
    finally:
        deleted = perform("api_key_delete", "API Key 认证", "DELETE", f"/v1/api-keys/{key_id}",
                          {204}, headers=BASIC_HEADERS,
                          detail_zh="删除临时 Key 返回 204")
        results.append(deleted)
        if not deleted.ok():
            # Keep the sentinel so atexit retries the delete.
            pending_keys.append((key_id, description))

    # Mirrors the assertion above on purpose: "a revoked key is rejected" and
    # "the browser can read that 401" are different claims, and this one holds
    # on /v1 while it does not on the Google Reader paths below.
    revoked = perform("api_key_revoked", "API Key 认证", "GET", "/v1/me", {401},
                      headers={"X-Auth-Token": token, "Origin": check.ORIGIN},
                      detail_zh="已删除的 Key 请求返回 401")
    revoked.expect_allow_origin()
    results.append(revoked)
    return results


def check_native_preflight():
    """Validate the preflight without ever sending the method being preflighted.

    The only request is OPTIONS. "PUT" appears solely as the value of the
    Access-Control-Request-Method header, which the server never dispatches on.
    """
    results = []

    get_preflight = perform(
        "preflight_native_get", "原生 API GET 预检", "OPTIONS", "/v1/me", {200, 204},
        headers={"Origin": check.ORIGIN, "Access-Control-Request-Method": "GET",
                 "Access-Control-Request-Headers": "x-auth-token,authorization"},
        detail_zh="OPTIONS 返回 200，允许 X-Auth-Token、Authorization")
    get_preflight.expect_allow_origin()
    get_preflight.expect_subset("allow_methods", ["get"], "Access-Control-Allow-Methods")
    get_preflight.expect_subset("allow_headers", ["x-auth-token", "authorization"],
                                "Access-Control-Allow-Headers")
    get_preflight.expect("max_age_present",
                         get_preflight.headers.get("Access-Control-Max-Age") is not None,
                         severity="warning", expected="present",
                         actual=get_preflight.headers.get("Access-Control-Max-Age"))
    results.append(get_preflight)

    put_preflight = perform(
        "preflight_native_put", "原生 API PUT 预检", "OPTIONS", "/v1/entries", {200, 204},
        headers={"Origin": check.ORIGIN, "Access-Control-Request-Method": "PUT",
                 "Access-Control-Request-Headers": "x-auth-token,content-type"},
        detail_zh="OPTIONS 返回 200，允许 PUT、X-Auth-Token、Content-Type，未发送 PUT")
    put_preflight.expect_allow_origin()
    put_preflight.expect_subset("allow_methods", ["put"], "Access-Control-Allow-Methods")
    put_preflight.expect_subset("allow_headers", ["x-auth-token", "content-type"],
                                "Access-Control-Allow-Headers")
    results.append(put_preflight)

    # The preflight above succeeds on ANY /v1 path, so on its own it proves the
    # CORS policy exists but not that the write route does. This read-only GET
    # proves the path is really routed; the two together are the honest form of
    # the "原生 API PUT 预检" row.
    binding = perform("route_binding_entries", None, "GET", "/v1/entries?limit=1", {200},
                      headers={**BASIC_HEADERS, "Origin": check.ORIGIN},
                      detail_zh="GET /v1/entries 返回 200，写目标路径存在")
    binding.expect_allow_origin()
    results.append(binding)

    # Disclosure, not a pass/fail result: keeps anyone from over-reading the two
    # preflight rows as evidence of route existence.
    agnostic = perform("preflight_path_agnostic", None, "OPTIONS", "/v1/__no_such_route__", {200},
                       headers={"Origin": check.ORIGIN, "Access-Control-Request-Method": "PUT"},
                       detail_zh="不存在的 /v1 路径预检同样返回 200", informational=True)
    agnostic.expect_allow_origin()
    results.append(agnostic)
    return results


def check_greader():
    results = []

    preflight = perform("greader_preflight", "Google Reader 预检", "OPTIONS", GREADER_PATH, {405},
                        headers={"Origin": check.ORIGIN, "Access-Control-Request-Method": "GET"},
                        detail_zh="OPTIONS 返回 405，且无 CORS 允许头",
                        pass_label="已确认跨域不可用")
    # 405 is the positive signal here: the router answers it when the path
    # matches but the method does not, so the route exists and is GET-only.
    preflight.expect_no_allow_origin()
    results.append(preflight)

    invalid = perform("greader_invalid_token", "Google Reader 无效 token 请求", "GET", GREADER_PATH,
                      {401},
                      headers={"Authorization": "GoogleLogin auth=invalid-connectivity-test",
                               "Origin": check.ORIGIN},
                      detail_zh="返回 401，无 CORS 允许头，未验证有效凭据",
                      pass_label="已确认跨域不可用")
    bad_token = invalid.headers.get("X-Reader-Google-Bad-Token")
    invalid.expect("bad_token_header", bad_token == "true", expected="true", actual=bad_token)
    invalid.expect_no_allow_origin()
    results.append(invalid)
    return results


# --- optional write-back ----------------------------------------------------

# API keys whose delete did not confirm, retried by atexit.
pending_keys = []

# The article currently flipped away from its original state. Populated before
# the flip and cleared only after a verified restore.
write_pending = {}


def restore_pending():
    """Idempotent restore. Safe to call from finally and from atexit.

    Re-sending the original status is free when it is already in place: the
    storage layer filters rows already in the target state, so a repeat write
    matches zero rows and is a no-op.
    """
    entry_id = write_pending.get("entry_id")
    if not entry_id:
        return True
    original = write_pending["original_status"]
    for attempt, delay in enumerate((0, 1, 3, 7)):
        if delay:
            time.sleep(delay)
        try:
            status, _, _ = check.send("PUT", "/v1/entries", headers=JSON_HEADERS,
                                      body={"entry_ids": [entry_id], "status": original},
                                      allow_write=True, timeout=15)
        except (urllib.error.URLError, OSError, RuntimeError):
            continue
        if status in (200, 204):
            write_pending["attempts"] = attempt + 1
            write_pending.clear()
            return True
    return False


def remove_pending_keys():
    for key_id, description in list(pending_keys):
        try:
            status, _, _ = check.send("DELETE", f"/v1/api-keys/{key_id}", headers=BASIC_HEADERS,
                                      timeout=15)
        except (urllib.error.URLError, OSError, RuntimeError):
            continue
        if status in (200, 204):
            pending_keys.remove((key_id, description))


@atexit.register
def _atexit_cleanup():
    remove_pending_keys()
    if not restore_pending():
        print(json.dumps({
            "error": "restore_failed_at_exit",
            "entry_id": write_pending.get("entry_id"),
            "original_status": write_pending.get("original_status"),
            "manual_fix": (f'PUT {check.BASE}/v1/entries  '
                           f'{{"entry_ids": [{write_pending.get("entry_id")}], '
                           f'"status": "{write_pending.get("original_status")}"}}'),
        }, ensure_ascii=False), file=sys.stderr)


def check_write_back(enabled):
    """Flip one article's read state, verify it, restore it, verify again.

    Two facts from the 2.2.16 source drive the shape of this check:
      * PUT /v1/entries/{entryID} accepts only {title, content}; status lives on
        the collection route PUT /v1/entries with {"entry_ids": [...], "status"}.
      * The storage layer sets changed_at=now() and skips rows already in the
        target state, so a 204 does not prove anything changed. Every step
        re-reads the server instead of trusting the status code.
    """
    record = {"name": "write_back_round_trip", "doc_row": "状态回写（--allow-write）",
              "informational": None, "ok": False, "outcome": "running", "reason": None,
              "detail_zh": "翻转一篇文章的已读状态并恢复", "steps": [], "assertions": [],
              "changed_at_before": None, "changed_at_after": None, "dirty_state": False}
    if not enabled:
        record.update({"ok": True, "outcome": "skipped", "reason": "requires --allow-write",
                       "detail_zh": "需显式 --allow-write；默认运行不会改动阅读状态"})
        return record

    unreachable = []

    def step(label, method, path, expected, headers=None, body=None):
        try:
            status, _, raw = check.send(method, path, headers=headers, body=body,
                                        allow_write=True, timeout=20)
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            reason = getattr(error, "reason", error)
            unreachable.append(type(reason).__name__)
            record["steps"].append({"step": label, "method": method, "path": path,
                                    "status": None, "expected_status": sorted(expected),
                                    "error": type(reason).__name__})
            return None, None, False
        record["steps"].append({"step": label, "method": method, "path": path,
                                "status": status, "expected_status": sorted(expected)})
        return status, parse_json(raw), status in expected

    def assert_(name, ok, **details):
        record["assertions"].append(check.assertion(name, ok, **details))

    def read_status():
        _, current, ok = step("read_back", "GET", f"/v1/entries/{entry_id}", {200}, BASIC_HEADERS)
        return current.get("status") if ok and current else None

    def fail_with_reason(reason):
        record.update({"ok": False, "outcome": "failed", "reason": reason,
                       "detail_zh": f"未通过（{reason}）"})
        return record

    def dirty(attempts):
        record.update({
            "ok": False, "outcome": "dirty", "dirty_state": True,
            "current_status": read_status(), "attempts": attempts,
            "manual_fix": (f'PUT {check.BASE}/v1/entries  {{"entry_ids": [{entry_id}], '
                           f'"status": "{original_status}"}}'),
            "manual_fix_ui": "在 Miniflux 网页端将该文章标记回原状态",
            "sync_impact": "该文章 changed_at 已前移，依赖 changed_after 的增量同步可能重新拉取这一篇",
            "detail_zh": f"未通过（恢复失败，文章 {entry_id} 未回到 {original_status}，需手动恢复）",
        })
        return record

    # Pick the oldest unread article. If the restore ever fails, the loss is the
    # article least likely to still be awaiting the user's attention. Exactly
    # one id, per design.md's rule against changing reading state in bulk.
    candidate = None
    for source_state, target_state in (("unread", "read"), ("read", "unread")):
        _, listing, ok = step(f"select_oldest_{source_state}", "GET",
                              f"/v1/entries?status={source_state}"
                              f"&order=id&direction=asc&limit=1", {200}, BASIC_HEADERS)
        if ok and listing and listing.get("entries"):
            candidate = listing["entries"][0]
            record["direction"] = f"{source_state} -> {target_state} -> {source_state}"
            break
    if candidate is None:
        # An unreachable service also yields no candidate, but reporting that as
        # "no articles" would hide the real cause.
        if unreachable:
            return fail_with_reason(f"service_unreachable:{unreachable[0]}")
        record.update({"ok": True, "outcome": "skipped", "reason": "no_entries_to_test",
                       "detail_zh": "跳过，实例中没有文章"})
        return record

    entry_id = candidate["id"]
    record["entry_id"] = entry_id

    # Record the original state.
    _, before, ok = step("read_original", "GET", f"/v1/entries/{entry_id}", {200}, BASIC_HEADERS)
    if not ok or not before:
        return fail_with_reason("could_not_read_original_state")
    original_status = before["status"]
    original_starred = before.get("starred")
    record["changed_at_before"] = before.get("changed_at")
    record["original_status"] = original_status

    # Concurrency guard: if another client touched this article between the
    # listing and now, refuse rather than clobber its change.
    _, recheck, ok = step("concurrency_recheck", "GET", f"/v1/entries/{entry_id}", {200},
                          BASIC_HEADERS)
    if ok and recheck and recheck.get("changed_at") != record["changed_at_before"]:
        record.update({"ok": True, "outcome": "skipped", "reason": "concurrent_modification",
                       "detail_zh": "跳过，文章在检查期间被其他客户端修改"})
        return record

    # Flip. The sentinel exists before the write so any later failure path knows
    # what to put back.
    write_pending.update({"entry_id": entry_id, "original_status": original_status})
    flip_to = "read" if original_status == "unread" else "unread"
    status, _, ok = step("flip", "PUT", "/v1/entries", {204}, JSON_HEADERS,
                         {"entry_ids": [entry_id], "status": flip_to})
    if not ok:
        write_pending.clear()
        return fail_with_reason(f"flip_rejected_{status}")

    # Verify by re-reading: a 204 can correspond to zero rows changed.
    _, after_flip, ok = step("verify_flip", "GET", f"/v1/entries/{entry_id}", {200}, BASIC_HEADERS)
    observed = after_flip.get("status") if ok and after_flip else None
    assert_("flip_visible", observed == flip_to, expected=flip_to, actual=observed)
    if observed != flip_to:
        restore_pending()
        return fail_with_reason("flip_not_visible_after_write")

    # Restore, then verify the restore.
    if not restore_pending():
        return dirty(4)
    _, after_restore, ok = step("verify_restore", "GET", f"/v1/entries/{entry_id}", {200},
                                BASIC_HEADERS)
    final_status = after_restore.get("status") if ok and after_restore else None
    final_starred = after_restore.get("starred") if ok and after_restore else None
    record["changed_at_after"] = after_restore.get("changed_at") if after_restore else None
    assert_("restore_visible", final_status == original_status,
            expected=original_status, actual=final_status)
    assert_("starred_unchanged", final_starred == original_starred,
            expected=original_starred, actual=final_starred)
    if final_status != original_status:
        return dirty(1)

    record.update({"ok": True, "outcome": "passed",
                   "detail_zh": (f"文章 {entry_id} 已读状态翻转并恢复到原值，"
                                  f"starred 未变；changed_at 已前移")})
    return record


# --- reporting --------------------------------------------------------------

def summarize(checks):
    graded = [c for c in checks if not c.get("informational")]
    passed = sum(1 for c in graded if c["outcome"] == "passed")
    skipped = sum(1 for c in graded if c["outcome"] == "skipped")
    failed = [c for c in graded if c["outcome"] == "failed"]
    dirty = [c for c in graded if c["outcome"] == "dirty"]
    return passed, failed, skipped, dirty


def exit_code(failed, dirty):
    if dirty:
        return EXIT_DIRTY_STATE
    if failed:
        return EXIT_CHECK_FAILED
    return EXIT_OK


def markdown_table(checks):
    """One row per doc 项目, assembled from the checks that carry that doc_row."""
    order, groups = [], {}
    for item in checks:
        row = item.get("doc_row")
        if not row:
            continue
        if row not in groups:
            order.append(row)
            groups[row] = []
        groups[row].append(item)
    lines = ["| 项目 | 结果 |", "| --- | --- |"]
    for row in order:
        items = groups[row]
        outcomes = {c["outcome"] for c in items}
        if outcomes & {"failed", "dirty"}:
            label = "未通过"
        elif outcomes == {"passed"}:
            label = items[0].get("pass_label") or "通过"
        else:
            label = "未运行"
        details = "；".join(c["detail_zh"] for c in items if c.get("detail_zh"))
        lines.append(f"| {row} | {label}（{details}） |")
    return "\n".join(lines)


def main():
    # Redirected stdout falls back to the locale encoding (cp936 on this
    # machine), which would write the Chinese check names as GBK. JSON is UTF-8.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(
        description="本地 Miniflux 浏览器直连契约检查（健康检查 / 认证 / CORS 预检 / 状态回写）")
    parser.add_argument("--allow-write", action="store_true",
                        help="启用状态回写测试：会翻转一篇文章的已读状态并恢复")
    parser.add_argument("--markdown", action="store_true",
                        help="额外输出可粘贴到文档的表格行")
    parser.add_argument("--base", default=check.BASE,
                        help=f"入口地址，默认 {check.BASE}；改动后文档记录的结果不再适用")
    args = parser.parse_args()
    check.BASE = args.base

    checks = []
    checks.append(check_healthcheck())
    checks.append(check_basic_auth())
    checks.extend(check_api_key_lifecycle())
    checks.extend(check_native_preflight())
    checks.extend(check_greader())
    checks.append(check_write_back(args.allow_write))

    records = [c.to_json() if isinstance(c, Result) else c for c in checks]
    passed, failed, skipped, dirty = summarize(records)
    code = exit_code(failed, dirty)

    document = {
        "summary": {"ok": not failed and not dirty,
                    "passed": passed, "failed": len(failed), "skipped": skipped,
                    "informational": sum(1 for c in records if c.get("informational")),
                    "write_back_left_dirty_state": bool(dirty),
                    "exit_code": code},
        "failed_checks": [{"name": c["name"], "status": c.get("status"),
                           "reason": c.get("reason")} for c in failed + dirty],
        "base": check.BASE,
        "origin": check.ORIGIN,
        "read_only_guarantee": {
            "allow_write": args.allow_write,
            "state_changing_requests": sorted(set(
                entry for entry in check.REQUEST_LEDGER
                if entry.split(" ", 1)[0] in check.MUTATING_METHODS)),
            "invariant": ("无 --allow-write 时，除 /v1/api-keys 的临时 Key 生命周期外，"
                          "任何写方法都会被拒绝"),
        },
        "checks": records,
    }
    print(json.dumps(document, ensure_ascii=False, indent=2))
    if args.markdown:
        print(markdown_table(records))
    return code


if __name__ == "__main__":
    sys.exit(main())
