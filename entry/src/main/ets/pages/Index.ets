import DeviceManager from '../utils/DeviceManager'
import DeviceListDialog from '../view/CustomDialogComponent';
import { distributedDeviceManager } from '@kit.DistributedServiceKit';
import Log from '../utils/Log';
import { common } from '@kit.AbilityKit';
import KvStoreModel from '../utils/kvStoreUtil';
// import { distributedKVStore } from '@kit.ArkData';
import distributedKVStore from '@ohos.data.distributedKVStore';

@Entry
@Component
struct Index {
  @StorageLink('deviceList') deviceList: distributedDeviceManager.DeviceBasicInfo[] = []
  @StorageLink('RemoteConnectDeviceId') remoteConnectDeviceId: string = ''
  @StorageLink('isSender') isSender: boolean = false
  @StorageLink('isReceiver') isReceiver: boolean = false
  @StorageLink('isPaired') isPaired: boolean = false
  @LocalStorageProp('messageList') messageList: string[] = [];
  @State connectedDeviceId: string = ''
  @State textInput: string = ''
  @State receivedText: string[] = []
  @State isLoading: boolean = false
  @State isAbleUnbind: boolean = false
  private context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private kvStoreModel: KvStoreModel = new KvStoreModel();
  @State receivedList: string[] = []
  storage: LocalStorage | undefined = this.getUIContext().getSharedLocalStorage()

  aboutToAppear() {
    this.createKVStore()
    DeviceManager.clearDeviceList()
  }

  createKVStore(): void {
    this.kvStoreModel.createKvStore(this.context, (data: distributedKVStore.ChangeNotification) => {
      Log.info('kvStore', 'dataChange deviceId:', data.deviceId, 'isSender:', this.isSender)
      
      // 发送端不处理接收消息，接收端才更新 receivedList
      if (this.isSender) {
        Log.info('kvStore', 'sender ignore dataChange')
        return
      }
      
      if (data.insertEntries.length > 0) {
        data.insertEntries.forEach((entry) => {
          Log.info('kvStore', 'inside insert', entry.key, entry.value.type, entry.value.value)
          const value = JSON.parse((entry.value.value) as string) as string[]
          this.receivedList = value  // 直接替换为远程发送的完整列表
          Log.info('kvStore', 'receivedList after insert:', this.receivedList)
        })
      }
      if (data.updateEntries.length > 0) {
        data.updateEntries.forEach((entry) => {
          Log.info('kvStore', 'inside update', entry.key, entry.value.type, entry.value.value)
          const value = JSON.parse((entry.value.value) as string) as string[]
          this.receivedList = value  // 直接替换为远程发送的完整列表
          Log.info('kvStore', 'receivedList after update:', this.receivedList)
        })
      }
    })
  }

  aboutToDisappear(): void {
    this.kvStoreModel.removeDataChangeListener()
  }

  private dialogController: CustomDialogController = new CustomDialogController({
    builder: DeviceListDialog({
      startAbility: this.startAbility,
      deviceList: this.deviceList,
      cancel: this.onCancel,
      param: this.messageList,
      connectedDeviceId: this.connectedDeviceId,
      isLoading: this.isLoading,
      isPaired: this.isPaired,
    })
  })

  // checkAbleUnbind() {
  //   if (this.connectDeviceId !== '') {
  //     this.isAbleUnbind = true
  //   } else {
  //     this.isAbleUnbind = false
  //   }
  // }
  startFindingNearbyDevice(): void {
    DeviceManager.startDeviceDiscovery()
  }

  onCancel(): void {
    DeviceManager.stopDeviceDiscovery()
  }

  pushData(data: string): void {
    Log.info('ConnectedDeviceId: ', this.connectedDeviceId)
    Log.info('ConnectedDeviceId data: ', data)
    this.messageList.push(data)
    this.kvStoreModel.put('sync messageList', JSON.stringify(this.messageList), this.remoteConnectDeviceId)
    // Log.info('ConnectedDeviceId shared_text: ', JSON.stringify(this.shared_data))
    // this.shared_data.push(data)
    // this.kvStoreModel.put('shared_text', JSON.stringify(this.shared_data), this.connectedDeviceId)
  }

  startAbility(
    context: common.UIAbilityContext,
    device: distributedDeviceManager.DeviceBasicInfo,
    shared_list: string[]
  ): void {
    DeviceManager.authenticateDevice(context, device, shared_list)
    DeviceManager.stopDeviceDiscovery()
  }

  build() {
    Column() {
      Row() {
        Button('Find nearby Device')
          .onClick(() => {
            this.startFindingNearbyDevice()
            this.dialogController.open()
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      Row() {
        Text(`${this.isSender ? 'Sender' : 'Receiver'}`)
          .alignSelf(ItemAlign.Start)

        Text(`Paired: ${this.isPaired}`)
          .alignSelf(ItemAlign.End)
      }
      .width('100%')
      .zIndex(1)
      .justifyContent(FlexAlign.End)

      if (this.isLoading) {
        LoadingProgress()
          .width(50)
      }
      if (this.connectedDeviceId !== '') {
        Button('Unbind')
          .onClick(() => {
            this.getUIContext().getPromptAction().showToast({
              message: "unbinding..."
            })
            setTimeout(() => {
              DeviceManager.unbindDevice(this.connectedDeviceId)
              this.connectedDeviceId = ''
              this.remoteConnectDeviceId = ''
            }, 100)
          })
      }
      Text('Connected device id: ' + this.remoteConnectDeviceId == '' ? this.connectedDeviceId :
      this.remoteConnectDeviceId)

      TextInput({ text: this.textInput, placeholder: 'Input your word..' })
        .onChange((value: string) => {
          this.textInput = value
        })

      Button('Send')
        .onClick(() => {
          if ((!this.connectedDeviceId && !this.remoteConnectDeviceId) || !this.textInput) {
            Log.info('No device connected or text is empty!')
            return
          }

          if (this.textInput) {
            this.pushData(this.textInput)
            // this.kvStoreModel.put('shared_text', this.textInput, this.connectDeviceId)
          }
        })

      Text('Send message:')
      ForEach(this.messageList, (item: string) => {
        Text(item)
      })

      Text('receive message:')
      ForEach(this.receivedList, (item: string) => {
        Text(item)
      })

    }
    .width('100%')
    .height('100%')
  }
}