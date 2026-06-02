import { Global, Module } from '@nestjs/common';
import { loadEnv } from '../../config/env';
import { MinioStorageDriver } from './minio.driver';
import { ScalewayStorageDriver } from './scaleway.driver';
import { STORAGE_DRIVER, StorageDriver } from './storage.driver';

/**
 * Sélection du driver de stockage par variable d'env STORAGE_DRIVER.
 * C'est le patron à répliquer pour les autres dépendances externes
 * (Mail, SMS, Signature, KMS, Push, Analytics) — cf. docs/10 §1.
 */
@Global()
@Module({
  providers: [
    MinioStorageDriver,
    ScalewayStorageDriver,
    {
      provide: STORAGE_DRIVER,
      inject: [MinioStorageDriver, ScalewayStorageDriver],
      useFactory: (minio: MinioStorageDriver, scaleway: ScalewayStorageDriver): StorageDriver => {
        const driver = loadEnv().storageDriver;
        switch (driver) {
          case 'minio':
            return minio;
          case 'scaleway':
            return scaleway;
          default:
            throw new Error(`STORAGE_DRIVER inconnu: ${driver}`);
        }
      },
    },
  ],
  exports: [STORAGE_DRIVER],
})
export class StorageModule {}
