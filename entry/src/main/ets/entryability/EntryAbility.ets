import { hilog } from '@kit.PerformanceAnalysisKit';
import { Want, UIAbility, common, bundleManager, AbilityConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { KeyboardAvoidMode } from '@ohos.arkui.UIContext';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import Log from '../utils/Log';
import DeviceManager from '../utils/DeviceManager';

const permissions: Array<Permissions> = ['ohos.permission.DISTRIBUTED_DATASYNC'];

export default class EntryAbility extends UIAbility {
  storage: LocalStorage = new LocalStorage();
  want?: Want;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.want = want
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onCreate')
    Log.info('EntryAbility', 'onCreate want parameters: ' + JSON.stringify(want.parameters))
    Log.info('EntryAbility', 'onCreate deviceId: ' + want.deviceId)
    DeviceManager.createDeviceManager()
    
    // 只有当 deviceId 存在时（远程启动），才设置为接收端
    // 本地启动时 deviceId 为 undefined 或空字符串
    if (want.deviceId && want?.parameters?.shared_list) {
      Log.info('EntryAbility', 'Remote start detected, this is receiver')
      AppStorage.setOrCreate('isReceiver', true)
      AppStorage.setOrCreate('isSender', false)
      AppStorage.setOrCreate('isPaired', true)
      
      // 设置发送端的 networkId
      if (want.parameters.senderNetworkId) {
        AppStorage.setOrCreate('RemoteConnectDeviceId', want.parameters.senderNetworkId as string)
        Log.info('EntryAbility', 'Set sender networkId: ' + want.parameters.senderNetworkId)
      }
    } else {
      Log.info('EntryAbility', 'Local start, not setting receiver flag')
    }
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.want = want
    Log.info('EntryAbility', 'onNewWant want parameters: ' + JSON.stringify(want.parameters))
    Log.info('EntryAbility', 'onNewWant deviceId: ' + want.deviceId)

    // 只有当 deviceId 存在时（远程启动），才设置为接收端
    if (want.deviceId && this.want?.parameters?.shared_list) {
      let messageList: string[] = JSON.parse((this.want.parameters.shared_list) as string)
      Log.info('EntryAbility', 'Remote start, received messageList: ' + JSON.stringify(messageList))
      this.storage.setOrCreate('messageList', messageList)
      
      AppStorage.setOrCreate('isReceiver', true)
      AppStorage.setOrCreate('isSender', false)
      AppStorage.setOrCreate('isPaired', true)
      
      if (this.want.parameters.senderNetworkId) {
        AppStorage.setOrCreate('RemoteConnectDeviceId', this.want.parameters.senderNetworkId as string)
        Log.info('EntryAbility', 'Set sender networkId: ' + this.want.parameters.senderNetworkId)
      }
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    Log.info('EntryAbility', 'onWindowStageCreate want parameters: ' + JSON.stringify(this.want?.parameters))
    Log.info('EntryAbility', 'onWindowStageCreate deviceId: ' + this.want?.deviceId)

    // 只有当 deviceId 存在时（远程启动），才设置为接收端
    if (this?.want?.deviceId && this?.want?.parameters?.shared_list) {
      let messageList: string[] = JSON.parse((this.want.parameters.shared_list) as string)
      Log.info('EntryAbility', 'Remote start, setting messageList in storage: ' + JSON.stringify(messageList))
      this.storage.setOrCreate('messageList', messageList)
      
      AppStorage.setOrCreate('isReceiver', true)
      AppStorage.setOrCreate('isSender', false)
      AppStorage.setOrCreate('isPaired', true)
      
      if (this.want.parameters.senderNetworkId) {
        AppStorage.setOrCreate('RemoteConnectDeviceId', this.want.parameters.senderNetworkId as string)
        Log.info('EntryAbility', 'Set sender networkId: ' + this.want.parameters.senderNetworkId)
      }
    }

    checkPermissions(this.context)

    windowStage.loadContent('pages/Index', this.storage, (err) => {
      if (err.code) {
        hilog.error(0x0000, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err) ?? '');
        return;
      }
      
      // 设置键盘避让模式：压缩页面大小
      windowStage.getMainWindowSync().getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
      Log.info('EntryAbility', 'Keyboard avoid mode set to RESIZE');
      
      hilog.info(0x0000, 'testTag', 'Succeeded in loading the content.');
    });
  }
}

async function checkPermissions(context: common.UIAbilityContext) {
  let grantStatus: abilityAccessCtrl.GrantStatus = await checkAccessToken();
  if (grantStatus !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
    // Applying for the distributed data synchronization permission.
    let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    atManager.requestPermissionsFromUser(context, permissions).then((data) => {
      let grantStatus: Array<number> = data.authResults;
      let length: number = grantStatus.length;
      for (let i: number = 0; i < length; i++) {
        if (grantStatus[i] === 0) {
          Log.info('EntryAbility', `checkPermissions request permission ${permissions[i]} success`);
        } else {
          Log.error('EntryAbility',
            `checkPermissions request fail permission=${permissions[i]}, grantStatus=${grantStatus[i]}`);
          return;
        }
      }
    }).catch((err: Error) => {
      Log.error('EntryAbility',
        `checkPermissions request permissions failed, err=${JSON.stringify(err)}`);
    })
  }
}

async function checkAccessToken() {
  let atManager = abilityAccessCtrl.createAtManager();
  let tokenId: number = 0;
  try {
    let bundleInfo: bundleManager.BundleInfo = await bundleManager
      .getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    let appInfo: bundleManager.ApplicationInfo = bundleInfo.appInfo;
    tokenId = appInfo.accessTokenId;
  } catch (err) {
    Log.error('EntryAbility',
      `checkAccessToken Failed to get bundle info for self. err=${JSON.stringify(err)}`);
  }

  let grantStatus: abilityAccessCtrl.GrantStatus = abilityAccessCtrl.GrantStatus.PERMISSION_DENIED;
  try {
    grantStatus = await atManager.checkAccessToken(tokenId, 'ohos.permission.DISTRIBUTED_DATASYNC');
  } catch (err) {
    Log.error('EntryAbility',
      `checkAccessToken Failed to check access token. err=${JSON.stringify(err)}`);
  }

  return grantStatus;
}