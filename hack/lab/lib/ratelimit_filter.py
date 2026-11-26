#!/usr/bin/env python3
"""Print the rate limit EnvoyFilter of design §3.3 (JSON) for the lab's APIs.

One virtual-host rate limit entry per API, matched on the API's host and path; descriptors
tenant, api, tier (a CEL expression over the role claim, exact text, ADR-0003, M20) and azp.
"""
import json, re

TENANT, GATEWAY, NAMESPACE = "team-a", "mto-api-gateway", "team-a-dev"
TIERS = ["gold", "silver"]          # highest first; anything else is the default tier
DEFAULT_TIER = "bronze"
# api name -> (host, path, today's role name or None)
APIS = {
    "orders": ("orders.team-a.apis.example.com", "/orders/v2", "api-orders-consumer"),
    "payments": ("orders.team-a.apis.example.com", "/payments/v1", None),
}

PAYLOAD = "metadata.filter_metadata['envoy.filters.http.jwt_authn']['payload']"
# The claim as a list, whatever its shape, so the expression can't fail.
ROLES = ("(('envoy.filters.http.jwt_authn' in metadata.filter_metadata && 'payload' in "
         "metadata.filter_metadata['envoy.filters.http.jwt_authn'] && 'allowed_apis' in " + PAYLOAD + ") ? "
         "(type(" + PAYLOAD + "['allowed_apis']) == list ? " + PAYLOAD + "['allowed_apis'] : "
         "[" + PAYLOAD + "['allowed_apis']]) : [])")


def tier_expr(api, legacy):
    expr = f"'{DEFAULT_TIER}'"
    for tier in reversed(TIERS):
        names = [f"api.{TENANT}.{api}.{tier}"] + ([f"{legacy}-{tier}"] if legacy else [])
        cond = " || ".join(f"'{n}' in {ROLES}" for n in names)
        expr = f"(({cond}) ? '{tier}' : {expr})"
    return expr


def entry(api, host, path, legacy):
    return {"actions": [
        {"generic_key": {"descriptor_key": "tenant", "descriptor_value": TENANT}},
        {"header_value_match": {"descriptor_key": "api", "descriptor_value": api, "headers": [
            {"name": ":authority", "string_match": {"safe_regex": {"regex": "^" + re.escape(host) + "(:[0-9]+)?$"}}},
            {"name": ":path", "string_match": {"safe_regex": {"regex": "^" + re.escape(path) + "([/?].*)?$"}}}]}},
        {"extension": {"name": "envoy.rate_limit_descriptors.expr", "typed_config": {
            "@type": "type.googleapis.com/envoy.extensions.rate_limit_descriptors.expr.v3.Descriptor",
            "descriptor_key": "tier", "text": tier_expr(api, legacy)}}},
        {"metadata": {"descriptor_key": "azp", "metadata_key": {
            "key": "envoy.filters.http.jwt_authn", "path": [{"key": "payload"}, {"key": "azp"}]}}},
    ]}


def main():
    hcm = {"filter": {"name": "envoy.filters.network.http_connection_manager",
                      "subFilter": {"name": "envoy.filters.http.router"}}}
    doc = {
        "apiVersion": "networking.istio.io/v1alpha3", "kind": "EnvoyFilter",
        "metadata": {"name": "mto-api-gateway-ratelimit", "namespace": NAMESPACE,
                     "labels": {"api-gateway.stakater.com/managed": "true"}},
        "spec": {
            "workloadSelector": {"labels": {"gateway.networking.k8s.io/gateway-name": GATEWAY}},
            "configPatches": [
                {"applyTo": "HTTP_FILTER",
                 "match": {"context": "GATEWAY", "listener": {"filterChain": hcm}},
                 "patch": {"operation": "INSERT_BEFORE", "value": {
                     "name": "envoy.filters.http.ratelimit",
                     "typed_config": {
                         "@type": "type.googleapis.com/envoy.extensions.filters.http.ratelimit.v3.RateLimit",
                         "domain": "mto-api-gateway", "failure_mode_deny": False, "timeout": "0.25s",
                         "rate_limit_service": {"grpc_service": {"envoy_grpc": {
                             "cluster_name": "outbound|8081||ratelimit.mto-api-gateways.svc.cluster.local"}},
                             "transport_api_version": "V3"}}}}},
                {"applyTo": "VIRTUAL_HOST",
                 "match": {"context": "GATEWAY", "routeConfiguration": {"vhost": {"name": "", "route": {"action": "ANY"}}}},
                 "patch": {"operation": "MERGE",
                           "value": {"rate_limits": [entry(a, *v) for a, v in APIS.items()]}}},
            ]}}
    print(json.dumps(doc, indent=1))


if __name__ == "__main__":
    main()
