# Nubia Web Console

Console de test pour les endpoints de l'API Nubia. Usage développement uniquement.

## Quickstart

```bash
# Lance toute la stack en une commande (Postgres + API + web-console)
./scripts/dev-stack.sh
```

Cette commande (depuis la racine du repo) démarre Postgres dans un conteneur Podman,
applique les migrations, lance l'API Rust sur `:38030` et la web-console Astro sur `:38040`.

### Lancer la web-console seule (si l'API tourne déjà)

```bash
cd web-console
./scripts/dev.sh
```

## Lancer

```bash
cd web-console
npm install
npm run dev
```

L'application est accessible sur http://localhost:38040.

## Build statique

```bash
npm run build
```

## Configuration

Ports canon du projet : API sur `:38030`, web-console sur `:38040` (anti-collision intentionnelle).
Par défaut l'API est contactée sur `http://localhost:38030`. Pour changer :

```bash
PUBLIC_API_BASE=http://mon-api:38030 npm run dev
```
