# syntax=docker/dockerfile:1.7
# Simplified custom MediaWiki image that bakes in required extensions.

ARG MEDIAWIKI_BASE_IMAGE="docker.io/mediawiki:1.45"
FROM ${MEDIAWIKI_BASE_IMAGE}

ENV MW_HOME=/var/www/html \
    COMPOSER_ALLOW_SUPERUSER=1

# USER root

# Tools needed to download Composer.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends unzip curl python3; \
    rm -rf /var/lib/apt/lists/*; \
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" \
    && php composer-setup.php --install-dir=/usr/local/bin --filename=composer \
    && rm composer-setup.php

# Copy any extensions provided in the build context under ./extensions.
# Each subfolder of ./extensions will be copied into MediaWiki's extensions directory.
COPY extensions/ /tmp/extensions/

# Helper script to derive extension name from metadata.
RUN cat <<'PY' > /tmp/ext_name.py
import json, os, sys
def ext_name(path: str) -> str:
    extjson = os.path.join(path, "extension.json")
    compjson = os.path.join(path, "composer.json")
    if os.path.isfile(extjson):
        try:
            with open(extjson) as f:
                data = json.load(f)
            if isinstance(data.get("name"), str):
                return data["name"]
        except Exception:
            pass
    if os.path.isfile(compjson):
        try:
            with open(compjson) as f:
                data = json.load(f)
            extra = data.get("extra") or {}
            inst = extra.get("installer-name")
            if isinstance(inst, str):
                return inst
        except Exception:
            pass
    return ""
if __name__ == "__main__":
    print(ext_name(sys.argv[1]))
PY

# Move extensions into place, supporting pre-unpacked folders and archives.
# For archives, the target directory name is derived from extension.json "name" if present,
# otherwise composer.json extra.installer-name, otherwise from the top-level folder, otherwise from the filename base.
RUN set -eux; \
    mkdir -p "${MW_HOME}/extensions"; \
    for entry in /tmp/extensions/*; do \
        [ -e "${entry}" ] || continue; \
        extname=""; \
        if [ -f "${entry}.sha256" ]; then \
            sha256sum -c "${entry}.sha256"; \
        fi; \
        case "${entry}" in \
            *.tar.gz|*.tgz) \
                workdir="$(mktemp -d)"; \
                tar -xzf "${entry}" -C "${workdir}"; \
                srcdir="$(find "${workdir}" -mindepth 1 -maxdepth 1 -type d | head -n1)"; \
                extname="$(python3 /tmp/ext_name.py "${srcdir}")"; \
                [ -n "${extname}" ] || extname="$(basename "${srcdir}")"; \
                dest="${MW_HOME}/extensions/${extname}"; \
                rm -rf "${dest}"; \
                mv "${srcdir}" "${dest}"; \
                rm -rf "${workdir}"; \
                ;; \
            *.zip) \
                workdir="$(mktemp -d)"; \
                unzip -q "${entry}" -d "${workdir}"; \
                srcdir="$(find "${workdir}" -mindepth 1 -maxdepth 1 -type d | head -n1)"; \
                extname="$(python3 /tmp/ext_name.py "${srcdir}")"; \
                [ -n "${extname}" ] || extname="$(basename "${srcdir}")"; \
                dest="${MW_HOME}/extensions/${extname}"; \
                rm -rf "${dest}"; \
                mv "${srcdir}" "${dest}"; \
                rm -rf "${workdir}"; \
                ;; \
            *) \
                if [ -d "${entry}" ]; then \
                    extname="$(python3 /tmp/ext_name.py "${entry}")"; \
                    [ -n "${extname}" ] || extname="$(basename "${entry}")"; \
                    dest="${MW_HOME}/extensions/${extname}"; \
                    rm -rf "${dest}"; \
                    cp -r "${entry}" "${dest}"; \
                fi; \
                ;; \
        esac; \
    done; \
    find "${MW_HOME}/extensions" -maxdepth 2 -type d -name ".git" -prune -exec rm -rf '{}' +

# Install PHP dependencies for any extension that declares a composer.json.
RUN set -eux; \
    composer config --global --json audit.ignore '["PKSA-y2cr-5h3j-g3ys", "PKSA-2kqm-ps5x-s4f5"]'; \
    for ext in "${MW_HOME}/extensions"/*; do \
        if [ -d "${ext}" ] && [ -f "${ext}/composer.json" ]; then \
            cd "${ext}" && composer install --no-dev --optimize-autoloader; \
        fi; \
    done; \
    chown -R www-data:www-data "${MW_HOME}/extensions"; \
    rm -rf /tmp/extensions /tmp/ext_name.py

# Create empty locale stubs for any i18n/api directory that ships only 'en.json'.
# Prevents LocalisationCache from emitting filemtime() warnings on every request when
# $wgLanguageCode is set to a language without translations for that sub-module (e.g. 'sv').
ARG MW_EXTRA_LOCALES="sv"
RUN set -eux; \
    for lang in ${MW_EXTRA_LOCALES}; do \
        find "${MW_HOME}/extensions" "${MW_HOME}/skins" \
             -type d -name "api" -path "*/i18n/api" \
          | while read -r dir; do \
                [ -f "${dir}/${lang}.json" ] || \
                    printf '{"@metadata":{"authors":[]}}\n' > "${dir}/${lang}.json"; \
            done; \
    done

# Enable APCu for PHP CLI so that maintenance scripts (e.g. update.php) can use
# the same in-process cache as the web workers.  By default apc.enable_cli = 0.
RUN echo 'apc.enable_cli = 1' >> /usr/local/etc/php/conf.d/docker-php-ext-apcu.ini

# Switch Apache to listen on 8080 to avoid privileged port binding restrictions in locked-down runtimes.
# RUN set -eux; \
#     sed -i 's/^Listen 80$/Listen 8080/' /etc/apache2/ports.conf; \
#     sed -i 's/:80>/:8080>/' /etc/apache2/sites-available/000-default.conf

# The official entrypoint/cmd from the base image runs Apache+PHP-FPM as root (dropping to www-data internally).
# USER root
# USER www-data
