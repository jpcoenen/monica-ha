# Official Docker image for Monica 4, published from github.com/monicahq/docker.
# Pinned to the last 4.x release; `latest` now points at the 5.x beta.
FROM monica:4.1.2-apache

# Bundled database: Monica 4 only supports MySQL/MariaDB.
RUN set -ex; \
    apt-get update; \
    apt-get install -y --no-install-recommends mariadb-server; \
    rm -rf /var/lib/apt/lists/* /var/lib/mysql/*

COPY run.sh /usr/local/bin/ha-run.sh
RUN chmod a+x /usr/local/bin/ha-run.sh

# ha-run.sh reads the add-on options, starts MariaDB and the scheduler, then
# hands over to the image's own entrypoint (migrations, Passport keys) and Apache.
ENTRYPOINT ["/usr/local/bin/ha-run.sh"]
CMD ["apache2-foreground"]
