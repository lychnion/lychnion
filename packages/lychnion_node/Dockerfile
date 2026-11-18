# A headless Lychnion node in a container. Build from the repository root:
#
#   docker build -f packages/lychnion_node/Dockerfile -t lychnion-node .
#   docker run -v /srv/lychnion:/data -p 8642:8642 lychnion-node
#   docker run -v /srv/lychnion:/data lychnion-node pull --into /data URL
#
# Only the three pure-Dart packages go into the build; the program runs
# alone on a minimal base (no shell, no Dart SDK).
# Pinned by digest; Dependabot (docker) proposes updates.
FROM dart:3.12.2@sha256:5ac89dbcae4327278b257920e2786df0f22c87adc630017266b67cfcceef8348 AS build
WORKDIR /src
COPY packages/lychnion_format packages/lychnion_format
COPY packages/lychnion_fetch packages/lychnion_fetch
COPY packages/lychnion_node packages/lychnion_node
WORKDIR /src/packages/lychnion_node
RUN dart pub get --enforce-lockfile \
    && dart compile exe bin/lychnion_node.dart -o /lychnion_node \
    && mkdir -p /data

FROM scratch
# The Dart image's /runtime holds the C library and CA certificates the
# compiled program needs (https catalogs).
COPY --from=build /runtime/ /
COPY --from=build /lychnion_node /bin/lychnion_node
# Owned by the user the program runs as, so a named volume is writable.
COPY --from=build --chown=65534:65534 /data /data
VOLUME /data
EXPOSE 8642
USER 65534:65534
ENTRYPOINT ["/bin/lychnion_node"]
CMD ["serve", "/data"]
