import { Injectable } from '@nestjs/common';
import { PutObjectInput, StorageDriver } from './storage.driver';

/**
 * Driver PROD (Scaleway Object Storage, S3-compatible). À implémenter dans NUB-T4.1.
 * Même interface que MinIO -> bascule POC->prod par configuration seule (docs/10 §8).
 */
@Injectable()
export class ScalewayStorageDriver implements StorageDriver {
  put(_input: PutObjectInput): Promise<void> {
    throw new Error('ScalewayStorageDriver.put: à implémenter (NUB-T4.1)');
  }

  getSignedUrl(_key: string, _expiresInSeconds: number): Promise<string> {
    throw new Error('ScalewayStorageDriver.getSignedUrl: à implémenter (NUB-T4.1)');
  }

  delete(_key: string): Promise<void> {
    throw new Error('ScalewayStorageDriver.delete: à implémenter (NUB-T4.1)');
  }
}
