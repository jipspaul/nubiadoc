# Image runtime de l'API Nubia — assemblage COPY-only (aucune compilation ici).
# Le binaire `nubia-api` est cross-compilé en amont sur la machine de build
# (arm64) vers x86_64-unknown-linux-musl (statique) via cargo-zigbuild, puis
# copié dans le contexte de build. Aucune instruction RUN => aucun code amd64
# n'est exécuté au build => pas de QEMU (qui fait segfault rustc sur libkrun).
#
#   podman build --platform linux/amd64 -t nubia-api:latest \
#     -f infra/deploy/api.Dockerfile <ctx-contenant-nubia-api>
#
# Binaire musl 100% statique => tourne tel quel sur Alpine x86_64.
FROM alpine:3.20
COPY nubia-api /usr/local/bin/nubia-api
ENV APP_PORT=3000
EXPOSE 3000
ENTRYPOINT ["/usr/local/bin/nubia-api"]
