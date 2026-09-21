{{- define "homemaps.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "homemaps.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else if contains (include "homemaps.name" .) .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name (include "homemaps.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/* Naam van één onderdeel: (dict "root" . "naam" "valhalla") */}}
{{- define "homemaps.onderdeel" -}}
{{- printf "%s-%s" (include "homemaps.fullname" .root) .naam | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "homemaps.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version | replace "+" "_" }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
app.kubernetes.io/version: {{ .root.Chart.AppVersion | quote }}
{{ include "homemaps.selector" . }}
{{- with .root.Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "homemaps.selector" -}}
app.kubernetes.io/name: {{ include "homemaps.name" .root }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .naam }}
{{- end }}

{{/* Pod-niveau: non-root met een vaste gebruiker. (dict "root" . "uid" 9011) overschrijft die. */}}
{{- define "homemaps.podSecurity" -}}
{{- $uid := default .root.Values.securityContext.runAsUser .uid }}
runAsUser: {{ $uid }}
runAsGroup: {{ default .root.Values.securityContext.runAsGroup .uid }}
runAsNonRoot: true
fsGroup: {{ default .root.Values.securityContext.fsGroup .uid }}
fsGroupChangePolicy: OnRootMismatch
seccompProfile:
  type: RuntimeDefault
{{- end }}

{{- define "homemaps.containerSecurity" -}}
allowPrivilegeEscalation: false
capabilities:
  drop: ["ALL"]
{{- end }}

{{- define "homemaps.pvc" -}}
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ include "homemaps.onderdeel" . }}
  labels: {{- include "homemaps.labels" . | nindent 4 }}
  annotations:
    # Een `helm uninstall` mag geen uren bouwwerk weggooien.
    helm.sh/resource-policy: keep
spec:
  accessModes: [{{ .root.Values.storage.accessMode }}]
  {{- with .root.Values.storage.storageClassName }}
  storageClassName: {{ . }}
  {{- end }}
  resources:
    requests:
      storage: {{ .size }}
{{- end }}

{{/* De hostnamen waaronder de installatie bereikbaar is, voor tileserver-gl. */}}
{{- define "homemaps.allowedHosts" -}}
{{- $hosts := concat (.Values.httpRoute.enabled | ternary .Values.httpRoute.hostnames list) (.Values.ingress.enabled | ternary .Values.ingress.hosts list) .Values.tiles.extraAllowedHosts }}
{{- if $hosts }}{{ join "," ($hosts | uniq) }}{{ else }}*{{ end }}
{{- end }}

{{- define "homemaps.image" -}}
{{- printf "%s:%s" .image.repository (default .root.Chart.AppVersion .image.tag) }}
{{- end }}
