{{/*
Expand the name of the chart.
*/}}
{{- define "stac-fastapi-pgstac.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "stac-fastapi-pgstac.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Chart name and version for the chart label.
*/}}
{{- define "stac-fastapi-pgstac.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "stac-fastapi-pgstac.labels" -}}
helm.sh/chart: {{ include "stac-fastapi-pgstac.chart" . }}
app.kubernetes.io/name: {{ include "stac-fastapi-pgstac.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
API selector labels
*/}}
{{- define "stac-fastapi-pgstac.api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "stac-fastapi-pgstac.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: api
{{- end }}

{{/*
Postgres selector labels
*/}}
{{- define "stac-fastapi-pgstac.postgres.selectorLabels" -}}
app.kubernetes.io/name: {{ include "stac-fastapi-pgstac.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: postgres
{{- end }}

{{/*
Name of the service account to use.
*/}}
{{- define "stac-fastapi-pgstac.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "stac-fastapi-pgstac.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Postgres Service name (bundled database).
*/}}
{{- define "stac-fastapi-pgstac.postgres.fullname" -}}
{{- printf "%s-postgres" (include "stac-fastapi-pgstac.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Name of the Secret holding the database credentials.
*/}}
{{- define "stac-fastapi-pgstac.secretName" -}}
{{- if .Values.auth.existingSecret }}
{{- .Values.auth.existingSecret }}
{{- else }}
{{- printf "%s-db" (include "stac-fastapi-pgstac.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Database host: the bundled Postgres Service, or the external host.
*/}}
{{- define "stac-fastapi-pgstac.dbHost" -}}
{{- if .Values.postgres.enabled }}
{{- include "stac-fastapi-pgstac.postgres.fullname" . }}
{{- else }}
{{- required "externalDatabase.host is required when postgres.enabled is false" .Values.externalDatabase.host }}
{{- end }}
{{- end }}

{{/*
Database port.
*/}}
{{- define "stac-fastapi-pgstac.dbPort" -}}
{{- if .Values.postgres.enabled }}
{{- .Values.postgres.service.port }}
{{- else }}
{{- .Values.externalDatabase.port }}
{{- end }}
{{- end }}

{{/*
Common database environment variables (PG* connection settings) for the API
and the migration job. Credentials come from the Secret.
*/}}
{{- define "stac-fastapi-pgstac.dbEnv" -}}
- name: PGHOST
  value: {{ include "stac-fastapi-pgstac.dbHost" . | quote }}
- name: PGPORT
  value: {{ include "stac-fastapi-pgstac.dbPort" . | quote }}
- name: PGDATABASE
  value: {{ .Values.auth.database | quote }}
- name: PGUSER
  valueFrom:
    secretKeyRef:
      name: {{ include "stac-fastapi-pgstac.secretName" . }}
      key: {{ .Values.auth.secretKeys.usernameKey }}
- name: PGPASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "stac-fastapi-pgstac.secretName" . }}
      key: {{ .Values.auth.secretKeys.passwordKey }}
{{- end }}
