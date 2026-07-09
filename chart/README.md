# stac-fastapi-pgstac Helm Chart

Deploys [stac-fastapi-pgstac](https://github.com/stac-utils/stac-fastapi-pgstac)
— a FastAPI STAC API — together with (optionally) an in-cluster
[pgstac](https://github.com/stac-utils/pgstac) PostgreSQL database. Designed for
Argo CD, usable with plain `helm install`.

## Architecture

Two tiers, mirroring `compose.yml`:

| Component | Kind | Notes |
| --- | --- | --- |
| **API** | `Deployment` (stateless) | uvicorn on port 8080. Scales horizontally. |
| **Database** | `StatefulSet` + `PVC` + headless `Service` | pgstac image; schema is auto-installed on first init. Set `postgres.enabled=false` to use an external DB instead. |
| Credentials | `Secret` | Chart-created, or bring your own via `auth.existingSecret`. |
| Migrations | `Job` (Helm hook, optional) | `pypgstac migrate`; off by default. |

The API reaches the database via `PG*` env vars. Host/port are wired
automatically to the bundled Service (or `externalDatabase` when
`postgres.enabled=false`); the username/password come from the Secret.

## Values

### Credentials (`auth`)

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `auth.username` | string | `username` | Database username. |
| `auth.password` | string | `""` | Database password. **Required** unless `existingSecret` is set. |
| `auth.database` | string | `postgis` | Database name. |
| `auth.existingSecret` | string | `""` | Use an existing Secret instead of creating one (recommended for GitOps). |
| `auth.secretKeys.usernameKey` | string | `username` | Key in the Secret holding the username. |
| `auth.secretKeys.passwordKey` | string | `password` | Key in the Secret holding the password. |

### API (`api`)

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `api.replicaCount` | int | `2` | API replicas (ignored when autoscaling). |
| `api.image.repository` | string | `ghcr.io/eurac/stac-fastapi-pgstac` | API image; point at your fork's registry. |
| `api.image.tag` | string | `""` | Image tag; defaults to chart `appVersion`. |
| `api.image.pullPolicy` | string | `IfNotPresent` | Pull policy. |
| `api.service.type` | string | `ClusterIP` | Service type. |
| `api.service.port` | int | `8080` | Service port (targets container 8080). |
| `api.probes.livenessPath` | string | `/_mgmt/ping` | Liveness path (no DB hit). |
| `api.probes.readinessPath` | string | `/_mgmt/health` | Readiness path (checks DB). |
| `api.resources` | map | `req 100m/256Mi, lim 1Gi` | Resource requests/limits. |
| `api.podSecurityContext` / `api.securityContext` | map | non-root uid 1000, caps dropped | Hardened defaults. |
| `api.nodeSelector` / `tolerations` / `affinity` | — | `{}` / `[]` / `{}` | Scheduling. |

#### API application settings (`api.settings`)

Mapped to the container's environment variables.

| Key | Env var | Default | Description |
| --- | --- | --- | --- |
| `webConcurrency` | `WEB_CONCURRENCY` | `"10"` | uvicorn worker count. |
| `dbMinConnSize` | `DB_MIN_CONN_SIZE` | `"1"` | asyncpg pool min. |
| `dbMaxConnSize` | `DB_MAX_CONN_SIZE` | `"10"` | asyncpg pool max. |
| `enableTransactionsExtensions` | `ENABLE_TRANSACTIONS_EXTENSIONS` | `false` | Enable the write (Transactions) API. |
| `enableCatalogsExtension` | `ENABLE_CATALOGS_EXTENSION` | `false` | Enable the read-only Catalogs extension. |
| `enabledExtensions` | `ENABLED_EXTENSIONS` | `""` | Comma-separated list; empty = all. |
| `useApiHydrate` | `USE_API_HYDRATE` | `false` | Hydrate items in the API instead of PgSTAC. |
| `corsOrigins` | `CORS_ORIGINS` | `"*"` | CORS allowed origins. |
| `uvicornRootPath` | `UVICORN_ROOT_PATH` | `""` | Root path when served under an ingress subpath (e.g. `/api/v1/pgstac`). Runtime — no rebuild needed. |

Anything else:

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `api.extraEnv` | list | GDAL/VSI tuning vars | Extra env (`{name,value}` or `valueFrom`). |
| `api.envFrom` | list | `[]` | Env from ConfigMaps/Secrets. |

#### API autoscaling (`api.autoscaling`)

| Key | Default | Description |
| --- | --- | --- |
| `enabled` | `false` | Create a HorizontalPodAutoscaler. |
| `minReplicas` / `maxReplicas` | `2` / `6` | Bounds. |
| `targetCPUUtilizationPercentage` | `80` | Target CPU %. |
| `targetMemoryUtilizationPercentage` | _(unset)_ | Set to enable memory-based scaling. |

### Bundled database (`postgres`)

Used when `postgres.enabled=true` (the default).

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `postgres.enabled` | bool | `true` | Deploy the in-cluster pgstac StatefulSet. |
| `postgres.image.repository` | string | `ghcr.io/stac-utils/pgstac` | pgstac image. |
| `postgres.image.tag` | string | `v0.9.8` | Image tag. Keep in sync with `migrations.image.tag`. |
| `postgres.service.port` | int | `5432` | Postgres port. |
| `postgres.args` | list | `["-N","500"]` | Extra `postgres` command args. |
| `postgres.persistence.enabled` | bool | `true` | Use a PVC (off = `emptyDir`, data lost on restart). |
| `postgres.persistence.storageClass` | string | `""` | StorageClass (empty = cluster default). |
| `postgres.persistence.accessModes` | list | `[ReadWriteOnce]` | PVC access modes. |
| `postgres.persistence.size` | string | `10Gi` | Volume size. |
| `postgres.resources` | map | `req 250m/512Mi, lim 2Gi` | Resources. |
| `postgres.podSecurityContext` | map | non-root uid/gid/fsGroup 999 | Postgres runs as uid 999; `fsGroup` makes the PVC writable. |
| `postgres.securityContext` | map | caps dropped | Container hardening. |

> **Single instance.** This is a single-replica StatefulSet with no
> replication or automated backups — fine for dev and small deployments. For
> production HA, point at an operator-managed DB (e.g. CloudNativePG) via
> `externalDatabase` and set `postgres.enabled=false`.

### External database (`externalDatabase`)

Used only when `postgres.enabled=false`. Credentials still come from `auth`.

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `externalDatabase.host` | string | `""` | DB hostname. **Required** when `postgres.enabled=false`. |
| `externalDatabase.port` | int | `5432` | DB port. |

### Migrations (`migrations`)

Optional Helm `post-install`/`post-upgrade` hook Job that runs `pypgstac
migrate` against the database. **Off by default, and not needed for a fresh
install** — the pgstac image installs the schema itself on first init (from its
baked `999_pgstac.sql`). The Job exists for one job: **walking the schema
forward on an existing volume when you bump the pgstac version** (see
[Upgrading pgstac](#upgrading-pgstac)). Also useful against an **external DB**
that doesn't self-install.

> Neither the pgstac image nor the API image ships the `pypgstac` CLI, so the
> Job runs a plain `python` image and `pip install`s pypgstac at runtime — it
> therefore needs **egress to PyPI**. `migrate` is idempotent, so re-runs are
> safe no-ops.

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `migrations.enabled` | bool | `false` | Render + run the migration Job (a PostSync hook under Argo CD). |
| `migrations.image.repository` | string | `python` | Base image the Job pip-installs pypgstac into. |
| `migrations.image.tag` | string | `3.12-slim` | Python base image tag. |
| `migrations.pypgstacVersion` | string | `>=0.9,<0.10` | pypgstac version spec to install. **Keep aligned with `postgres.image.tag`.** |
| `migrations.resources` | map | small | Job resources. |

### Ingress, ServiceAccount, misc

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `ingress.enabled` | bool | `false` | Create an Ingress for the API. |
| `ingress.className` | string | `""` | Ingress class. |
| `ingress.annotations` | map | `{}` | Annotations. |
| `ingress.hosts` | list | `stac-api.example.org` → `/` | Host/path rules. |
| `ingress.tls` | list | `[]` | TLS config. |
| `serviceAccount.create` | bool | `true` | Create a ServiceAccount. |
| `serviceAccount.name` | string | `""` | Name (generated when empty). |
| `imagePullSecrets` | list | `[]` | Private-registry pull secrets. |
| `nameOverride` / `fullnameOverride` | string | `""` | Naming overrides. |

## Example overlay

```yaml
# values.prod.yaml
auth:
  existingSecret: stac-db-credentials   # pre-created; no plaintext in git
  secretKeys:
    usernameKey: username
    passwordKey: password
  database: postgis

api:
  replicaCount: 3
  image:
    repository: ghcr.io/eurac/stac-fastapi-pgstac
    tag: "6.3.1"
  settings:
    enableTransactionsExtensions: true
    corsOrigins: "https://browser.stac.eurac.edu"

postgres:
  enabled: true
  persistence:
    storageClass: fast-ssd
    size: 50Gi
  resources:
    requests: { cpu: 500m, memory: 1Gi }
    limits:   { memory: 4Gi }

ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
  hosts:
    - host: stac.eurac.edu
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: stac-api-tls
      hosts:
        - stac.eurac.edu
```

## Serving under a subpath

The API prefix is a **runtime**
setting. To serve at `/api/v1/pgstac` behind an ingress, set
`api.settings.uvicornRootPath: "/api/v1/pgstac"` and route that path to the
Service — no image rebuild needed.

## Upgrading pgstac

**Fresh install needs nothing here** — the pgstac image installs its schema on
first init of an empty volume. The problem is *later*: bumping
`postgres.image.tag` to a new pgstac version does **not** re-run that init,
because the PVC already has data. The DB comes up still on the old schema while
the new API expects the new one. `pypgstac migrate` is the in-place path that
walks the existing data's schema forward — that's what the (default-off)
migration Job runs.

### How the `migrations.enabled` toggle behaves

- `false` → the Job isn't rendered. Nothing runs.
- `true` → the Job is a **PostSync hook**: it runs at the end of **each Argo CD
  sync** (i.e. when you push a change or Argo CD heals drift) — not
  continuously, and not "once ever". `hook-delete-policy:
  before-hook-creation,hook-succeeded` means each run replaces the previous Job
  and a succeeded one is cleaned up.
- `pypgstac migrate` is **idempotent**, so leaving it `true` just makes it a
  no-op on syncs where the schema is already current.

You can therefore either **leave it on** (simple, but every sync then depends on
PyPI egress + a reachable DB) or **toggle it per upgrade** (recommended below).

### Upgrade playbook (toggle per upgrade)

1. In one commit, bump the DB image and turn the migrator on with a matching
   pypgstac version:

   ```yaml
   postgres:
     image:
       tag: v0.10.x                  # new schema-providing DB image
   migrations:
     enabled: true
     pypgstacVersion: ">=0.10,<0.11" # match the new schema version
   ```

2. Push → Argo CD syncs. The DB StatefulSet rolls to the new image (no re-init;
   the PVC is non-empty), then the PostSync Job `pip install`s the matching
   pypgstac and runs `migrate`, walking the schema `0.9.8 → 0.10.x`.
3. Once healthy, set `migrations.enabled: false` again in a follow-up commit.

### Two caveats for upgrade day

- **Brief 503 window:** the new API pods roll at the same time and stay
  unhealthy (`/_mgmt/health` 503) until the PostSync migrate finishes. Expected;
  it self-recovers.
- **PostgreSQL *major* version jumps are out of scope for `migrate`:** if a
  pgstac image bump also bumps PostgreSQL's major version (e.g. PG17 → PG18),
  the on-disk data format changes and needs `pg_upgrade` / dump-restore.
  `pypgstac migrate` only migrates the **pgstac schema**, not the PG data
  directory — check the release notes before bumping.
