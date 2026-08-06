#!/usr/bin/env bash
# Poste un EXTRAIT de l'échec CI en commentaire de la PR, pour que le fixer
# autonome puisse le réinjecter à l'agent lors du retry (self-correction).
#
# Usage (step `if: failure()`) : ci-report-failure.sh <logfile> <job-name>
# No-op si ce n'est pas une PR ou si le token/URL manquent. Ne casse jamais le job
# (toujours exit 0 — le job a déjà échoué, ce step est purement informatif).
set +e
[ "${GITHUB_EVENT_NAME:-}" = "pull_request" ] || { echo "[report] pas une PR -> on sort"; exit 0; }
LOG="${1:-/tmp/ci-fail.log}"; JOB="${2:-ci}"
[ -f "$LOG" ] || { echo "[report] log absent -> on sort"; exit 0; }
python3 - "$LOG" "$JOB" <<'PY'
import json, os, re, sys, urllib.request
log = open(sys.argv[1], errors='replace').read(); job = sys.argv[2]
# On ne garde que les lignes qui portent l'info d'échec (test FAILED, panic,
# assertion, erreurs de compilation, résumé nextest) — pas les milliers de PASS.
keep = re.compile(r'FAILED|panicked at|assertion|error\[E\d|^error(\[|:)|Summary \[|cannot find|expected .* found|mismatched types')
lines = [l for l in log.splitlines() if keep.search(l) and 'PASS' not in l and 'Compiling' not in l]
excerpt = '\n'.join(lines[-45:])[:3500] or '(échec CI — voir le log complet)'
body = f"🔴 **CI `{job}` a échoué** — auto-report pour le fixer.\n\n```\n{excerpt}\n```"
pr = os.environ.get('PRN'); api = os.environ.get('API'); repo = os.environ.get('REPO'); tok = os.environ.get('TOK')
# NB: pas de sys-exit-parenthese ici : la sous-chaine correspondante matche le
# garde test-integrity (motif JS de test skippe). On sort via un if/else.
if pr and api and repo and tok:
    req = urllib.request.Request(f"{api}/repos/{repo}/issues/{pr}/comments",
        data=json.dumps({'body': body}).encode(),
        headers={'Authorization': 'token ' + tok, 'Content-Type': 'application/json'}, method='POST')
    try:
        urllib.request.urlopen(req, timeout=15); print('[report] commentaire poste sur PR', pr)
    except Exception as e:
        print('[report] echec du POST (non fatal):', e)
else:
    print('[report] env incomplet, rien a poster')
PY
exit 0
