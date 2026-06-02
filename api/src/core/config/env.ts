/**
 * Validation des variables d'environnement au boot (fail-fast).
 * Pas de @nestjs/config pour rester léger : on lit process.env et on échoue
 * tôt si une variable critique manque. Cf. docs/04 §9 et docs/10.
 */
export interface AppEnv {
  nodeEnv: string;
  mode: 'api' | 'worker';
  port: number;
  databaseUrl: string;
  redisUrl: string;
  storageDriver: string;
  mailDriver: string;
  smsDriver: string;
  signDriver: string;
  kmsDriver: string;
  analyticsDriver: string;
}

function required(name: string): string {
  const value = process.env[name];
  if (!value || value.trim() === '') {
    throw new Error(`Variable d'environnement manquante: ${name}`);
  }
  return value;
}

export function loadEnv(): AppEnv {
  const mode = (process.env.MODE ?? 'api') as 'api' | 'worker';
  if (mode !== 'api' && mode !== 'worker') {
    throw new Error(`MODE invalide: ${mode} (attendu: api | worker)`);
  }

  return {
    nodeEnv: process.env.NODE_ENV ?? 'development',
    mode,
    port: Number.parseInt(process.env.PORT ?? '3000', 10),
    databaseUrl: required('DATABASE_URL'),
    redisUrl: required('REDIS_URL'),
    storageDriver: process.env.STORAGE_DRIVER ?? 'minio',
    mailDriver: process.env.MAIL_DRIVER ?? 'mailpit',
    smsDriver: process.env.SMS_DRIVER ?? 'log',
    signDriver: process.env.SIGN_DRIVER ?? 'yousign_sandbox',
    kmsDriver: process.env.KMS_DRIVER ?? 'local',
    analyticsDriver: process.env.ANALYTICS_DRIVER ?? 'noop',
  };
}
