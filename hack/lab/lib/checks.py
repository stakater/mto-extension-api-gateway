#!/usr/bin/env python3
"""The G.19 checks (docs/planning/G19-kind-spike.md). Run by `lab.sh test`.

  checks.py [--istio VERSION] [--only name,name] [--skip name,name]

Every check calls as the caller, through the gateway's Service, from a client pod, and pairs each
denial with an allow. A check prints PASS, FAIL or NOTE with its row; the results go to
hack/lab/.state/results-<istio>.md. The exit code is 1 when any check fails.
"""
import argparse, json, os, random, string, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
LAB = os.path.dirname(HERE)
STATE = os.path.join(LAB, ".state")
GW = "http://mto-api-gateway-istio.team-a-dev.svc.cluster.local"
HOST = "orders.team-a.apis.example.com"
OUTSIDER = ("team-a-outside", "outsider")   # not in the mesh: where callers come from (the router)
INTRUDER = ("team-a-test", "intruder")      # in the mesh, another namespace of the tenant
RUN = "".join(random.choice(string.ascii_lowercase) for _ in range(5))  # fresh rate limit counters per run
RESULTS = []


# ---------------------------------------------------------------- helpers

def kc(*args, stdin=None, check=True):
    p = subprocess.run(["kubectl", *args], input=stdin, capture_output=True, text=True)
    if check and p.returncode != 0:
        raise RuntimeError(f"kubectl {' '.join(args)}: {p.stderr.strip()}")
    return p.stdout


def apply(text):
    kc("apply", "-f", "-", stdin=text)


def tok(k, claims, **override):
    claims = dict(claims, **override)
    return subprocess.run([sys.executable, os.path.join(HERE, "tokens.py"), "mint", k, json.dumps(claims)],
                          capture_output=True, text=True, check=True).stdout.strip()


def client(pod, *args):
    ns, name = pod
    return kc("exec", "-n", ns, name, "--", "python3", "/lab/client.py", *args, check=False).strip()


def req(path, token="", pod=OUTSIDER, host=HOST, base=GW, headers=()):
    out = client(pod, "req", base + path, host, token, *headers)
    try:
        return json.loads(out.splitlines()[-1])
    except (ValueError, IndexError):
        return {"status": "ERR", "body": out[-160:]}


def plain(url, pod):
    return client(pod, "plain", url)


def burst(path, token, n, pod=OUTSIDER):
    return json.loads(client(pod, "burst", GW + path, HOST, token, str(n)).splitlines()[-1])


def hv(headers, name):
    """A header's value as text: go-httpbin returns lists, httpbin.org returns strings."""
    v = headers.get(name)
    return v[0] if isinstance(v, list) and len(v) == 1 else v


def record(status, row, check, detail=""):
    RESULTS.append((status, row, check, detail))
    print(f"{status:4} {row:22} {check}" + (f"  [{detail}]" if detail else ""), flush=True)


def expect(row, check, got, want, detail=""):
    ok = got == want if not callable(want) else want(got)
    record("PASS" if ok else "FAIL", row, check, detail or f"got {got}")
    return ok


def pod_ip(ns, selector):
    return kc("get", "pod", "-n", ns, "-l", selector, "-o", "jsonpath={.items[0].status.podIP}")


def wait_minute_start(budget=25):
    """Rate limit windows are per minute: start a burst early in a minute, so it doesn't straddle two."""
    if time.time() % 60 > 60 - budget:
        time.sleep(61 - time.time() % 60)


def shop():
    return tok("a", {"azp": f"shop-{RUN}", "allowed_apis": ["api.team-a.orders.silver"], "client_id": "shop-app"})


# ---------------------------------------------------------------- checks

def check_baseline():
    """M12, AC-AUTH-1/2/3: the floor, the default deny, an invalid token, a valid one."""
    good = shop()
    r = req("/orders/v2/get", good)
    expect("M12 AC-AUTH-3", "valid token for orders: 200, path rewritten", (r["status"], (r.get("url") or "").endswith("/anything/orders/v1/get")), (200, True))
    expect("M12 AC-AUTH-1", "no token: 403", req("/orders/v2/get")["status"], 403)
    forged = tok("b", {"azp": "shop", "allowed_apis": ["api.team-a.orders.silver"]}, iss="https://idp-a.lab/realms/apis")
    expect("AC-AUTH-2", "token signed with another key: 401", req("/orders/v2/get", forged)["status"], 401)
    expired = tok("a", {"azp": "shop", "allowed_apis": ["api.team-a.orders.silver"]}, exp=int(time.time()) - 600)
    expect("AC-AUTH-2", "expired token: 401", req("/orders/v2/get", expired)["status"], 401)
    bare = tok("a", {"azp": "bare"})
    expect("M12 AC-AUTH-3", "valid token without the API: 403", req("/orders/v2/get", bare)["status"], 403)
    expect("M12", "valid token, path of no API: 403", req("/nothing/here", good)["status"], 403)


def check_issuers():
    """M17, Q18, AC-AUTH-10: a token of an issuer the gateway doesn't trust."""
    other = tok("b", {"azp": "bank", "allowed_apis": ["api.team-a.orders.silver"]})
    expect("M17 Q18 AC-AUTH-10", "issuer b (trusted by the floor, not by this gateway): 401", req("/orders/v2/get", other)["status"], 401)


def check_query_token():
    """AC-AUTH-9, M15: the token only from the Authorization header."""
    r = req("/orders/v2/get?access_token=" + shop())
    expect("AC-AUTH-9 M15", "token in ?access_token=: 403", r["status"], 403)


def check_headers():
    """AC-AUTH-4, M7: the caller's claim headers are removed, the gateway's are set from the token."""
    r = req("/orders/v2/get", shop(), headers=["x-sub:admin", "x-roles:admin"])
    h = r.get("headers", {})
    expect("AC-AUTH-4 M7", "x-sub set from azp, caller's copy removed", hv(h, "x-sub"), f"shop-{RUN}")
    expect("AC-AUTH-4 M7", "x-roles set from the token, caller's copy removed",
           len(h.get("x-roles", [])) == 1 and h.get("x-roles") != ["admin"], True, f"got {h.get('x-roles')}")
    expect("ADR-0003", "the token is not forwarded to the backend", "authorization" in h, False)


def check_paths():
    """M16, Q16, AC-AUTH-8: two APIs on one host, split by path."""
    good = shop()
    pay = tok("a", {"azp": f"pay-{RUN}", "allowed_apis": ["api.team-a.payments.gold"]})
    expect("M16 AC-AUTH-8", "payments' caller on payments: 200", req("/payments/v1/x", pay)["status"], 200)
    expect("M16 AC-AUTH-8", "orders' caller on orders: 200", req("/orders/v2/x", good)["status"], 200)
    for path in ["/payments/v1/x", "/orders/v2/../../payments/v1/x", "//payments/v1/x",
                 "/orders/v2%2F..%2F..%2Fpayments/v1/x", "/Payments/v1/x", "/orders/v2x"]:
        st = req(path, good)["status"]
        expect("M16 Q16 AC-AUTH-8", f"orders' caller on {path}: refused", st, lambda s: s in (403, 404, 400), f"got {st}")
    expect("M16", "a query string doesn't change the match", req("/orders/v2/x?p=/payments/v1", good)["status"], 200)


def check_closed_rule():
    """M10, ADR-0006: the closed rule, azp required, today's role names."""
    cases = [("another tenant's API", {"azp": "bank", "allowed_apis": ["api.team-b.billing.gold"]}, 403),
             ("orders2 (closed rule)", {"azp": "near", "allowed_apis": ["api.team-a.orders2.silver"]}, 403),
             ("no azp", {"allowed_apis": ["api.team-a.orders.silver"]}, 403),
             ("the claim as one string", {"azp": "one", "allowed_apis": "api.team-a.orders.silver"}, 200),
             ("today's role name (migration)", {"azp": "legacy-shop", "allowed_apis": ["api-orders-consumer-gold"]}, 200)]
    for name, claims, want in cases:
        expect("M10 ADR-0006", f"{name}: {want}", req("/orders/v2/get", tok("a", claims))["status"], want)


def check_rate_limits():
    """M14, M18, M20, AC-RL-1..4: the tier from the role claim by CEL, a counter per tenant, API, tier, caller."""
    cases = [("gold", ["api.team-a.orders.gold"], 20), ("silver", ["api.team-a.orders.silver"], 10),
             ("no tier role", ["api.team-a.orders"], 4), ("unknown tier", ["api.team-a.orders.platinum"], 4),
             ("bronze and gold", ["api.team-a.orders.bronze", "api.team-a.orders.gold"], 20),
             ("string claim", "api.team-a.orders.gold", 20), ("today's role name", ["api-orders-consumer-silver"], 10)]
    for i, (name, roles, limit) in enumerate(cases):
        wait_minute_start()
        t = tok("a", {"azp": f"rl{i}-{RUN}", "allowed_apis": roles})
        got = burst("/orders/v2/get", t, limit + 3)
        expect("M20 AC-RL-1/2", f"{name}: {limit} pass, then 429", (got.get("200", 0), got.get("429", 0)), (limit, 3), f"got {got}")
    wait_minute_start()
    t = tok("a", {"azp": f"two-{RUN}", "allowed_apis": ["api.team-a.orders.silver", "api.team-a.payments.silver"]})
    a, b = burst("/orders/v2/get", t, 13), burst("/payments/v1/get", t, 13)
    expect("M18 AC-RL-3", "one caller on two APIs has two counters", (a.get("200"), b.get("200")), (10, 10), f"orders {a}, payments {b}")
    anon = tok("a", {"allowed_apis": ["api.team-a.orders.silver"]})
    expect("AC-RL-4", "no azp: refused before the limit", burst("/orders/v2/get", anon, 3), {"403": 3})


def check_fail_open():
    """AC-RL-6: the rate limit service down, the platform chose fail open."""
    kc("scale", "deploy/ratelimit", "-n", "mto-api-gateways", "--replicas=0")
    kc("wait", "--for=delete", "pod", "-l", "app=ratelimit", "-n", "mto-api-gateways", "--timeout=60s", check=False)
    try:
        t = tok("a", {"azp": f"fo-{RUN}", "allowed_apis": ["api.team-a.orders"]})
        got = burst("/orders/v2/get", t, 8)
        expect("AC-RL-6", "rate limit service down: all 8 pass (bronze is 4)", got, {"200": 8})
    finally:
        kc("scale", "deploy/ratelimit", "-n", "mto-api-gateways", "--replicas=1")
        kc("rollout", "status", "deploy/ratelimit", "-n", "mto-api-gateways", "--timeout=120s")


def check_lock():
    """M4, Q5, AC-ISO-5: the waypoint lock."""
    svc = "http://orders.team-a-dev.svc.cluster.local"
    r = req("/anything/orders/v1", pod=INTRUDER, host="-", base=svc)
    expect("M4 Q5 AC-ISO-5", "intruder through the Service on the API's path: 403", r["status"], 403)
    for path in ["/healthz", "/metrics"]:
        r = req(path, pod=INTRUDER, host="-", base=svc)
        expect("Q5 AC-ISO-5", f"intruder on the open path {path}: reaches the backend",
               r["status"] != 403 and "RBAC" not in r.get("body", ""), True, f"got {r['status']}")
    expect("Q5 AC-ISO-5", "the gateway reaches the backend: 200", req("/orders/v2/get", shop())["status"], 200)
    apply("""apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata: { name: lab.deny-all, namespace: team-a-dev }
spec:
  targetRefs: [{ group: "", kind: Service, name: orders }]
  action: DENY
  rules: [{}]
""")
    time.sleep(6)
    try:
        expect("M4", "with a deny-all on the waypoint, the gateway still gets 200 (its traffic skips the waypoint)",
               req("/orders/v2/get", shop())["status"], 200)
        expect("M4", "with the same deny-all, intruder on /healthz: 403 (the waypoint enforces it)",
               req("/healthz", pod=INTRUDER, host="-", base=svc)["status"], 403)
    finally:
        kc("delete", "authorizationpolicy", "lab.deny-all", "-n", "team-a-dev")
        time.sleep(4)


def check_bypass():
    """M21, Q21: calls that don't pass the waypoint, the documented limit."""
    ip = pod_ip("team-a-dev", "app=orders")
    svc = "http://orders.team-a-dev.svc.cluster.local"
    for who, pod, url in [("intruder on a pod's IP", INTRUDER, f"http://{ip}:8080/anything/x"),
                          ("outsider on the Service", OUTSIDER, svc + "/anything/x"),
                          ("outsider on a pod's IP", OUTSIDER, f"http://{ip}:8080/anything/x")]:
        st = plain(url, pod)
        expect("M21 Q21", f"{who}: reaches the backend (known limit)", st, "200")


def check_strict():
    """M24, AC-ISO-12: STRICT mTLS on the backend pods, a platform choice per tenant."""
    ip = pod_ip("team-a-dev", "app=orders")
    pod = kc("get", "pod", "-n", "team-a-dev", "-l", "app=orders", "-o", "jsonpath={.items[0].metadata.name}")
    restarts = kc("get", "pod", pod, "-n", "team-a-dev", "-o", "jsonpath={.status.containerStatuses[0].restartCount}")
    apply("""apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata: { name: api.orders.orders, namespace: team-a-dev, labels: { api-gateway.stakater.com/managed: "true" } }
spec:
  selector: { matchLabels: { app: orders } }
  mtls: { mode: STRICT }
""")
    time.sleep(8)
    try:
        for who, url in [("Service /metrics", "http://orders.team-a-dev.svc.cluster.local/metrics"),
                         ("Service API path", "http://orders.team-a-dev.svc.cluster.local/anything/x"),
                         ("pod IP", f"http://{ip}:8080/anything/x")]:
            st = plain(url, OUTSIDER)
            expect("M24 AC-ISO-12", f"STRICT: outsider on the {who}: refused", st.startswith("ERR"), True, f"got {st}")
        expect("M24 AC-ISO-12", "STRICT: the gateway still gets 200", req("/orders/v2/get", shop())["status"], 200)
        time.sleep(15)
        ready = kc("get", "pod", pod, "-n", "team-a-dev", "-o", "jsonpath={.status.containerStatuses[0].ready}/{.status.containerStatuses[0].restartCount}")
        expect("M24", "STRICT: kubelet probes pass (ready, no restart)", ready, f"true/{restarts}")
    finally:
        kc("delete", "peerauthentication", "api.orders.orders", "-n", "team-a-dev")
        time.sleep(5)


def check_metrics():
    """M23: the gateway's and the waypoint's metrics, read from outside the mesh."""
    for name, ns, sel in [("gateway", "team-a-dev", "gateway.networking.k8s.io/gateway-name=mto-api-gateway"),
                          ("waypoint", "team-a-dev", "gateway.networking.k8s.io/gateway-name=mto-api-gateway-waypoint")]:
        ip = pod_ip(ns, sel)
        out = kc("exec", "-n", OUTSIDER[0], OUTSIDER[1], "--", "python3", "-c",
                 f"import urllib.request;print(sum(1 for l in urllib.request.urlopen('http://{ip}:15020/stats/prometheus',timeout=8).read().decode().splitlines() if l.startswith('istio_requests_total')))",
                 check=False).strip()
        expect("M23", f"the {name}'s istio_requests_total on port 15020 /stats/prometheus", out.isdigit() and int(out) > 0, True, f"series: {out}")


def check_mesh_caller_to_gateway():
    """A mesh pod calling the gateway's Service: the gateway's namespace uses a waypoint for its Services."""
    r = req("/orders/v2/get", shop(), pod=INTRUDER)
    record("NOTE", "ADR-0007", "intruder (in the mesh) calls the gateway's Service with a valid token", f"got {r['status']}")


def floor_principals(extra):
    base = ["https://idp-a.lab/realms/apis/*", "https://idp-b.lab/realms/apis/*"]
    kc("patch", "authorizationpolicy", "mto-api-gateway-token-floor", "-n", "istio-system", "--type=json", "-p",
       json.dumps([{"op": "replace", "path": "/spec/rules/0/from/0/source/notRequestPrincipals", "value": base + extra}]))


def check_floor_change():
    """Q20: the root floor changed while a client keeps one connection open."""
    p = subprocess.Popen(["kubectl", "exec", "-n", OUTSIDER[0], OUTSIDER[1], "--", "python3", "/lab/client.py", "keep",
                          GW + "/orders/v2/get", HOST, tok("a", {"azp": f"keep-{RUN}", "allowed_apis": ["api.team-a.orders.gold"]}),
                          "18", "0.5"], stdout=subprocess.PIPE, text=True)  # 18 calls: under gold's 20 per minute
    time.sleep(3)
    floor_principals(["https://idp-c.lab/realms/apis/*"])
    time.sleep(4)
    floor_principals([])
    out, _ = p.communicate(timeout=60)
    got = json.loads(out.strip().splitlines()[-1])
    expect("Q20", "18 calls on a kept-open connection while the floor changes twice: no failure",
           set(got["counts"]) == {"200"}, True, f"got {got}")


def check_unreachable_issuer():
    """Q19: one issuer's keys can't be fetched; the others keep working."""
    ra = json.loads(kc("get", "requestauthentication", "mto-api-gateway-jwt", "-n", "team-a-dev", "-o", "json"))
    rules = ra["spec"]["jwtRules"]
    c_rule = {"issuer": "https://idp-c.lab/realms/apis", "jwksUri": "https://idp-c.lab.invalid/realms/apis/certs",
              "audiences": ["apis"], "fromHeaders": [{"name": "Authorization", "prefix": "Bearer "}]}
    kc("patch", "requestauthentication", "mto-api-gateway-jwt", "-n", "team-a-dev", "--type=json", "-p",
       json.dumps([{"op": "replace", "path": "/spec/jwtRules", "value": rules + [c_rule]}]))
    floor_principals(["https://idp-c.lab/realms/apis/*"])
    time.sleep(12)
    try:
        expect("Q19", "issuer c unreachable: issuer a's token still 200", req("/orders/v2/get", shop())["status"], 200)
        ctok = tok("c", {"azp": "cee", "allowed_apis": ["api.team-a.orders.silver"]})
        expect("Q19", "issuer c unreachable: c's token 401", req("/orders/v2/get", ctok)["status"], 401)
    finally:
        kc("patch", "requestauthentication", "mto-api-gateway-jwt", "-n", "team-a-dev", "--type=json", "-p",
           json.dumps([{"op": "replace", "path": "/spec/jwtRules", "value": rules}]))
        floor_principals([])
        time.sleep(5)


def check_external():
    """Q22, AC-EXT-1: a backend outside the cluster (needs internet)."""
    if os.environ.get("LAB_OFFLINE"):
        record("NOTE", "Q22 AC-EXT-1", "skipped: LAB_OFFLINE is set")
        return
    t = tok("a", {"azp": f"partner-{RUN}", "allowed_apis": ["api.team-a.partner.gold"]})
    r = req("/partner/v1/x", t)
    h = r.get("headers", {})
    expect("Q22 AC-EXT-1", "external backend over TLS: 200, Host rewritten, x-sub set, no token",
           (r["status"], hv(h, "host"), hv(h, "x-sub"), "authorization" in h),
           (200, "httpbin.org", f"partner-{RUN}", False), f"got {r['status']} host={hv(h, 'host')} x-sub={hv(h, 'x-sub')}")
    expect("AC-EXT-1", "external backend without the API's role: 403", req("/partner/v1/x", shop())["status"], 403)


def check_any_order():
    """AC-AUTH-7, issue #10: no request gets through while a tenant's objects are applied in any order."""
    objs = {}
    names = [("requestauthentication", "mto-api-gateway-jwt"), ("authorizationpolicy", "api.orders"),
             ("authorizationpolicy", "api.payments"), ("envoyfilter", "mto-api-gateway-strip-headers"),
             ("envoyfilter", "mto-api-gateway-ratelimit"), ("authorizationpolicy", "api.orders.orders")]
    for kind, name in names:
        o = json.loads(kc("get", kind, name, "-n", "team-a-dev", "-o", "json"))
        for k in ("resourceVersion", "uid", "creationTimestamp", "generation", "managedFields", "annotations"):
            o["metadata"].pop(k, None)
        o.pop("status", None)
        objs[(kind, name)] = json.dumps(o)
    attackers = {"no token": "", "no API role": tok("a", {"azp": "bare"}),
                 "orders2": tok("a", {"azp": "near", "allowed_apis": ["api.team-a.orders2.silver"]}),
                 "issuer b": tok("b", {"azp": "bank", "allowed_apis": ["api.team-a.orders.silver"]})}
    leaked = {}
    for round_ in range(3):
        for kind, name in names:
            kc("delete", kind, name, "-n", "team-a-dev", check=False)
        procs = {who: subprocess.Popen(["kubectl", "exec", "-n", OUTSIDER[0], OUTSIDER[1], "--", "python3", "/lab/client.py",
                                        "keep", GW + "/orders/v2/get", HOST, t or "-", "50", "0.2"],
                                       stdout=subprocess.PIPE, text=True) for who, t in attackers.items()}
        order = list(names)
        random.shuffle(order)
        for kind, name in order:
            time.sleep(1.5)
            apply(objs[(kind, name)])
        for who, p in procs.items():
            out, _ = p.communicate(timeout=90)
            counts = json.loads(out.strip().splitlines()[-1])["counts"]
            if "200" in counts:
                leaked[f"{who}, round {round_ + 1}"] = counts
    expect("AC-AUTH-7 #10", "3 shuffled apply orders, 4 attackers, 50 calls each: never a 200", leaked, {})
    time.sleep(5)
    expect("AC-AUTH-7", "after the applies, the allowed caller gets 200", req("/orders/v2/get", shop())["status"], 200)


def rl_loaded(limit_line="tier.azp"):
    ip = pod_ip("mto-api-gateways", "app=ratelimit")
    return kc("exec", "-n", OUTSIDER[0], OUTSIDER[1], "--", "python3", "-c",
              f"import urllib.request,re;t=urllib.request.urlopen('http://{ip}:6070/rlconfig',timeout=5).read().decode();"
              f"m=re.search(r'\\.tier\\.azp: unit=MINUTE requests_per_unit=(\\d+)',t);print(m.group(1) if m else '-')",
              check=False).strip()


def check_ratelimit_reload():
    """S1: a change of the mounted configuration, with the service running. Recorded, not judged."""
    def restarts():
        return int(kc("get", "pod", "-n", "mto-api-gateways", "-l", "app=ratelimit", "-o",
                      "jsonpath={.items[0].status.containerStatuses[0].restartCount}") or 0)
    notes = []
    for frm, to in [(4, 5), (5, 4)]:
        r0 = restarts()
        cm = json.loads(kc("get", "configmap", "ratelimit-config", "-n", "mto-api-gateways", "-o", "json"))
        cm["data"]["config.yaml"] = cm["data"]["config.yaml"].replace(f"requests_per_unit: {frm} }}", f"requests_per_unit: {to} }}")
        cm["metadata"].pop("resourceVersion", None)
        apply(json.dumps(cm))
        t0, loaded = time.time(), "-"
        while time.time() - t0 < 180:
            time.sleep(5)
            loaded = rl_loaded()
            if loaded == str(to):
                break
        notes.append(f"{frm}->{to}: loaded {loaded} after {int(time.time() - t0)}s, restarts {r0}->{restarts()}")
    record("NOTE", "S1", "rate limit configuration changed twice while running", "; ".join(notes))


CHECKS = [check_baseline, check_issuers, check_query_token, check_headers, check_paths, check_closed_rule,
          check_rate_limits, check_fail_open, check_lock, check_bypass, check_strict, check_metrics,
          check_mesh_caller_to_gateway, check_floor_change, check_unreachable_issuer, check_external,
          check_any_order, check_ratelimit_reload]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--istio", default=os.environ.get("ISTIO_VERSION", "unknown"))
    ap.add_argument("--only", default="")
    ap.add_argument("--skip", default="")
    a = ap.parse_args()
    only = set(filter(None, a.only.split(",")))
    skip = set(filter(None, a.skip.split(",")))
    checks = list(CHECKS)
    if kc("get", "crd", "templates.templates.v2.stakater.com", check=False):
        sys.path.insert(0, HERE)
        import to_checks
        to_checks.use(sys.modules[__name__])
        checks += to_checks.CHECKS
    else:
        record("NOTE", "T4 T6 T7 T10", "Template Operator checks skipped: Template Operator is not installed (TO_SRC)")
    for c in checks:
        name = c.__name__.replace("check_", "")
        if (only and name not in only) or name in skip:
            continue
        print(f"--- {name}: {c.__doc__.strip().splitlines()[0]}", flush=True)
        try:
            c()
        except Exception as e:  # a broken check is a failure, never a silent pass
            record("FAIL", name, "the check itself failed", str(e)[:200])
    os.makedirs(STATE, exist_ok=True)
    path = os.path.join(STATE, f"results-{a.istio}.md")
    with open(path, "w") as f:
        f.write(f"# G.19 lab results, Istio {a.istio}, {time.strftime('%Y-%m-%d %H:%M')}\n\n")
        f.write("| Result | Row | Check | Detail |\n|---|---|---|---|\n")
        for s, row, check, detail in RESULTS:
            cell = detail.replace("|", "/").replace("<", "&lt;").replace(">", "&gt;")
            f.write(f"| {s} | {row} | {check.replace('<', '&lt;')} | {cell} |\n")
    fails = sum(1 for r in RESULTS if r[0] == "FAIL")
    print(f"\n{len(RESULTS)} results, {fails} failed; written to {path}")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
