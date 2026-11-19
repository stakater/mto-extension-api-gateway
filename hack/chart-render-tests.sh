#!/usr/bin/env bash
# Render tests for the mto-extension-api-gateway charts.
#
# There is no controller in this repo to catch a mistake downstream: these
# checks are the quality gate. Rules every check follows (as in
# mto-extension-vault-enterprise):
#   - A check that can pass on its own failure is worse than no check. Render on
#     its own line, check the status, then assert on the output.
#   - Every guard has a positive control, so a guard that rejects everything
#     cannot pass; the key guards are also mutation-tested here, on a render
#     broken on purpose.
#
# Two gotemplates: the parent (platform: tenants, namespaces and requests in;
# the team-facing api-gateway Template out) and the team template (one team
# request in; its gateway out, in its own namespace). The team template is
# rendered with the parameters the parent actually published.
#
#   1. structure   — the bootstrap renders one parent Template and its
#                    TemplateInstance; the parent carries files/parent-gotemplate.tpl
#                    and, as teamGotemplate, files/team-gotemplate.tpl, byte for byte.
#   2. params      — every parameter either gotemplate reads is declared; the
#                    fixture sets every parent parameter; every parameter of the
#                    team Template is disableOverride (a team supplies none).
#   3. sync        — the parent Template syncs revert or strict; the team
#                    Template syncs strict (teams can't edit or delete what it renders).
#   4. golden      — the parent render and every team render equal the golden.
#   5. emission    — the parent publishes one api-gateway Template, open only to
#                    tenant namespaces, with the right namespace->tenant map, one
#                    owner request per tenant (oldest, ties by name), the granted
#                    host names, and every skip listed; list mode limits both maps.
#   6. requests    — the owner request renders its Gateway in its own namespace,
#                    named like the request; every other request renders only a
#                    status ConfigMap saying why.
#   7. trust       — a request can't change its tenant: forged instance labels
#                    change nothing, and a request in another tenant's namespace
#                    under the owner's name is refused.
#   8. listener    — AC-R-5: every listener takes routes only from its tenant's
#                    namespaces, kind HTTPRoute only, with a hostname; the tenant
#                    listener serves *.<tenant>.<base domain>. Mutation-tested.
#   9. extrahosts  — ADR-0009: a granted host name gets its own listener; an
#                    invalid one, one inside the base domain, one granted to two
#                    tenants, and a wildcard covering another's are refused for
#                    both sides and listed.
#  10. forbidden   — AC-R-1: no EnvoyFilter, WasmPlugin or TrafficExtension in
#                    any render. Mutation-tested.
#  11. namespace   — the parent renders only into the platform namespace; a team
#                    request renders only into its own namespace.
#  12. certs       — with a cert-manager issuer, one Certificate per listener with
#                    the listener's host name and Secret; without one, none.
#  13. schema      — a class other than istio, an empty base domain, sync mode
#                    off, fewer than 2 minimum replicas fail the install.
#  14. rbaccover   — the parent's kinds are writable in the platform namespace;
#                    the team kinds are writable cluster-wide (tenant namespaces).
#  15. crd         — every rendered Gateway and Certificate validates against the
#                    vendored CRDs (hack/crds), with an exact object count.
#
# The gotemplates are rendered through helm's tpl — an approximation of Template
# Operator's text/template + Sprig engine that is exact for the constructs they
# use.
#
# Regenerate the golden after an INTENTIONAL change: make golden
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP="$REPO_ROOT/charts/mto-extension-api-gateway-bootstrap"
FIXTURES="$REPO_ROOT/hack/render-fixtures"
CRDS="$REPO_ROOT/hack/crds"
HELM="${HELM:-helm}"
YQ="${YQ:-yq}"
GO="${GO:-go}"
RELEASE=mto-extension-api-gateway
NS=mto-api-gateways
BASE=apis.example.com
LABEL=stakater.com/tenant
PARENT_TPL="$BOOTSTRAP/files/parent-gotemplate.tpl"
TEAM_TPL="$BOOTSTRAP/files/team-gotemplate.tpl"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fails=0

check() { # check <name> <status> [message]
  if [ "$2" = 0 ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s: %s\n' "$1" "${3:-}"
    fails=$((fails + 1))
  fi
}
first() { head -n 1 "$1" 2>/dev/null || true; }
# per_doc <expr> <file...> — evaluate per document (yq e), one result per line,
# sorted. Use it for any expression with "as $var": in eval-all mode a variable
# binds across every document of the stream.
per_doc() { local expr="$1"; shift; "$YQ" e "$expr" "$@" | { grep -v '^---$' || true; } | sed '/^$/d' | LC_ALL=C sort; }
csv() { paste -sd, -; }
sorted_docs() { # sorted_docs <file...> -> stable, key-sorted documents
  "$YQ" ea -P '[.] | sort_by(.apiVersion + "|" + .kind + "|" + (.metadata.namespace // "") + "|" + .metadata.name) | .[] | sort_keys(..) | splitDoc' "$@"
}
trim() { sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$1"; }

for tool in "$HELM" "$YQ" "$GO"; do
  command -v "$tool" > /dev/null || { echo "FAIL setup: $tool not found"; exit 1; }
done
for f in "$BOOTSTRAP/Chart.yaml" "$PARENT_TPL" "$TEAM_TPL" "$FIXTURES/parent-params.yaml" "$FIXTURES/team-instances.txt"; do
  [ -f "$f" ] || { echo "FAIL setup: missing $f"; exit 1; }
done

# --- renders -----------------------------------------------------------------

if ! "$HELM" template "$RELEASE" "$BOOTSTRAP" -n "$NS" --set gateway.baseDomain="$BASE" \
    > "$WORK/bootstrap.yaml" 2> "$WORK/bootstrap.err"; then
  echo "FAIL setup: the bootstrap chart does not render: $(first "$WORK/bootstrap.err")"
  exit 1
fi

shim() { # shim <dir> <file> <context expression>
  mkdir -p "$1/templates" "$1/files"
  cp "$2" "$1/files/body.tpl"
  printf 'apiVersion: v2\nname: shim\nversion: 0.0.1\n' > "$1/Chart.yaml"
  printf '{{ tpl ($.Files.Get "files/body.tpl") %s }}\n' "$3" > "$1/templates/render.yaml"
}
shim "$WORK/parent-shim" "$PARENT_TPL" '(dict "parameters" .Values.parameters)'
shim "$WORK/team-shim" "$TEAM_TPL" '(dict "parameters" .Values.parameters "instance" .Values.instance)'
printf 'instance: { name: "", namespace: "", labels: {} }\n' > "$WORK/team-shim/values.yaml"

render_parent() { # render_parent <out> [helm args...]
  local out="$1"; shift
  if ! "$HELM" template shim "$WORK/parent-shim" -f "$FIXTURES/parent-params.yaml" \
      --set-file parameters.teamGotemplate="$TEAM_TPL" "$@" > "$out" 2> "$out.err"; then
    echo "FAIL setup: the parent gotemplate does not render ($*): $(first "$out.err")"
    exit 1
  fi
}
render_parent "$WORK/parent.yaml"
render_parent "$WORK/parent-certs.yaml" --set parameters.certManagerIssuerName=platform-ca
render_parent "$WORK/parent-list.yaml" --set parameters.tenantsMode=list --set 'parameters.tenantList={team-a}'

team_params() { # team_params <parent render> <out> — the api-gateway Template's parameters as values
  "$YQ" e 'select(.kind == "Template" and .metadata.name == "api-gateway")
    | {"parameters": (.spec.parameters | map({"key": .name, "value": .value}) | from_entries)}' "$1" > "$2"
}
team_params "$WORK/parent.yaml" "$WORK/team-params.yaml"
team_params "$WORK/parent-certs.yaml" "$WORK/team-params-certs.yaml"

render_team() { # render_team <params> <namespace> <name> <out> [helm args...]
  local params="$1" ns="$2" name="$3" out="$4"; shift 4
  if ! "$HELM" template shim "$WORK/team-shim" -f "$params" \
      --set-string instance.namespace="$ns" --set-string instance.name="$name" "$@" > "$out" 2> "$out.err"; then
    echo "FAIL setup: the team gotemplate does not render for $ns/$name: $(first "$out.err")"
    exit 1
  fi
}
mkdir -p "$WORK/team" "$WORK/team-certs"
: > "$WORK/team.yaml"; : > "$WORK/team-certs.yaml"
while read -r ns name want; do
  case "$ns" in ''|'#'*) continue ;; esac
  render_team "$WORK/team-params.yaml" "$ns" "$name" "$WORK/team/$ns.$name.yaml"
  render_team "$WORK/team-params-certs.yaml" "$ns" "$name" "$WORK/team-certs/$ns.$name.yaml"
  cat "$WORK/team/$ns.$name.yaml" >> "$WORK/team.yaml"
  cat "$WORK/team-certs/$ns.$name.yaml" >> "$WORK/team-certs.yaml"
done < "$FIXTURES/team-instances.txt"

# --- 1. structure -------------------------------------------------------------

n_tpl=$("$YQ" ea '[select(.kind == "Template" and .metadata.name == "mto-extension-api-gateway-parent")] | length' "$WORK/bootstrap.yaml")
n_ti=$("$YQ" ea '[select(.kind == "TemplateInstance" and .spec.templateRef.name == "mto-extension-api-gateway-parent")] | length' "$WORK/bootstrap.yaml")
"$YQ" e 'select(.kind == "Template") | .spec.gotemplate' "$WORK/bootstrap.yaml" > "$WORK/embedded-parent.tpl"
"$YQ" e 'select(.kind == "Template") | .spec.parameters[] | select(.name == "teamGotemplate") | .value' "$WORK/bootstrap.yaml" > "$WORK/embedded-team.tpl"
"$YQ" e 'select(.kind == "Template" and .metadata.name == "api-gateway") | .spec.gotemplate' "$WORK/parent.yaml" > "$WORK/published-team.tpl"
if [ "$n_tpl" = 1 ] && [ "$n_ti" = 1 ] \
    && diff -q <(trim "$WORK/embedded-parent.tpl") <(trim "$PARENT_TPL") > /dev/null \
    && diff -q <(trim "$WORK/embedded-team.tpl") <(trim "$TEAM_TPL") > /dev/null \
    && diff -q <(trim "$WORK/published-team.tpl") <(trim "$TEAM_TPL") > /dev/null; then
  check structure 0
else
  check structure 1 "Templates=$n_tpl TemplateInstances=$n_ti, or an embedded or published gotemplate differs from files/"
fi

# --- 2. params ----------------------------------------------------------------

grep -o '\.parameters\.[A-Za-z0-9]*' "$PARENT_TPL" | sed 's/.*\.parameters\.//' | LC_ALL=C sort -u > "$WORK/p-used"
"$YQ" e 'select(.kind == "Template") | .spec.parameters[].name' "$WORK/bootstrap.yaml" | LC_ALL=C sort -u > "$WORK/p-declared"
"$YQ" '.parameters | keys | .[]' "$FIXTURES/parent-params.yaml" | LC_ALL=C sort -u > "$WORK/p-fixture"
{ grep -o '\$p\.[A-Za-z0-9]*' "$TEAM_TPL" | sed 's/^\$p\.//'; grep -o '\.parameters\.[A-Za-z0-9]*' "$TEAM_TPL" | sed 's/.*\.parameters\.//'; } | LC_ALL=C sort -u > "$WORK/t-used"
"$YQ" e 'select(.kind == "Template" and .metadata.name == "api-gateway") | .spec.parameters[].name' "$WORK/parent.yaml" | LC_ALL=C sort -u > "$WORK/t-declared"
open_params=$("$YQ" e 'select(.kind == "Template" and .metadata.name == "api-gateway") | .spec.parameters[] | select(.disableOverride != true) | .name' "$WORK/parent.yaml" | csv)
p_undeclared=$(comm -23 "$WORK/p-used" "$WORK/p-declared" | csv)
p_unfixtured=$(comm -23 "$WORK/p-declared" "$WORK/p-fixture" | csv)
t_undeclared=$(comm -23 "$WORK/t-used" "$WORK/t-declared" | csv)
if [ -s "$WORK/p-used" ] && [ -s "$WORK/t-used" ] && [ -z "$p_undeclared$p_unfixtured$t_undeclared$open_params" ]; then
  check params 0
else
  check params 1 "parent reads undeclared [$p_undeclared]; parent declared but not in fixture [$p_unfixtured]; team reads undeclared [$t_undeclared]; team parameters a team could set [$open_params]"
fi

# --- 3. sync ------------------------------------------------------------------

pmode=$("$YQ" e 'select(.kind == "Template") | .spec.sync.mode' "$WORK/bootstrap.yaml")
tmode=$("$YQ" e 'select(.kind == "Template" and .metadata.name == "api-gateway") | .spec.sync.mode' "$WORK/parent.yaml")
case "$pmode/$tmode" in
  revert/strict|strict/strict) check sync 0 ;;
  *) check sync 1 "parent '$pmode' (want revert or strict), team '$tmode' (want strict)" ;;
esac

# --- 4. golden ----------------------------------------------------------------

sorted_docs "$WORK/parent.yaml" "$WORK/team.yaml" > "$WORK/all.sorted.yaml"
if [ "${UPDATE_GOLDEN:-}" = 1 ]; then
  cp "$WORK/all.sorted.yaml" "$FIXTURES/golden.yaml"
  echo "note golden regenerated: $FIXTURES/golden.yaml"
fi
if [ ! -f "$FIXTURES/golden.yaml" ]; then
  check golden 1 "no committed golden; run make golden after checking the render"
elif diff -u "$FIXTURES/golden.yaml" "$WORK/all.sorted.yaml" > "$WORK/golden.diff"; then
  check golden 0
else
  check golden 1 "the render differs from the golden: $(sed -n 3,6p "$WORK/golden.diff" | tr '\n' ' ')"
fi

# --- 5. emission --------------------------------------------------------------

tparam() { # tparam <render> <name> <yq expr on the value>
  "$YQ" e "select(.kind == \"Template\" and .metadata.name == \"api-gateway\") | .spec.parameters[] | select(.name == \"$2\") | .value | $3" "$1"
}
n_team_tpl=$("$YQ" ea "[select(.kind == \"Template\" and .metadata.name == \"api-gateway\" and .metadata.namespace == \"$NS\")] | length" "$WORK/parent.yaml")
selector=$("$YQ" e 'select(.metadata.name == "api-gateway") | .spec.targetNamespaces.selector.matchExpressions[] | .key + " " + .operator' "$WORK/parent.yaml")
tenant_of=$(tparam "$WORK/parent.yaml" tenantOf 'to_entries | .[] | .key + "=" + .value' | LC_ALL=C sort | csv)
owners=$(tparam "$WORK/parent.yaml" owner 'to_entries | .[] | .key + "=" + .value' | LC_ALL=C sort | csv)
granted=$(tparam "$WORK/parent.yaml" extraHostnames 'to_entries | .[] | .key + "=" + (.value | join(";"))' | csv)
skipped=$("$YQ" e 'select(.metadata.name == "mto-extension-api-gateway-skipped-tenants") | .data | keys | .[]' "$WORK/parent.yaml" | LC_ALL=C sort | csv)
list_owner=$(tparam "$WORK/parent-list.yaml" owner 'keys | .[]' | csv)
list_tenant_of=$(tparam "$WORK/parent-list.yaml" tenantOf 'keys | .[]' | LC_ALL=C sort | csv)
want_tenant_of="idle-dev=idle,n1234=1234,team-a-dev=team-a,team-a-test=team-a,team-b-dev=team-b,team-core=team"
want_owners="1234=n1234/a,team-a=team-a-test/edge,team-b=team-b-dev/api-gateway,team=team-core/gw"
want_skipped=$(printf '%s\n' Upper has.dot request.has-dot-ns.api-gateway request.n1234.b request.team-a-dev.api-gateway \
  request.team-b-dev.bad.name request.unlabelled.api-gateway team-a.hostnames team-b.hostnames team.hostnames \
  tenant-name-of-sixty-four-characters-which-is-one-over-the-cap-x | LC_ALL=C sort | csv)
if [ "$n_team_tpl" = 1 ] && [ "$selector" = "$LABEL Exists" ] && [ "$tenant_of" = "$want_tenant_of" ] \
    && [ "$owners" = "$want_owners" ] && [ "$granted" = "team-a=api.team-a.example.org" ] \
    && [ "$skipped" = "$want_skipped" ] && [ "$list_owner" = "team-a" ] && [ "$list_tenant_of" = "team-a-dev,team-a-test" ]; then
  check emission 0
else
  check emission 1 "templates=$n_team_tpl selector=[$selector]; tenantOf=[$tenant_of]; owner=[$owners]; granted=[$granted]; skipped=[$skipped] want [$want_skipped]; list owner=[$list_owner] tenantOf=[$list_tenant_of]"
fi

# --- 6. requests --------------------------------------------------------------

req_ok=0; req_msg=""; n_ok=0
while read -r ns name want; do
  case "$ns" in ''|'#'*) continue ;; esac
  f="$WORK/team/$ns.$name.yaml"
  status=$("$YQ" e "select(.kind == \"ConfigMap\" and .metadata.name == \"$name-status\") | .data.status" "$f")
  gws=$(per_doc 'select(.kind == "Gateway") | .metadata.namespace + "/" + .metadata.name' "$f" | csv)
  others=$(per_doc 'select(.kind != null and .metadata.name != "'"$name"'-status") | .kind' "$f" | csv)
  if [ "$want" = ok ]; then
    n_ok=$((n_ok + 1))
    [ "$status" = ok ] && [ "$gws" = "$ns/$name" ] || { req_ok=1; req_msg="$req_msg $ns/$name: status=$status gateways=[$gws];"; }
  else
    reason=$("$YQ" e "select(.metadata.name == \"$name-status\") | .data.reason" "$f")
    [ "$status" = refused ] && [ -z "$others" ] && [ -n "$reason" ] || { req_ok=1; req_msg="$req_msg $ns/$name: status=$status others=[$others] reason=[$reason];"; }
  fi
done < "$FIXTURES/team-instances.txt"
total_gw=$("$YQ" ea '[select(.kind == "Gateway")] | length' "$WORK/team.yaml")
[ "$total_gw" = "$n_ok" ] && [ "$n_ok" -gt 0 ] || { req_ok=1; req_msg="$req_msg gateways=$total_gw want $n_ok;"; }
check requests "$req_ok" "$req_msg"

# --- 7. trust -----------------------------------------------------------------

render_team "$WORK/team-params.yaml" team-a-test edge "$WORK/forged-labels.yaml" \
  --set-string 'instance.labels.stakater\.com/tenant=team-b'
render_team "$WORK/team-params.yaml" team-b-dev edge "$WORK/forged-ns.yaml"
forged_sel=$(per_doc "select(.kind == \"Gateway\") | .spec.listeners[] | .allowedRoutes.namespaces.selector.matchLabels[\"$LABEL\"] + \" \" + .hostname" "$WORK/forged-labels.yaml" | csv)
forged_ns=$("$YQ" e 'select(.metadata.name == "edge-status") | .data.status' "$WORK/forged-ns.yaml")
forged_gw=$("$YQ" ea '[select(.kind == "Gateway")] | length' "$WORK/forged-ns.yaml")
if [ "$forged_sel" = "team-a *.team-a.$BASE,team-a api.team-a.example.org" ] && [ "$forged_ns" = refused ] && [ "$forged_gw" = 0 ]; then
  check trust 0
else
  check trust 1 "forged labels gave listeners [$forged_sel]; team-b-dev/edge status=$forged_ns gateways=$forged_gw"
fi

# --- 8. listener (mutation-tested) --------------------------------------------

listener_violations() { # listener_violations <render> -> one line per bad listener
  per_doc "select(.kind == \"Gateway\") | .metadata.labels[\"$LABEL\"] as \$t | .metadata.name as \$g | .spec.listeners[]
    | select((\$t // \"\") == \"\"
        or .allowedRoutes.namespaces.from != \"Selector\"
        or .allowedRoutes.namespaces.selector.matchLabels[\"$LABEL\"] != \$t
        or (.allowedRoutes.namespaces.selector.matchExpressions // [] | length) != 0
        or (.allowedRoutes.kinds | length) != 1
        or .allowedRoutes.kinds[0].kind != \"HTTPRoute\"
        or (.hostname // \"\") == \"\"
        or (.name == \"tenant\" and .hostname != \"*.\" + \$t + \".$BASE\"))
    | \$g + \"/\" + .name" "$1"
}
bad=$(listener_violations "$WORK/team.yaml" | csv)
n_listeners=$("$YQ" ea '[select(.kind == "Gateway") | .spec.listeners[]] | length' "$WORK/team.yaml")
n_tenant=$("$YQ" ea '[select(.kind == "Gateway") | .spec.listeners[] | select(.name == "tenant")] | length' "$WORK/team.yaml")
sed 's/from: Selector/from: All/' "$WORK/team.yaml" > "$WORK/mut-listener.yaml"
mut=$(listener_violations "$WORK/mut-listener.yaml")
if [ -z "$bad" ] && [ "$n_tenant" = "$n_ok" ] && [ "$n_listeners" -gt "$n_tenant" ] && [ -n "$mut" ]; then
  check listener 0
else
  check listener 1 "violations=[$bad]; tenant listeners=$n_tenant (want $n_ok); listeners=$n_listeners; mutation caught=[${mut:+yes}]"
fi

# --- 9. extrahosts ------------------------------------------------------------

extras=$(per_doc 'select(.kind == "Gateway") | .metadata.name as $g | .spec.listeners[] | select(.name != "tenant") | $g + "/" + .name + "=" + .hostname' "$WORK/team.yaml" | csv)
reasons=$("$YQ" e 'select(.metadata.name == "mto-extension-api-gateway-skipped-tenants") | .data' "$WORK/parent.yaml")
ok=0
[ "$extras" = "edge/extra-1=api.team-a.example.org" ] || ok=1
for want in "Bad_Host.example.org" "shared.example.org" '\*.wild.example.org' "x.wild.example.org" "orders.apis.example.com"; do
  echo "$reasons" | grep -q "$want" || { ok=1; extras="$extras; '$want' not listed"; }
done
for t in team-b team; do
  line=$("$YQ" e "select(.metadata.name == \"mto-extension-api-gateway-skipped-tenants\") | .data[\"$t.hostnames\"]" "$WORK/parent.yaml")
  echo "$line" | grep -q "shared.example.org" || { ok=1; extras="$extras; shared.example.org not refused for $t"; }
done
check extrahosts "$ok" "extra listeners=[$extras]"

# --- 10. forbidden (mutation-tested) ------------------------------------------

forbidden() { "$YQ" ea 'select(.kind == "EnvoyFilter" or .kind == "WasmPlugin" or .kind == "TrafficExtension") | .kind + "/" + .metadata.name' "$@"; }
bad=$(forbidden "$WORK/bootstrap.yaml" "$WORK/parent.yaml" "$WORK/parent-certs.yaml" "$WORK/parent-list.yaml" "$WORK/team.yaml" "$WORK/team-certs.yaml")
cp "$WORK/team.yaml" "$WORK/mut-forbidden.yaml"
printf -- '---\napiVersion: networking.istio.io/v1alpha3\nkind: EnvoyFilter\nmetadata: { name: patch, namespace: team-a-test }\n' >> "$WORK/mut-forbidden.yaml"
mut=$(forbidden "$WORK/mut-forbidden.yaml")
if [ -z "$bad" ] && [ -n "$mut" ]; then
  check forbidden 0
else
  check forbidden 1 "forbidden kinds rendered: [$bad]; mutation caught=[${mut:+yes}]"
fi

# --- 11. namespace ------------------------------------------------------------

stray=$("$YQ" ea "select(.kind != null and .metadata.namespace != \"$NS\") | .kind + \"/\" + .metadata.name" "$WORK/parent.yaml" "$WORK/parent-certs.yaml" | csv)
while read -r ns name want; do
  case "$ns" in ''|'#'*) continue ;; esac
  s=$("$YQ" ea "select(.kind != null and .metadata.namespace != \"$ns\") | .kind + \"/\" + .metadata.name" \
    "$WORK/team/$ns.$name.yaml" "$WORK/team-certs/$ns.$name.yaml" | csv)
  [ -z "$s" ] || stray="$stray $ns/$name rendered outside $ns: $s;"
done < "$FIXTURES/team-instances.txt"
n_objs=$("$YQ" ea '[select(.kind != null)] | length' "$WORK/team.yaml")
if [ -z "$stray" ] && [ "$n_objs" -gt 0 ]; then
  check namespace 0
else
  check namespace 1 "$stray (team objects=$n_objs)"
fi

# --- 12. certs ----------------------------------------------------------------

certs=$(per_doc 'select(.kind == "Certificate") | .metadata.namespace + "/" + .metadata.name + "=" + .spec.secretName + "=" + (.spec.dnsNames | join(";"))' "$WORK/team-certs.yaml" | csv)
refs=$(per_doc 'select(.kind == "Gateway") | .metadata.namespace as $n | .spec.listeners[] | $n + "/" + .tls.certificateRefs[0].name + "=" + .tls.certificateRefs[0].name + "=" + .hostname' "$WORK/team-certs.yaml" | csv)
nocert=$("$YQ" ea '[select(.kind == "Certificate")] | length' "$WORK/team.yaml")
issuer=$("$YQ" ea '[select(.kind == "Certificate") | select(.spec.issuerRef.name != "platform-ca" or .spec.issuerRef.kind != "ClusterIssuer")] | length' "$WORK/team-certs.yaml")
if [ -n "$certs" ] && [ "$certs" = "$refs" ] && [ "$nocert" = 0 ] && [ "$issuer" = 0 ]; then
  check certs 0
else
  check certs 1 "certificates=[$certs] listeners=[$refs]; without issuer=$nocert; wrong issuer=$issuer"
fi

# --- 13. schema ---------------------------------------------------------------

schema_ok=0; schema_msg=""
must_fail() { # must_fail <label> <helm --set args...>
  local label="$1"; shift
  if "$HELM" template "$RELEASE" "$BOOTSTRAP" -n "$NS" "$@" > /dev/null 2> "$WORK/schema.err"; then
    schema_ok=1; schema_msg="$schema_msg $label rendered;"
  fi
}
must_fail "an empty base domain"
must_fail "class openshift-default" --set gateway.baseDomain="$BASE" --set gateway.className=openshift-default
must_fail "sync off" --set gateway.baseDomain="$BASE" --set templateSync.mode=off
must_fail "minReplicas 1" --set gateway.baseDomain="$BASE" --set gateway.autoscaling.minReplicas=1
must_fail "max below min" --set gateway.baseDomain="$BASE" --set gateway.autoscaling.minReplicas=4 --set gateway.autoscaling.maxReplicas=3
must_fail "a base domain with a wildcard" --set gateway.baseDomain='*.example.com'
check schema "$schema_ok" "should have failed:$schema_msg"

# --- 14. rbaccover ------------------------------------------------------------

resource_of() { # resource_of <kind> -> group/resource
  case "$1" in
    Gateway) echo "gateway.networking.k8s.io/gateways" ;;
    ConfigMap) echo "/configmaps" ;;
    Certificate) echo "cert-manager.io/certificates" ;;
    Template) echo "templates.v2.stakater.com/templates" ;;
    *) echo "UNKNOWN:$1" ;;
  esac
}
can() { # can <Role|ClusterRole> <group/resource> <verb>
  local group="${2%%/*}" res="${2#*/}"
  "$YQ" ea "[select(.kind == \"$1\" and .metadata.name == \"mto-extension-api-gateway-manager\")
    | .rules[] | select((.apiGroups[] == \"$group\") and (.resources[] == \"$res\") and (.verbs[] == \"$3\"))] | length" \
    "$WORK/bootstrap.yaml"
}
rbac_ok=0; rbac_msg=""
need() { # need <render> <Role|ClusterRole> <verbs...>
  local render="$1" role="$2"; shift 2
  local kinds; kinds=$(per_doc 'select(.kind != null) | .kind' "$render" | LC_ALL=C sort -u)
  [ -n "$kinds" ] || { rbac_ok=1; rbac_msg="$rbac_msg no kinds in $render;"; return; }
  while read -r kind; do
    local r; r=$(resource_of "$kind")
    case "$r" in UNKNOWN:*) rbac_ok=1; rbac_msg="$rbac_msg $kind has no RBAC mapping;"; continue ;; esac
    for verb in "$@"; do
      [ "$(can "$role" "$r" "$verb")" -gt 0 ] || { rbac_ok=1; rbac_msg="$rbac_msg $role cannot $verb $r;"; }
    done
  done <<< "$kinds"
}
need "$WORK/parent-certs.yaml" Role create update delete
need "$WORK/parent-certs.yaml" ClusterRole list
need "$WORK/team-certs.yaml" ClusterRole create update delete list
check rbaccover "$rbac_ok" "$rbac_msg"

# --- 15. crd ------------------------------------------------------------------

want_crd=$("$YQ" ea '[select(.kind == "Gateway" or .kind == "Certificate")] | length' "$WORK/team-certs.yaml")
if (cd "$REPO_ROOT" && "$GO" run ./hack/crd-validate -min "$want_crd" "$CRDS" "$WORK/team-certs.yaml") > "$WORK/crd.out" 2>&1 \
    && grep -q "^OK $want_crd " "$WORK/crd.out"; then
  check crd 0
else
  check crd 1 "$(tr '\n' ' ' < "$WORK/crd.out" | cut -c1-400) (want exactly $want_crd objects)"
fi

echo
if [ "$fails" -gt 0 ]; then
  echo "chart-render-tests: $fails check(s) failed"
  exit 1
fi
echo "chart-render-tests: all checks passed"
