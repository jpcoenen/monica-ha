# Official Docker image for Monica 4, published from github.com/monicahq/docker.
# Pinned to the last 4.x release; `latest` now points at the 5.x beta.
FROM monica:4.1.2-apache

COPY run.sh /usr/local/bin/ha-run.sh
RUN chmod a+x /usr/local/bin/ha-run.sh

# ha-run.sh reads the add-on options, then hands over to the image's own
# entrypoint (migrations, Passport keys) and Apache.
ENTRYPOINT ["/usr/local/bin/ha-run.sh"]
CMD ["apache2-foreground"]
