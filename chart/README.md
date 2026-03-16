# MediaWiki Helm Chart

A Helm chart for deploying [MediaWiki](https://www.mediawiki.org/) to Kubernetes. Designed for stateless, GitOps-friendly deployments with pluggable storage backends and optional OIDC authentication.

## Install

```bash
helm install my-wiki oci://ghcr.io/mabadiliko/helm-charts/mediawiki --version 0.3.0 \
  -f my-values.yaml
```

Or from a local checkout:

```bash
helm install my-wiki ./charts/mediawiki -f my-values.yaml
```

## What it creates

| Resource | Description |
|----------|-------------|
| Deployment | MediaWiki pod (1 replica by default) |
| Service | ClusterIP on port 80 |
| ConfigMap | `LocalSettings.php` generated from values |
| PVC | Upload storage (when `objectStore.type: pvc`) |
| Ingress | Optional, with TLS via cert-manager |
| Job (Helm hook) | Runs `maintenance/update.php` on install/upgrade |
| ServiceAccount | Standard Helm-managed service account |

## Configuration

### Image

```yaml
image:
  repository: docker.io/mediawiki   # or your custom image with extensions
  tag: "1.45"
  pullPolicy: IfNotPresent
```

The official image works for core MediaWiki. To use additional extensions, build a custom image that bakes them in (see the companion image repo).

### Site settings

```yaml
site:
  name: My Wiki
  server: https://wiki.example.com
  scriptPath: ""
  logo: ""
  secretKey: "<64-char hex string>"    # required -- generate with: openssl rand -hex 32
  upgradeKey: "<16-char hex string>"   # required -- generate with: openssl rand -hex 8
```

### Database

The chart expects an external MySQL/MariaDB database and a pre-created Kubernetes Secret with the password.

```yaml
database:
  host: mariadb.mariadb.svc.cluster.local
  port: 3306
  name: mywiki
  user: wikiuser
  existingSecret: wiki-database    # Secret containing the DB password
  passwordKey: password            # key within the Secret
```

The password is mounted as a file and read via `file_get_contents()` in PHP -- it never appears in the ConfigMap.

### Upload storage

Three backends are supported:

**PVC (default):**
```yaml
objectStore:
  type: pvc
  pvc:
    size: 10Gi
    accessModes: [ReadWriteOnce]
```

**MinIO / S3:**
```yaml
objectStore:
  type: minio
  minio:
    bucket: mywiki
    endpoint: http://minio.minio.svc.cluster.local:9000
    usePathStyle: true
    accessKeySecret: wiki-minio
    accessKeyKey: accessKey
    secretKeySecret: wiki-minio
    secretKeyKey: secretKey
```

**Azure Blob Storage:**
```yaml
objectStore:
  type: azure
  azure:
    container: wiki
    accountName: mystorageaccount
    keySecret: wiki-azure-storage
    keySecretKey: accountKey
```

### OIDC authentication

To mount an OIDC client secret securely:

```yaml
oidc:
  existingSecret: wiki-oidc       # Secret containing the OIDC client secret
  secretKey: clientSecret          # key within the Secret
```

The secret is mounted at `/etc/mediawiki/secrets/oidc/clientSecret`. Reference it in `extraPhp`:

```yaml
localSettings:
  extraPhp: |
    wfLoadExtension( 'PluggableAuth' );
    wfLoadExtension( 'OpenID Connect' );
    $wgPluggableAuth_Config[] = [
        'plugin' => 'OpenIDConnect',
        'data' => [
            'providerURL'  => 'https://id.example.com/realms/myrealm',
            'clientID'     => 'mywiki',
            'clientSecret' => trim( file_get_contents( '/etc/mediawiki/secrets/oidc/clientSecret' ) ),
            'scope'        => [ 'openid', 'email', 'profile' ],
        ],
    ];
```

### Extensions and extra PHP

The `localSettings.extraPhp` field lets you add arbitrary PHP to `LocalSettings.php`. Use it to load extensions, configure skins, or set any MediaWiki variable:

```yaml
localSettings:
  extraPhp: |
    wfLoadSkin( 'Vector' );
    $wgDefaultSkin = "vector";
    wfLoadExtension( 'DynamicPageList3' );
```

### Ingress

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt"
  hosts:
    - host: wiki.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: wiki-tls
      hosts:
        - wiki.example.com
```

### Schema update Job

A Helm hook Job runs `php maintenance/update.php --quick` after every install or upgrade. It uses the same image and volumes as the main deployment. The previous Job is automatically deleted before each run.

```yaml
job:
  update:
    enabled: true
    backoffLimit: 1
```

## Security note

The official MediaWiki Docker image starts Apache as root (PID 1) and drops privileges to `www-data` internally. Do **not** set `runAsNonRoot: true` or `runAsUser` in the security context -- it will prevent Apache from starting.

## All values

See [values.yaml](values.yaml) for the full list of configurable parameters with defaults.
