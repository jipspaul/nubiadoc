/**
 * Driver de stockage objet — interface commune POC/prod (docs/10 §1).
 * POC: MinIO (S3-compatible) · Prod: Scaleway Object Storage.
 * Le code métier dépend de StorageDriver, jamais d'un SDK concret.
 */
export interface PutObjectInput {
  key: string;
  body: Buffer;
  contentType: string;
}

export interface StorageDriver {
  put(input: PutObjectInput): Promise<void>;
  /** URL signée temporaire (expiration en secondes). */
  getSignedUrl(key: string, expiresInSeconds: number): Promise<string>;
  delete(key: string): Promise<void>;
}

export const STORAGE_DRIVER = Symbol('STORAGE_DRIVER');
