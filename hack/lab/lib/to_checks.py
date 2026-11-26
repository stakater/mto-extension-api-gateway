"""Template Operator checks (T4, T6, T7, T10, AC-LIFE-7), run by checks.py when Template Operator is installed."""
import json, os, time

LAB = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TO = os.path.join(LAB, "to")
apply = expect = kc = record = None  # set by use(), from the running checks module


def use(m):
    """Share the runner's helpers, so results land in one list."""
    globals().update(apply=m.apply, expect=m.expect, kc=m.kc, record=m.record)


NOADOPT = os.path.join(LAB, "manifests", "90-no-adoption.yaml")


def ns(name):
    kc("delete", "namespace", name, "--wait=true", "--timeout=120s", check=False)
    kc("create", "namespace", name)
    kc("label", "namespace", name, "lab.stakater.com/to-check=true")


def instance(namespace, name, template, params=None):
    spec = {"templateRef": {"name": template, "namespace": "mto-api-gateways"}}
    if params:
        spec["parameters"] = params
    apply(json.dumps({"apiVersion": "templates.v2.stakater.com/v2alpha1", "kind": "TemplateInstance",
                      "metadata": {"name": name, "namespace": namespace}, "spec": spec}))
    time.sleep(15)


def conditions(namespace, name):
    o = json.loads(kc("get", "templateinstance", name, "-n", namespace, "-o", "json"))
    return {c["type"]: (c["status"], c.get("message", "")) for c in (o.get("status") or {}).get("conditions") or []}


def delete_instance(namespace, name):
    kc("delete", "templateinstance", name, "-n", namespace, "--wait=true", "--timeout=90s", check=False)
    time.sleep(8)


def live(namespace, kind, name):
    """(uid, taken over by Template Operator?, data owner or listener hosts) or None."""
    out = kc("get", kind, name, "-n", namespace, "-o", "json", check=False)
    if not out:
        return None
    o = json.loads(out)
    labels = o["metadata"].get("labels") or {}
    extra = (o.get("data") or {}).get("owner") or ",".join(l.get("hostname", "") for l in (o.get("spec") or {}).get("listeners", []))
    return o["metadata"]["uid"], "templates.v2.stakater.com/instance-uid" in labels, extra


def handmade(namespace, gateway="mto-api-gateway", configmap=True):
    gw = {"apiVersion": "gateway.networking.k8s.io/v1", "kind": "Gateway", "metadata": {"name": gateway, "namespace": namespace},
          "spec": {"gatewayClassName": "lab-unused", "listeners": [{"name": "old", "port": 80, "protocol": "HTTP", "hostname": "*.old.example.com"}]}}
    kc("apply", "--server-side", "--field-manager=helm", "-f", "-", stdin=json.dumps(gw))
    if configmap:
        cm = {"apiVersion": "v1", "kind": "ConfigMap", "metadata": {"name": "mto-api-gateway-infra", "namespace": namespace},
              "data": {"owner": "helm"}}
        kc("apply", "--server-side", "--field-manager=helm", "-f", "-", stdin=json.dumps(cm))


def setup():
    kc("apply", "-f", os.path.join(TO, "rbac.yaml"))
    kc("apply", "-f", os.path.join(TO, "templates.yaml"))


def check_to_takeover_control():
    """T4: the hazard, without the admission policy (the red control)."""
    setup()
    kc("delete", "-f", NOADOPT, check=False)
    time.sleep(3)
    n = "lab-to-control"
    ns(n)
    handmade(n)
    before = live(n, "gateway", "mto-api-gateway")
    instance(n, "req", "lab-api-gateway")
    after = live(n, "gateway", "mto-api-gateway")
    expect("T4", "without the policy, the request takes over the live Gateway (same UID, our label, our listener added)",
           (after[0] == before[0], after[1], "*.lab.example.com" in after[2]), (True, True, True), f"got {after}")
    delete_instance(n, "req")
    expect("T4", "without the policy, deleting the request deletes the live Gateway and ConfigMap",
           (live(n, "gateway", "mto-api-gateway"), live(n, "configmap", "mto-api-gateway-infra")), (None, None))


def check_to_takeover_guarded():
    """T10, AC-LIFE-7: with the admission policy, nothing is taken over."""
    setup()
    kc("apply", "-f", NOADOPT)
    time.sleep(3)
    n = "lab-to-guarded"
    ns(n)
    handmade(n)
    before = (live(n, "gateway", "mto-api-gateway"), live(n, "configmap", "mto-api-gateway-infra"))
    instance(n, "req", "lab-api-gateway")
    c = conditions(n, "req")
    expect("T10 AC-LIFE-7", "with the policy, the request applies nothing and its status names the Gateway",
           (c.get("Applied", ("?",))[0], "mto-api-gateway" in c.get("Applied", ("", ""))[1], live(n, "configmap", "mto-api-gateway-status.req")),
           ("False", True, None), f"Applied={c.get('Applied')}")
    expect("T10 AC-LIFE-7", "with the policy, both live objects are unchanged",
           (live(n, "gateway", "mto-api-gateway"), live(n, "configmap", "mto-api-gateway-infra")), before)
    delete_instance(n, "req")
    expect("T4 AC-LIFE-7", "with the policy, deleting the request leaves both live objects",
           (live(n, "gateway", "mto-api-gateway"), live(n, "configmap", "mto-api-gateway-infra")), before)
    taken = preflight_names()
    expect("AC-LIFE-7", "the preflight name check names both objects", sorted(taken),
           sorted([f"configmaps {n}/mto-api-gateway-infra", f"gateways {n}/mto-api-gateway"]))
    kc("delete", "namespace", n, "--wait=true", "--timeout=120s", check=False)
    expect("AC-LIFE-7", "with them gone, the preflight name check passes", preflight_names(), [])


def check_to_own_objects():
    """T10: our own objects are created, updated and deleted as usual, with the policy."""
    n = "lab-to-fresh"
    ns(n)
    instance(n, "req", "lab-api-gateway")
    expect("T10", "a new namespace: our objects are created", (live(n, "gateway", "mto-api-gateway") or (0, 0, ""))[1], True)
    kc("patch", "template", "lab-api-gateway", "-n", "mto-api-gateways", "--type=json",
       "-p", json.dumps([{"op": "replace", "path": "/spec/parameters/0/value", "value": "2"}]))
    time.sleep(15)
    v = kc("get", "configmap", "mto-api-gateway-infra", "-n", n, "-o", "jsonpath={.data.version}", check=False)
    kc("patch", "template", "lab-api-gateway", "-n", "mto-api-gateways", "--type=json",
       "-p", json.dumps([{"op": "replace", "path": "/spec/parameters/0/value", "value": "1"}]))
    expect("T10", "a Template change updates our own object", v, "2")
    delete_instance(n, "req")
    expect("T10", "deleting the request deletes our objects", live(n, "gateway", "mto-api-gateway"), None)


def check_to_other_extension():
    """T10: another extension's takeover, with no label of ours, still works."""
    n = "lab-to-other"
    ns(n)
    kc("apply", "--server-side", "--field-manager=old-controller", "-f", "-", stdin=json.dumps(
        {"apiVersion": "v1", "kind": "ConfigMap", "metadata": {"name": "appproject-x", "namespace": n}, "data": {"owner": "old-controller"}}))
    uid = live(n, "configmap", "appproject-x")[0]
    instance(n, "take", "lab-other-extension")
    after = live(n, "configmap", "appproject-x")
    expect("T10", "another extension takes over its object on purpose (same UID, its data)", (after[0] == uid, after[2]), (True, "other-extension"))
    delete_instance(n, "take")


def check_to_request_name():
    """ADR-0002: a request named like a live gateway gets mto-api-gateway; the live one is untouched."""
    n = "lab-to-name"
    ns(n)
    handmade(n, gateway="orders-gateway", configmap=False)
    before = live(n, "gateway", "orders-gateway")
    instance(n, "orders-gateway", "lab-api-gateway")
    expect("ADR-0002", "a request named orders-gateway renders mto-api-gateway; the live orders-gateway is unchanged",
           (live(n, "gateway", "orders-gateway"), (live(n, "gateway", "mto-api-gateway") or (0, 0, ""))[1]), (before, True))
    delete_instance(n, "orders-gateway")
    expect("ADR-0002", "deleting that request leaves the live orders-gateway", live(n, "gateway", "orders-gateway"), before)


def preflight_names():
    """The preflight's name check (design §9): reserved names without our label, outside mto-api-gateways."""
    taken = []
    for kind in ["configmaps", "services", "gateways"]:
        for o in json.loads(kc("get", kind, "-A", "-o", "json"))["items"]:
            m = o["metadata"]
            if (m["name"].startswith("mto-api-") or m["name"].startswith("api.")) and m.get("namespace") != "mto-api-gateways" \
                    and (m.get("labels") or {}).get("api-gateway.stakater.com/managed") != "true":
                taken.append(f"{kind} {m['namespace']}/{m['name']}")
    return taken


def routes_param(namespace, json_path=".items"):
    return {"name": "routes", "valueFrom": {"objectFieldRef": {"apiVersion": "gateway.networking.k8s.io/v1", "kind": "HTTPRoute",
                                                               "namespace": namespace, "jsonPath": json_path}}}


def check_to_list():
    """T7: what a LIST parameter gives the template, with one object and with none, for two JSONPaths."""
    kc("delete", "-f", NOADOPT, check=False)  # the probes are new objects; keep this check independent of the policy
    for n, with_route in [("lab-to-list", True), ("lab-to-empty", False)]:
        ns(n)
        if with_route:
            apply(json.dumps({"apiVersion": "gateway.networking.k8s.io/v1", "kind": "HTTPRoute",
                              "metadata": {"name": "plain", "namespace": n},
                              "spec": {"parentRefs": [{"name": "nowhere"}], "rules": [{"backendRefs": []}]}}))
        for probe, path in [("items", ".items"), ("names", ".items[*].metadata.name")]:
            instance(n, probe, "lab-list", [routes_param(n, path)])
            c = conditions(n, probe)
            d = json.loads(kc("get", "configmap", f"mto-api-gateway-list-probe.{probe}", "-n", n, "-o", "json", check=False) or '{"data": {}}')["data"]
            what = "one route" if with_route else "no route"
            record("NOTE", "T7", f"LIST of {what}, jsonPath {path}: Ready={c.get('Ready', ('?',))[0]}",
                   f"{d.get('routesType')} len={d.get('routesLen')} {d.get('routesJson', '')[:60]}; "
                   f"ParametersValid={c.get('ParametersValid', ('?', ''))[1][:100]}")
            if not with_route:
                want = "True" if probe == "items" else "False"
                expect("T7", f"a LIST of no objects, jsonPath {path}: Ready={want}", c.get("Ready", ("?",))[0], want,
                       f"{c.get('ParametersValid', ('?', ''))[1][:100]}")
    kc("apply", "-f", NOADOPT)


def check_to_missing_key():
    """T6: a missing key on a listed object: a field path fails the render; index doesn't."""
    n = "lab-to-list"  # one route, with no annotations
    instance(n, "dot", "lab-missing-dot", [routes_param(n)])
    c = conditions(n, "dot")
    expect("T6", "a field path to a missing annotation fails the render",
           (c.get("Rendered", ("?",))[0], live(n, "configmap", "mto-api-gateway-dot-probe")), ("False", None),
           f"Rendered={c.get('Rendered', ('?', ''))[1][:160]}")
    instance(n, "index", "lab-missing-index", [routes_param(n)])
    c = conditions(n, "index")
    v = kc("get", "configmap", "mto-api-gateway-index-probe", "-n", n, "-o", "jsonpath={.data.api}", check=False)
    expect("T6", "index on a missing annotation renders, as the text <no value> (so templates add default)",
           (c.get("Ready", ("?",))[0], v), ("True", "<no value>"), f"Ready={c.get('Ready', ('?',))[0]}, value={v!r}")
    for name in ["dot", "index", "items", "names"]:
        delete_instance(n, name)


CHECKS = [check_to_takeover_control, check_to_takeover_guarded, check_to_own_objects, check_to_other_extension,
          check_to_request_name, check_to_list, check_to_missing_key]
