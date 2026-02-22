# MediaWiki Custom Image

A custom [MediaWiki 1.45](https://www.mediawiki.org/) Docker image with bundled extensions, designed for Kubernetes deployments.

The official `mediawiki:1.45` image ships only the core extensions. To use additional extensions in Kubernetes you need to bake them into the image -- this repo does that.

## Included extensions (basic image)

| Extension | Source |
|-----------|--------|
| [OpenID Connect](https://www.mediawiki.org/wiki/Extension:OpenID_Connect) | OIDC authentication |
| [PluggableAuth](https://www.mediawiki.org/wiki/Extension:PluggableAuth) | Authentication framework (required by OpenID Connect) |
| [Realnames](https://www.mediawiki.org/wiki/Extension:Realnames) | Add realname to all username links |


## Build

```bash
# Build with podman (or docker)
podman build -t mediawiki-custom:latest .

# Tag and push to your registry
podman tag mediawiki-custom:latest your-registry/mediawiki:latest
podman push your-registry/mediawiki:latest
```

To change the base image version:

```bash
podman build --build-arg MEDIAWIKI_BASE_IMAGE=docker.io/mediawiki:1.45 -t mediawiki-custom:latest .
```

## How it works

The Dockerfile:

1. Extends the official `mediawiki:1.45` image
2. Installs `unzip`, `curl`, `python3`, and [Composer](https://getcomposer.org/)
3. Copies everything under `extensions/` into the container
4. Unpacks any `.tar.gz` or `.zip` archives, deriving the correct extension directory name from `extension.json` metadata
5. Runs `composer install --no-dev` for extensions that declare PHP dependencies
6. Sets ownership to `www-data`

## Adding or removing extensions

1. **Download** the extension tarball from [mediawiki.org](https://www.mediawiki.org/wiki/Special:ExtensionDistributor) (choose the branch matching your MediaWiki version, e.g. REL1_45)
2. **Drop** the `.tar.gz` into the `extensions/` directory
3. **Rebuild** the image

To remove an extension, delete its tarball from `extensions/` and rebuild.

You can also place pre-extracted extension directories in `extensions/` instead of archives.

No Dockerfile edits are required when adding or removing extensions.

### Optional: checksum verification

Place a `<filename>.sha256` file alongside any archive and the build will verify it with `sha256sum -c`.

## Runtime configuration

The image contains the extensions but does not enable them. You enable extensions in your `LocalSettings.php`:

```php
wfLoadExtension( 'PluggableAuth' );
wfLoadExtension( 'OpenID Connect' );
wfLoadExtension( 'Realnames' );
// etc.
```

In Kubernetes, mount `LocalSettings.php` via a ConfigMap. See the companion Helm chart for a complete deployment setup.

## Notes

- The container listens on **port 80** (Apache starts as root and drops privileges to `www-data` internally). If your cluster requires non-privileged ports, uncomment the port 8080 section in the Dockerfile.
- Composer runs `install --no-dev` per extension. For extensions with conflicting dependencies you may need to run Composer at the MediaWiki root level instead.
- The `mediawiki-aws-s3` extension is unmaintained third-party code. Pin to a known-good version and test thoroughly.

## License

The Dockerfile and build scripts in this repo are provided as-is. MediaWiki and its extensions are licensed under their respective licenses (typically GPL-2.0-or-later).
