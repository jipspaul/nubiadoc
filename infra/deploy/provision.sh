#!/bin/sh
# Provisionne le LXC Alpine (idempotent). Exécuté en root SUR le LXC (poussé via
# ssh par build-and-deploy.sh). Installe podman et prépare /opt/nubia.
# Réseau = host pour tous les conteneurs (pas besoin de netavark/cni).
set -eu

echo "[provision] apk add podman"
apk update >/dev/null
apk add --no-cache podman fuse-overlayfs ca-certificates

# Stockage : en LXC, overlayfs natif est souvent indisponible -> fuse-overlayfs.
mkdir -p /etc/containers
if [ ! -f /etc/containers/storage.conf ]; then
  cat > /etc/containers/storage.conf <<'EOF'
[storage]
driver = "overlay"
[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
EOF
fi

# cgroups v2 : podman rootful en LXC tourne avec le manager cgroupfs.
mkdir -p /etc/containers
if [ ! -f /etc/containers/containers.conf ]; then
  cat > /etc/containers/containers.conf <<'EOF'
[engine]
cgroup_manager = "cgroupfs"
[containers]
cgroupns = "host"
cgroups = "disabled"
EOF
fi

mkdir -p /opt/nubia/images \
         /opt/nubia/www/patient /opt/nubia/www/praticien /opt/nubia/www/secretary \
         /opt/nubia/migrations /opt/nubia/seed

echo "[provision] OK : $(podman --version)"
