{{/*
Checks the schema can't express, and the sync block every Template carries.
*/}}
{{- define "mto-extension-api-gateway-bootstrap.validate" -}}
{{- if not .Values.gateway.baseDomain -}}
{{- fail "gateway.baseDomain is required: each tenant's listener serves *.<tenant>.<baseDomain>" -}}
{{- end -}}
{{- if lt (int .Values.gateway.autoscaling.maxReplicas) (int .Values.gateway.autoscaling.minReplicas) -}}
{{- fail (printf "gateway.autoscaling.maxReplicas (%v) is below minReplicas (%v)" .Values.gateway.autoscaling.maxReplicas .Values.gateway.autoscaling.minReplicas) -}}
{{- end -}}
{{- if ge (int .Values.gateway.podDisruptionBudget.minAvailable) (int .Values.gateway.autoscaling.minReplicas) -}}
{{- fail "gateway.podDisruptionBudget.minAvailable must be below gateway.autoscaling.minReplicas, or a node drain can never evict a gateway pod" -}}
{{- end -}}
{{- if and (eq .Values.tenants.mode "list") (not .Values.tenants.list) -}}
{{- fail "tenants.mode is list but tenants.list is empty: no tenant would get a gateway" -}}
{{- end -}}
{{- end -}}

{{- define "mto-extension-api-gateway-bootstrap.templateSync" -}}
{{- $mode := .Values.templateSync.mode | toString -}}
{{- if not (has $mode (list "revert" "strict")) -}}
{{- fail (printf "templateSync.mode must be revert or strict, got %q: off freezes every tenant after its first apply" $mode) -}}
{{- end -}}
sync:
  mode: {{ $mode }}
{{- end -}}
