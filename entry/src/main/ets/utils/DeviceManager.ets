import { distributedDeviceManager } from '@kit.DistributedServiceKit'
import Log from './Log'
import { BusinessError } from '@kit.BasicServicesKit';
import { Want, common } from '@kit.AbilityKit';

interface PendingStartAbility {
  context: common.UIAbilityContext;
  device: distributedDeviceManager.DeviceBasicInfo;
  shared_list: string[];
}

class DeviceManager {
  private static instance: DeviceManager | undefined = undefined
  private myDeviceManager?: distributedDeviceManager.DeviceManager
  private deviceList: distributedDeviceManager.DeviceBasicInfo[] = []
  private availableDeviceList: distributedDeviceManager.DeviceBasicInfo[] = []
  private discoverList: distributedDeviceManager.DeviceBasicInfo[] = []
  private isDiscovering: boolean = false
  private boundDeviceList: string[] = []
  private isPaired: boolean = false
  private pendingStartAbility?: PendingStartAbility
  private bindTimeoutId?: number

  static getInstance(): DeviceManager {
    if (!DeviceManager.instance) {
      DeviceManager.instance = new DeviceManager()
    }
    return DeviceManager.instance;
  }

  async createDeviceManager() {
    if (this.myDeviceManager !== undefined) {
      Log.info('DeviceManager', 'DeviceManager already exists');
      return;
    }

    try {
      this.myDeviceManager = distributedDeviceManager.createDeviceManager("com.example.superdevicedemo");

      this.registerDeviceStateListener();
      this.getLocalDeviceInfo();
      this.getAvailableDeviceList();
      this.initDeviceList();
      Log.info('DeviceManager', 'device list', this.deviceList)
    } catch (error) {
      Log.error('DeviceManager', `createDeviceManager failed: ${JSON.stringify(error)}`);
    }
  }

  registerDeviceStateListener(): void {
    if (!this.myDeviceManager) {
      Log.error('DeviceManager', 'registerDeviceStateListener deviceManager has not initialized')
      return;
    }
    try {
      this.myDeviceManager.on('deviceStateChange', (data) => {
        if (!data) {
          return;
        }
        switch (data.action) {
          case distributedDeviceManager.DeviceStateChange.AVAILABLE:
            const remoteDevice = data.device
            this.isPaired = true
            AppStorage.setOrCreate('RemoteConnectDeviceId', remoteDevice.networkId)
            AppStorage.setOrCreate('isPaired', this.isPaired)
            Log.info('deviceStateChange', 'Paired by device: ' + remoteDevice.deviceName + ', networkId: ' + remoteDevice.networkId)
            this.deviceOnline(data.device);
            
            // 清除超时定时器
            if (this.bindTimeoutId) {
              clearTimeout(this.bindTimeoutId)
              this.bindTimeoutId = undefined
            }
            
            // 如果有待启动的 Ability，现在启动它
            // 关键修复：使用 remoteDevice（包含完整 networkId），而不是保存的 device
            if (this.pendingStartAbility && this.pendingStartAbility.device.deviceId === remoteDevice.deviceId) {
              Log.info('deviceStateChange', 'Device paired, starting ability now')
              Log.info('deviceStateChange', `Using networkId: ${remoteDevice.networkId}`)
              this.startAbility(
                this.pendingStartAbility.context,
                remoteDevice,  // 使用 remoteDevice 而不是 pendingStartAbility.device
                this.pendingStartAbility.shared_list
              )
              this.pendingStartAbility = undefined
            }
            break;
          case distributedDeviceManager.DeviceStateChange.UNAVAILABLE:
            this.isPaired = false
            AppStorage.setOrCreate('RemoteConnectDeviceId', '')
            AppStorage.setOrCreate('isPaired', this.isPaired)
            this.deviceOffline(data.device);
            // 注意：不在这里清除 pendingStartAbility
            // 因为 UNAVAILABLE 可能是配对过程中的中间状态
            Log.info('deviceStateChange', 'Device unavailable: ' + data.device.deviceName)
            break;
        }
      });
    } catch (error) {
      Log.error('DeviceManager',
        `registerDeviceStateListener on('deviceStateChange') failed, error=${JSON.stringify(error)}`)
    }
  }

  getLocalDeviceInfo(): void {
    if (!this.myDeviceManager) {
      return;
    }

    try {
      Log.info('DeviceManager',
        `Local Device ID: ${this.myDeviceManager.getLocalDeviceId()}, Name: ${this.myDeviceManager.getLocalDeviceName()}, Type: ${this.myDeviceManager.getLocalDeviceType()
          .toString()}, Network ID:${this.myDeviceManager.getLocalDeviceNetworkId()}`);
    } catch (err) {
      Log.error('DeviceManager', `getLocalDeviceInfo failed: ${JSON.stringify(err)}`);
    }
  }

  getAvailableDeviceList(): void {
    if (!this.myDeviceManager) {
      return;
    }

    try {
      this.availableDeviceList = this.myDeviceManager.getAvailableDeviceListSync();
    } catch (err) {
      Log.error('DeviceManager', `getAvailableDeviceListSync failed: ${JSON.stringify(err)}`);
    }
  }

  initDeviceList(): void {
    this.deviceList = [];
    this.availableDeviceList.forEach(device => this.addToDeviceList(device));
    AppStorage.setOrCreate('deviceList', this.deviceList);
  }

  deviceOnline(device: distributedDeviceManager.DeviceBasicInfo): void {
    this.availableDeviceList.push(device);
    this.addToDeviceList(device);
  }

  deviceOffline(device: distributedDeviceManager.DeviceBasicInfo): void {
    this.availableDeviceList = this.availableDeviceList.filter(item => item.networkId !== device.networkId);
    this.deleteFromDeviceList(device);
  }

  addToDeviceList(device: distributedDeviceManager.DeviceBasicInfo): void {
    const index = this.deviceList.findIndex(d => d.deviceId === device.deviceId);
    if (index >= 0) {
      this.deviceList[index] = device;
    } else {
      this.deviceList.push(device);
    }
    AppStorage.setOrCreate('deviceList', this.deviceList);
  }

  deleteFromDeviceList(device: distributedDeviceManager.DeviceBasicInfo): void {
    this.deviceList = this.deviceList.filter(d => d.deviceId !== device.deviceId);
    AppStorage.setOrCreate('deviceList', this.deviceList);
  }

  startDeviceDiscovery(): void {
    this.discoverList = [];
    this.initDeviceList();
    if (this.myDeviceManager === undefined) {
      Log.error('DeviceManager', 'startDeviceDiscovery deviceManager has not initialized');
      return;
    }

    try {
      this.stopDeviceDiscovery()

      this.myDeviceManager.startDiscovering(
        {
          discoverTargetType: 1
        }
      );
      this.isDiscovering = true;
      this.myDeviceManager.on('discoverSuccess', (data) => {
        if (data) {
          Log.info('DeviceManager', `Device found: ${JSON.stringify(data.device.deviceName)}`);
          this.deviceFound(data.device);
        } else {
          Log.warn('DeviceManager', 'Discovery success, but no device in data');
        }
      });

      this.myDeviceManager.on('discoverFailure', (data) => {
        Log.error('DeviceManager', `Device discovery failed: ${JSON.stringify(data)}`);
      });

    } catch (err) {
      Log.error('DeviceManager', `startDeviceDiscovery failed: ${JSON.stringify(err)}`);
    }
  }

  authenticateDevice(
    context: common.UIAbilityContext,
    device: distributedDeviceManager.DeviceBasicInfo,
    shared_list: string[]
  ): void {
    // 设置为发送端（无论是否需要配对）
    AppStorage.setOrCreate('isSender', true)
    AppStorage.setOrCreate('isReceiver', false)
    
    // 检查设备是否已经可用（系统层面已配对）
    const isAvailable = this.availableDeviceList.some(
      (item: distributedDeviceManager.DeviceBasicInfo) => item.deviceId === device.deviceId
    )
    
    if (isAvailable) {
      Log.info('DeviceManager', 'Device already available, start ability directly')
      // 设置连接状态
      this.isPaired = true
      AppStorage.setOrCreate('RemoteConnectDeviceId', device.networkId)
      AppStorage.setOrCreate('isPaired', this.isPaired)
      Log.info('DeviceManager', 'Set remote device networkId: ' + device.networkId)
      
      this.startAbility(context, device, shared_list);
      return;
    }

    if (this.myDeviceManager === undefined) {
      Log.error('RemoteDeviceModel', 'authenticateDevice deviceManager has not initialized');
      return;
    }

    Log.info('DeviceManager', 'Device not available, start binding process with PIN')
    let bindParam: Record<string, string | number> = {
      'bindType': 1,
      'targetPkgName': context.abilityInfo.bundleName,
      'appName': context.abilityInfo.labelId.toString(),
      'appOperation': 'SuperDevice data sync',
      'customDescription': 'Allow data synchronization'
    }

    try {
      // 保存待启动的信息，等待 AVAILABLE 事件
      const pendingInfo: PendingStartAbility = { 
        context: context, 
        device: device, 
        shared_list: shared_list 
      }
      this.pendingStartAbility = pendingInfo
      
      // 设置 30 秒超时，如果没有收到 AVAILABLE 事件，则清除 pendingStartAbility
      this.bindTimeoutId = setTimeout(() => {
        if (this.pendingStartAbility && this.pendingStartAbility.device.deviceId === device.deviceId) {
          Log.error('DeviceManager', 'Bind timeout, clearing pending start ability')
          this.pendingStartAbility = undefined
        }
        this.bindTimeoutId = undefined
      }, 30000)
      
      this.myDeviceManager.bindTarget(device.deviceId, bindParam, (err: BusinessError) => {
        if (err && err.code !== 0) {
          Log.error('Device Manager',
            `authenticateDevice error code=${err.code}, msg=${JSON.stringify(err.message)}`)
          // 注意：即使回调报错，也不清除 pendingStartAbility
          // 因为 deviceStateChange AVAILABLE 事件才是最终判断标准
          // 错误码 7 等可能是中间状态，不影响最终配对结果
          return;
        }
        Log.info('DeviceManager', 'bindDevice callback success, waiting for AVAILABLE event')
        this.boundDeviceList.push(device.deviceId);
        AppStorage.setOrCreate('boundDeviceList', this.boundDeviceList);
      })
    } catch (error) {
      Log.error('Device Manager',
        `authenticateDevice failed error=${JSON.stringify(error)}`);
    }
  }

  unbindDevice(deviceId: string): void {
    if (this.myDeviceManager === undefined) {
      Log.error('RemoteDeviceModel', 'unbindDevice deviceManager has not initialized');
      return;
    }
    setTimeout(() => {
      try {
        this.myDeviceManager?.unbindTarget(deviceId)
        Log.info('RemoteDeviceModel', `Device unbind: ${deviceId}`)
      } catch (e) {
        Log.error('RemoteDeviceModel', `Failed to unbind: ${JSON.stringify(e)}`)
      }
    }, 0)
  }

  getBoundDeviceList(): string[] {
    return this.boundDeviceList;
  }

  startAbility(context: common.UIAbilityContext, device: distributedDeviceManager.DeviceBasicInfo,
    shared_list: string[]): void {
    // 获取本地设备的 networkId
    const localNetworkId = this.myDeviceManager?.getLocalDeviceNetworkId() || ''
    
    // 设置远程设备连接状态
    this.isPaired = true
    AppStorage.setOrCreate('RemoteConnectDeviceId', device.networkId)
    AppStorage.setOrCreate('isPaired', this.isPaired)
    Log.info('DeviceManager', '✅ Set RemoteConnectDeviceId: ' + device.networkId)
    
    let wantValue: Want = {
      bundleName: context.abilityInfo.bundleName,
      abilityName: 'EntryAbility',
      deviceId: device.networkId,
      parameters: {
        shared_list: JSON.stringify(shared_list),
        senderNetworkId: localNetworkId  // 传递发送端的 networkId
      }
    };

    context.startAbility(wantValue).then(() => {
      Log.info('RemoteDeviceModel', `startAbility finished wantValue=${JSON.stringify(wantValue)}`);
    }).catch((error: Error) => {
      Log.error('RemoteDeviceModel', `startAbility failed, error=${JSON.stringify(error)}`);
    })
  }

  stopDeviceDiscovery(): void {
    if (!this.myDeviceManager) {
      Log.error('DeviceManager', 'stopDeviceDiscovery failed: manager not initialized');
      return;
    }

    if (this.isDiscovering) {
      try {
        this.myDeviceManager.stopDiscovering()
        this.isDiscovering = false;
        Log.info('DeviceManager', 'Device discovery stopped');
      } catch (err) {
        Log.error('DeviceManager', `stopDeviceDiscovery failed: ${JSON.stringify(err)}`);
      }
    } else {
      Log.info('DeviceManager', 'Device discovery not active, no need to stop');
    }
  }

  clearDeviceList(): void {
    if (this.deviceList.length !== 0) {
      this.deviceList = []
    }
  }

  deviceFound(device: distributedDeviceManager.DeviceBasicInfo): void {
    if (!this.discoverList.find(d => d.deviceId === device.deviceId)) {
      this.discoverList.push(device);
      this.addToDeviceList(device);
    }
  }
}

export default DeviceManager.getInstance()