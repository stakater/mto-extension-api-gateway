{{- /* The parent: the platform's side of the self-service request.

       A team asks for its tenant's API gateway with a TemplateInstance of the
       "api-gateway" Template in one of its namespaces. That instance carries
       no parameters, so the team decides only WHERE its gateway runs (the
       namespace) and WHAT it is called (the instance name). Everything else
       comes from this parent, which publishes the api-gateway Template with
       every value as a disableOverride default:
         - tenantOf: namespace -> tenant, from the tenant label, for the
           tenants that may request a gateway. The team Template reads its
           instance's tenant from here, never from anything the team writes;
         - owner: tenant -> "<namespace>/<name>" of the one request that gets
           the tenant's gateway: the oldest valid one;
         - extraHostnames: tenant -> the extra host names granted to it, minus
           the refused ones.
       The parent also lists, in the skipped-tenants ConfigMap, the tenants it
       skipped, the host names it refused and the requests it refused. */ -}}
{{- $ns := .parameters.gatewayNamespace }}
{{- $label := .parameters.tenantLabelKey }}
{{- $base := .parameters.baseDomain }}
{{- $teamTemplate := .parameters.teamTemplateName }}
{{- $dnsLabel := "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" }}
{{- $hostRe := "^(\\*\\.)?([a-z0-9]([-a-z0-9]*[a-z0-9])?\\.)+[a-z0-9]([-a-z0-9]*[a-z0-9])?$" }}
{{- /* Tenants that may request a gateway. Skipped, and listed with the reason:
       a name that is not a DNS label (it becomes a label value and a host name
       label), or one over 63 characters (a label value's limit). With
       tenantsMode "list", a tenant not listed may not request one: that is the
       platform's choice, not an error, so it is not listed. */ -}}
{{- $allowed := dict }}
{{- $skipped := dict }}
{{- range $t := (default list .parameters.tenants) }}
{{- $name := toString $t.metadata.name }}
{{- if not (regexMatch $dnsLabel $name) }}
{{- $_ := set $skipped $name "the name is not a DNS label (lowercase letters, digits and hyphens, no dots): this tenant can't request an API gateway" }}
{{- else if gt (len $name) 63 }}
{{- $_ := set $skipped $name (printf "the name is %d characters, over the 63 a label value allows: this tenant can't request an API gateway" (len $name)) }}
{{- else if and (eq $.parameters.tenantsMode "list") (not (has $name (default list $.parameters.tenantList))) }}
{{- else }}
{{- $_ := set $allowed $name true }}
{{- end }}
{{- end }}
{{- /* namespace -> tenant, for the allowed tenants only. */ -}}
{{- $tenantOf := dict }}
{{- range $n := (default list .parameters.tenantNamespaces) }}
{{- $t := toString (dig "metadata" "labels" $label "" $n) }}
{{- if hasKey $allowed $t }}
{{- $_ := set $tenantOf (toString $n.metadata.name) $t }}
{{- end }}
{{- end }}
{{- /* Requests: TemplateInstances of the api-gateway Template, wherever they
       are. A request is valid when its namespace belongs to an allowed tenant
       and its name is a DNS label of at most 48 characters (it names the
       Gateway, and <name>-tls-extra-NN must stay within 63). One request per
       tenant gets the gateway: the oldest valid one; ties go to the first
       "<namespace>/<name>". Every other request is refused, with the reason. */ -}}
{{- $requests := list }}
{{- range $ti := (default list .parameters.templateInstances) }}
{{- $refName := toString (dig "spec" "templateRef" "name" "" $ti) }}
{{- $refNs := toString (dig "spec" "templateRef" "namespace" "" $ti) }}
{{- if and (eq $refName $teamTemplate) (eq $refNs $ns) (not (hasKey $ti.metadata "deletionTimestamp")) }}
{{- $requests = append $requests (dict "ns" (toString $ti.metadata.namespace) "name" (toString $ti.metadata.name) "ts" (toString (dig "metadata" "creationTimestamp" "" $ti))) }}
{{- end }}
{{- end }}
{{- $owner := dict }}
{{- $ownerTs := dict }}
{{- $refusedRequests := dict }}
{{- range $r := $requests }}
{{- $id := printf "%s/%s" $r.ns $r.name }}
{{- $t := get $tenantOf $r.ns }}
{{- if not $t }}
{{- $_ := set $refusedRequests $id (printf "namespace %s does not belong to a tenant that may request an API gateway" $r.ns) }}
{{- else if or (not (regexMatch $dnsLabel $r.name)) (gt (len $r.name) 48) }}
{{- $_ := set $refusedRequests $id "the TemplateInstance name must be a DNS label of at most 48 characters: it names the Gateway and its objects" }}
{{- else if or (not (hasKey $owner $t)) (lt $r.ts (get $ownerTs $t)) (and (eq $r.ts (get $ownerTs $t)) (lt $id (get $owner $t))) }}
{{- $_ := set $owner $t $id }}
{{- $_ := set $ownerTs $t $r.ts }}
{{- end }}
{{- end }}
{{- range $r := $requests }}
{{- $id := printf "%s/%s" $r.ns $r.name }}
{{- $t := get $tenantOf $r.ns }}
{{- if and $t (hasKey $owner $t) (ne (get $owner $t) $id) (not (hasKey $refusedRequests $id)) }}
{{- $_ := set $refusedRequests $id (printf "tenant %s already has its API gateway, from TemplateInstance %s; a tenant has one" $t (get $owner $t)) }}
{{- end }}
{{- end }}
{{- /* Extra host names (ADR-0009). Every granted (tenant, host) pair is checked
       against the base domain and against every other tenant's pairs; a host
       that overlaps another tenant's is refused for both. Overlap, not
       equality: *.wild.example.org and x.wild.example.org overlap. */ -}}
{{- $pairs := list }}
{{- range $t, $hosts := (default dict .parameters.extraHostnames) }}
{{- range $h := $hosts }}
{{- $pairs = append $pairs (dict "t" (toString $t) "h" (toString $h)) }}
{{- end }}
{{- end }}
{{- $refusedHosts := dict }}
{{- range $p := $pairs }}
{{- $h := $p.h }}
{{- $hw := hasPrefix "*." $h }}
{{- $hs := trimPrefix "*." $h }}
{{- $why := "" }}
{{- if not (regexMatch $hostRe $h) }}
{{- $why = "not a valid host name (lowercase letters, digits, hyphens and dots, optionally starting with *.)" }}
{{- else if or (eq $hs $base) (hasSuffix (printf ".%s" $base) $hs) (and $hw (hasSuffix (printf ".%s" $hs) $base)) }}
{{- $why = printf "overlaps the base domain %s, which is reserved for <tenant>.%s names" $base $base }}
{{- else }}
{{- range $q := $pairs }}
{{- if and (not $why) (ne $q.t $p.t) }}
{{- $qw := hasPrefix "*." $q.h }}
{{- $qs := trimPrefix "*." $q.h }}
{{- $x := false }}
{{- if and (not $hw) (not $qw) }}{{ $x = eq $h $q.h }}
{{- else if and $hw (not $qw) }}{{ $x = hasSuffix (printf ".%s" $hs) $q.h }}
{{- else if and (not $hw) $qw }}{{ $x = hasSuffix (printf ".%s" $qs) $h }}
{{- else }}{{ $x = or (eq $hs $qs) (hasSuffix (printf ".%s" $qs) $hs) (hasSuffix (printf ".%s" $hs) $qs) }}
{{- end }}
{{- if $x }}{{ $why = printf "overlaps %s, also granted to tenant %s" $q.h $q.t }}{{ end }}
{{- end }}
{{- end }}
{{- end }}
{{- if $why }}
{{- $_ := set $refusedHosts (printf "%s|%s" $p.t $h) $why }}
{{- end }}
{{- end }}
{{- /* The granted host names per allowed tenant, in the order given. */ -}}
{{- $extras := dict }}
{{- range $t, $hosts := (default dict .parameters.extraHostnames) }}
{{- if hasKey $allowed (toString $t) }}
{{- $ok := list }}
{{- range $h := $hosts }}
{{- if not (hasKey $refusedHosts (printf "%s|%s" (toString $t) (toString $h))) }}
{{- $ok = append $ok (toString $h) }}
{{- end }}
{{- end }}
{{- if $ok }}{{ $_ := set $extras (toString $t) $ok }}{{ end }}
{{- end }}
{{- end }}
{{- /* Skipped-tenants ConfigMap keys: a tenant's own name; "<tenant>.hostnames"
       (a tenant name has no dot, so it can't collide); and
       "request.<namespace>.<name>" for a refused request. */ -}}
{{- range $key, $why := $refusedHosts }}
{{- $parts := splitList "|" $key }}
{{- $k := printf "%s.hostnames" (index $parts 0) }}
{{- $line := printf "%s: %s" (index $parts 1) $why }}
{{- $prev := get $skipped $k }}
{{- $_ := set $skipped $k (ternary $line (printf "%s\n%s" $prev $line) (eq $prev "")) }}
{{- end }}
{{- range $id, $why := $refusedRequests }}
{{- $_ := set $skipped (printf "request.%s" (replace "/" "." $id)) $why }}
{{- end }}
{{- if $skipped }}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: mto-extension-api-gateway-skipped-tenants
  namespace: {{ $ns }}
data:
  {{- range $k, $reason := $skipped }}
  {{ $k | quote }}: {{ $reason | quote }}
  {{- end }}
{{- end }}
{{- /* The team-facing Template. Only tenant namespaces may instantiate it.
       Sync mode strict: the admission webhook refuses a team's edit or delete
       of anything it renders, so a team can't weaken its own gateway. */}}
---
apiVersion: templates.v2.stakater.com/v2alpha1
kind: Template
metadata:
  name: {{ $teamTemplate }}
  namespace: {{ $ns }}
spec:
  targetNamespaces:
    selector:
      matchExpressions:
        - key: {{ $label }}
          operator: Exists
  sync:
    mode: strict
  parameters:
    - name: tenantOf
      type: object
      value: {{ toJson $tenantOf }}
      disableOverride: true
    - name: owner
      type: object
      value: {{ toJson $owner }}
      disableOverride: true
    - name: extraHostnames
      type: object
      value: {{ toJson $extras }}
      disableOverride: true
    - name: tenantLabelKey
      value: {{ $label | quote }}
      disableOverride: true
    - name: baseDomain
      value: {{ $base | quote }}
      disableOverride: true
    - name: gatewayClassName
      value: {{ .parameters.gatewayClassName | quote }}
      disableOverride: true
    - name: port
      value: {{ .parameters.port | quote }}
      disableOverride: true
    - name: minReplicas
      value: {{ .parameters.minReplicas | quote }}
      disableOverride: true
    - name: maxReplicas
      value: {{ .parameters.maxReplicas | quote }}
      disableOverride: true
    - name: targetCPUUtilizationPercentage
      value: {{ .parameters.targetCPUUtilizationPercentage | quote }}
      disableOverride: true
    - name: pdbMinAvailable
      value: {{ .parameters.pdbMinAvailable | quote }}
      disableOverride: true
    - name: certManagerIssuerKind
      value: {{ .parameters.certManagerIssuerKind | quote }}
      disableOverride: true
    - name: certManagerIssuerName
      value: {{ .parameters.certManagerIssuerName | quote }}
      disableOverride: true
  gotemplate: |
{{ .parameters.teamGotemplate | indent 4 }}
