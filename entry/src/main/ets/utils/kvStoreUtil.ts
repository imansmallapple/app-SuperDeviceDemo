import distributedKVStore from '@ohos.data.distributedKVStore';
import common from '@ohos.app.ability.common';
import Log from './Log';

class KvStoreModel {
  kvManager?: distributedKVStore.KVManager;
  kvStore?: distributedKVStore.SingleKVStore;
  private syncCallbacks: ((success: boolean) => void)[] = [];  // 使用队列存储多个回调

  /**
   * Create a distributed key-value database.
   *
   * @param context Ability context.
   * @param callback Callback.
   */
  createKvStore(
    context: common.UIAbilityContext,
    callback: (data: distributedKVStore.ChangeNotification) => void
  ): void {
    Log.info('KvStoreModel', '========== createKvStore called ==========')
    
    if (this.kvStore !== undefined) {
      Log.info('KvStoreModel', 'createKvStore KVManager is exist');
      return;
    }

    let config: distributedKVStore.KVManagerConfig = {
      bundleName: context.abilityInfo.bundleName,
      context: context
    };
    
    Log.info('KvStoreModel', 'Creating KVManager with config:', JSON.stringify(config))
    
    try {
      this.kvManager = distributedKVStore.createKVManager(config);
      Log.info('KvStoreModel', '✅ KVManager created successfully')
    } catch (error) {
      Log.error('KvStoreModel',
        `createKvStore createKVManager failed, err=${JSON.stringify(error)}`);
      return;
    }

    let options: distributedKVStore.Options = {
      createIfMissing: true,
      encrypt: false,
      backup: false,
      autoSync: true,
      kvStoreType: distributedKVStore.KVStoreType.SINGLE_VERSION,
      securityLevel: distributedKVStore.SecurityLevel.S1
    };
    
    Log.info('KvStoreModel', 'Getting KVStore with options:', JSON.stringify(options))

    this.kvManager.getKVStore('super_device_kvstore', options).then((store: distributedKVStore.SingleKVStore) => {
      if (store === null) {
        Log.error('KvStoreModel', `createKvStore getKVStore store is null`);
        return;
      }
      Log.info('KvStoreModel', '✅ KVStore obtained successfully')
      
      this.kvStore = store;
      this.kvStore.enableSync(true).then(() => {
        Log.info('KvStoreModel', '✅ enableSync success');
      }).catch((error: Error) => {
        Log.error('KvStoreModel',
          `createKvStore enableSync fail, error=${JSON.stringify(error)}`);
      });
      
      Log.info('KvStoreModel', 'Setting up data change listener...')
      this.setDataChangeListener(callback);
      Log.info('KvStoreModel', '✅ Data change listener registered')
      
      Log.info('KvStoreModel', 'Setting up sync complete listener...')
      this.setSyncCompleteListener();
      Log.info('KvStoreModel', '✅ Sync complete listener registered')
      
      Log.info('KvStoreModel', '========== createKvStore COMPLETE ==========')
    }).catch((error: Error) => {
      Log.error('getKVStore',
        `createKvStore getKVStore failed, error=${JSON.stringify(error)}`);
    })
  }

  /**
   * Add data to the distributed key-value database.
   *
   * @param key Store key name.
   * @param value Store value.
   * @param deviceId Target device ID for sync.
   * @param callback Optional callback when put and sync complete.
   */
  put(key: string, value: string, deviceId?: string, callback?: (success: boolean) => void): void {
    if (this.kvStore === undefined) {
      Log.error('KvStoreModel', 'put failed: kvStore is undefined');
      callback?.(false);
      return;
    }

    this.kvStore.put(key, value).then(() => {
      Log.info('KvStoreModel', `kvStore.put key=${key} finished, value length=${value.length}`);

      if (deviceId) {
        Log.info('KvStoreModel', `Preparing to sync to deviceId: ${deviceId}`);
        
        // 由于 autoSync: true，KVStore 会自动同步
        // 我们手动触发 sync 来加速同步过程
        setTimeout(() => {
          try {
            if (this.kvStore) {
              Log.info('KvStoreModel', `🔄 Calling kvStore.sync([${deviceId}], PUSH_PULL)...`);
              this.kvStore.sync([deviceId], distributedKVStore.SyncMode.PUSH_PULL);
              Log.info('KvStoreModel', `✅ sync to ${deviceId} triggered successfully`);
            } else {
              Log.error('KvStoreModel', `sync failed: kvStore is undefined`);
            }
          } catch (error) {
            Log.error('KvStoreModel', `❌ sync exception: ${JSON.stringify(error)}`);
          }
        }, 50);
        
        // 立即返回成功，不等待 syncComplete
        // 因为 autoSync 会处理同步
        Log.info('KvStoreModel', `Calling callback with success=true`);
        callback?.(true);
      } else {
        Log.info('KvStoreModel', `No deviceId provided, calling callback directly`);
        callback?.(true);
      }

    }).catch((error: Error) => {
      Log.error('KvStoreModel',
        `kvStore.put key=${key} failed, error=${JSON.stringify(error)}`);
      callback?.(false);
    });
  }

  /**
   * Delete a key from the distributed key-value database.
   *
   * @param key Store key name to delete.
   * @param callback Optional callback.
   */
  delete(key: string, callback?: (success: boolean) => void): void {
    if (this.kvStore === undefined) {
      Log.error('KvStoreModel', 'delete failed: kvStore is undefined');
      callback?.(false);
      return;
    }

    this.kvStore.delete(key).then(() => {
      Log.info('KvStoreModel', `kvStore.delete key=${key} finished`);
      callback?.(true);
    }).catch((error: Error) => {
      Log.error('KvStoreModel',
        `kvStore.delete key=${key} failed, error=${JSON.stringify(error)}`);
      callback?.(false);
    });
  }

  /**
   * Manually trigger sync to specified devices.
   *
   * @param deviceIds Target device IDs for sync.
   */
  sync(deviceIds: string[]): void {
    if (this.kvStore === undefined) {
      Log.error('KvStoreModel', 'sync failed: kvStore is undefined');
      return;
    }

    try {
      Log.info('KvStoreModel', `🔄 Manually triggering sync to devices: ${JSON.stringify(deviceIds)}`);
      this.kvStore.sync(deviceIds, distributedKVStore.SyncMode.PUSH_PULL);
      Log.info('KvStoreModel', `✅ sync triggered successfully`);
    } catch (error) {
      Log.error('KvStoreModel', `❌ sync exception: ${JSON.stringify(error)}`);
    }
  }

  /**
   * Set the data change listening function.
   *
   * @param callback Callback.
   */
  setDataChangeListener(callback: (data: distributedKVStore.ChangeNotification) => void): void {
    if (this.kvStore === undefined) {
      Log.error('KvStoreModel', 'setDataChangeListener kvStore is null')
      return
    }

    try {
      this.kvStore.on('dataChange', distributedKVStore.SubscribeType.SUBSCRIBE_TYPE_ALL,
        (data: distributedKVStore.ChangeNotification) => {
          if ((data.updateEntries.length > 0) || (data.insertEntries.length > 0)) {
            callback(data);
          }
          Log.info('kvStore','inside dataChange, data: ',data)
        });
    } catch (error) {
      Log.error('KvStoreModel',
        `setDataChangeListener on('dataChange') failed, err=${JSON.stringify(error)}`);
    }
  }

  /**
   * Set the sync complete listener.
   */
  setSyncCompleteListener(): void {
    if (this.kvStore === undefined) {
      Log.error('KvStoreModel', 'setSyncCompleteListener kvStore is null')
      return
    }

    try {
      this.kvStore.on('syncComplete', (data) => {
        Log.info('KvStoreModel', `syncComplete: ${JSON.stringify(data)}`);
        Log.info('KvStoreModel', `Pending callbacks: ${this.syncCallbacks.length}`);
        
        // 调用所有待处理的回调
        if (this.syncCallbacks.length > 0) {
          Log.info('KvStoreModel', 'Executing all pending sync callbacks');
          const callbacks = [...this.syncCallbacks];  // 复制数组
          this.syncCallbacks = [];  // 清空队列
          callbacks.forEach((callback, index) => {
            Log.info('KvStoreModel', `Executing callback ${index + 1}/${callbacks.length}`);
            callback(true);
          });
        } else {
          Log.info('KvStoreModel', 'No pending callbacks to execute');
        }
      });
    } catch (error) {
      Log.error('KvStoreModel',
        `setSyncCompleteListener on('syncComplete') failed, err=${JSON.stringify(error)}`);
    }
  }

  /**
   * Remove the data change listener.
   */
  removeDataChangeListener(): void {
    if (this.kvStore === undefined) {
      return;
    }

    try {
      this.kvStore.off('dataChange');
    } catch (error) {
      Log.error('KvStoreModel',
        `removeDataChangeListener off('dataChange') failed, err=${JSON.stringify(error)}`);
    }
  }

  /**
   * Manually trigger a PUSH_PULL sync to a specific device.
   * This is the key to solving the sync issue!
   */
  manualPullSync(deviceId: string): void {
    if (this.kvStore === undefined) {
      Log.error('KvStoreModel', 'manualPullSync: kvStore is null')
      return
    }

    if (!deviceId || deviceId.length === 0) {
      Log.warn('KvStoreModel', 'manualPullSync: deviceId is empty, skipping')
      return
    }

    try {
      // 使用 PUSH_PULL 模式与指定设备同步
      this.kvStore.sync([deviceId], distributedKVStore.SyncMode.PUSH_PULL)
      Log.info('KvStoreModel', `✅ Manual PUSH_PULL sync triggered to ${deviceId}`)
    } catch (error) {
      Log.error('KvStoreModel', `manualPullSync failed: ${JSON.stringify(error)}`)
    }
  }
}

export default KvStoreModel