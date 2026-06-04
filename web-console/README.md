# Nubia Web Console

Console de test pour les endpoints de l'API Nubia. Usage développement uniquement.

## Quickstart

```bash
cd web-console
./scripts/dev.sh
```

Le script installe les dépendances si besoin, vérifie que l'API Nubia tourne sur `:3000`, et lance le serveur sur http://localhost:4321.

Depuis la racine du repo :

```bash
./scripts/dev-web.sh
```

## Lancer

```bash
cd web-console
npm install
npm run dev
```

L'application est accessible sur http://localhost:4321.

## Build statique

```bash
npm run build
```

## Configuration

Par défaut l'API est contactée sur `http://localhost:3000`. Pour changer :

```bash
PUBLIC_API_BASE=http://mon-api:3000 npm run dev
```
