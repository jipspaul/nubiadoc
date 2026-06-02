import { Injectable } from '@nestjs/common';
import { PutObjectInput, StorageDriver } from './storage.driver';

/**
 * Driver POC (MinIO, S3-compatible). À implémenter dans NUB-T4.1
 * avec @aws-sdk/client-s3 pointant sur S3_ENDPOINT.
 * Stub volontaire : la sélection DI fonctionne, l'impl arrive avec la brique Documents.
 */
@Injectable()
export class MinioStorageDriver implements StorageDriver {
  put(_input: PutObjectInput): Promise<void> {
    throw new Error('MinioStorageDriver.put: à implémenter (NUB-T4.1)');
  }

  getSignedUrl(_key: string, _expiresInSeconds: number): Promise<string> {
    throw new Error('MinioStorageDriver.getSignedUrl: à implémenter (NUB-T4.1)');
  }

  delete(_key: string): Promise<void> {
    throw new Error('MinioStorageDriver.delete: à implémenter (NUB-T4.1)');
  }
}
