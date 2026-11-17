{{- /* The team's side: one TemplateInstance of this Template, in one of the
       tenant's namespaces, asks for the tenant's API gateway. It renders into
       the instance's own namespace, and nowhere else.

       Trust: the instance has no parameters (every one is disableOverride, set
       by the platform's parent). The tenant comes from .parameters.tenantOf,
       keyed by the instance's namespace, never from the instance's labels or
       anything else the team writes. Every outcome renders the status
       ConfigMap <name>-status, so the team sees why it has, or hasn't, a
       gateway. */ -}}
{{- $p := .parameters }}
{{- $ns := .instance.namespace }}
{{- $name := .instance.name }}
{{- $label := $p.tenantLabelKey }}
{{- $base := $p.baseDomain }}
{{- $tenant := toString (index $p.tenantOf $ns | default "") }}
{{- $me := printf "%s/%s" $ns $name }}
{{- $owner := toString (index $p.owner $tenant | default "") }}
{{- $why := "" }}
{{- if not $tenant }}
{{- $why = printf "namespace %s does not belong to a tenant that may request an API gateway" $ns }}
{{- else if or (not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $name)) (gt (len $name) 48) }}
{{- $why = "the TemplateInstance name must be a DNS label of at most 48 characters: it names the Gateway and its objects" }}
{{- else if ne $owner $me }}
{{- $why = printf "tenant %s already has its API gateway, from TemplateInstance %s; a tenant has one" $tenant (default "(none yet: the platform has not seen this request; it retries)" $owner) }}
{{- end }}
{{- $listeners := list }}
{{- $hosts := list }}
{{- if not $why }}
{{- $listeners = append $listeners (dict "name" "tenant" "host" (printf "*.%s.%s" $tenant $base) "secret" (printf "%s-tls" $name)) }}
{{- $hosts = append $hosts (printf "*.%s.%s" $tenant $base) }}
{{- $i := 0 }}
{{- range $h := (index $p.extraHostnames $tenant | default list) }}
{{- $i = add1 $i }}
{{- $listeners = append $listeners (dict "name" (printf "extra-%d" $i) "host" (toString $h) "secret" (printf "%s-tls-extra-%d" $name $i)) }}
{{- $hosts = append $hosts (toString $h) }}
{{- end }}
{{- end }}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ printf "%s-status" $name | quote }}
  namespace: {{ $ns | quote }}
data:
  {{- if $why }}
  status: refused
  reason: {{ $why | quote }}
  {{- else }}
  status: ok
  tenant: {{ $tenant | quote }}
  gateway: {{ $name | quote }}
  hostnames: {{ join "," $hosts | quote }}
  {{- end }}
{{- if not $why }}
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: {{ $name | quote }}
  namespace: {{ $ns | quote }}
  labels:
    {{ $label }}: {{ $tenant | quote }}
spec:
  gatewayClassName: {{ $p.gatewayClassName }}
  infrastructure:
    labels:
      {{ $label }}: {{ $tenant | quote }}
    parametersRef:
      group: ""
      kind: ConfigMap
      name: {{ printf "%s-infra" $name | quote }}
  listeners:
    {{- range $l := $listeners }}
    - name: {{ $l.name }}
      hostname: {{ $l.host | quote }}
      port: {{ $p.port }}
      protocol: HTTPS
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: {{ $l.secret | quote }}
      allowedRoutes:
        kinds:
          - group: gateway.networking.k8s.io
            kind: HTTPRoute
        namespaces:
          from: Selector
          selector:
            matchLabels:
              {{ $label }}: {{ $tenant | quote }}
    {{- end }}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ printf "%s-infra" $name | quote }}
  namespace: {{ $ns | quote }}
  labels:
    {{ $label }}: {{ $tenant | quote }}
data:
  horizontalPodAutoscaler: |
    spec:
      minReplicas: {{ $p.minReplicas }}
      maxReplicas: {{ $p.maxReplicas }}
      metrics:
        - type: Resource
          resource:
            name: cpu
            target:
              type: Utilization
              averageUtilization: {{ $p.targetCPUUtilizationPercentage }}
  podDisruptionBudget: |
    spec:
      minAvailable: {{ $p.pdbMinAvailable }}
{{- if $p.certManagerIssuerName }}
{{- range $l := $listeners }}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: {{ $l.secret | quote }}
  namespace: {{ $ns | quote }}
  labels:
    {{ $label }}: {{ $tenant | quote }}
spec:
  secretName: {{ $l.secret | quote }}
  dnsNames:
    - {{ $l.host | quote }}
  issuerRef:
    group: cert-manager.io
    kind: {{ $p.certManagerIssuerKind }}
    name: {{ $p.certManagerIssuerName | quote }}
{{- end }}
{{- end }}
{{- end }}
