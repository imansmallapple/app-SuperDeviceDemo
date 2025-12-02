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
    Log.info('Index', 'aboutToAppear - isSender:', this.isSender, 'isReceiver:', this.isReceiver)
    this.createKVStore()
    
    // 只有发送端才清空设备列表，接收端不需要
    if (!this.isReceiver) {
      DeviceManager.clearDeviceList()
    }
    
    // 如果是接收端，记录日志
    if (this.isReceiver) {
      Log.info('Index', 'This is receiver side, waiting for messages...')
    }
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
    this.textInput = ''  // 清空输入框
  }

  @Builder
  MessageBubble(message: string, isSent: boolean) {
    Row() {
      if (isSent) {
        Blank()
      }
      
      Text(message)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor(isSent ? '#007AFF' : '#E5E5EA')
        .fontColor(isSent ? Color.White : Color.Black)
        .borderRadius(16)
        .width('70%')
        .wordBreak(WordBreak.BREAK_ALL)
      
      if (!isSent) {
        Blank()
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 4, bottom: 4 })
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
      // 顶部导航栏
      Row() {
        Text(this.isPaired ? 
          `${this.isSender ? '📤 Connected' : '📥 Connected'}` : 
          '🔗 Not Connected')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isPaired ? '#007AFF' : '#8E8E93')
        
        Blank()
        
        Button({ type: ButtonType.Normal }) {
          Text('🔍')
            .fontSize(20)
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor('#F2F2F7')
        .onClick(() => {
          this.startFindingNearbyDevice()
          this.dialogController.open()
        })
        
        if (this.isPaired && this.remoteConnectDeviceId !== '') {
          Button({ type: ButtonType.Normal }) {
            Text('✕')
              .fontSize(20)
              .fontColor('#FF3B30')
          }
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor('#F2F2F7')
          .margin({ left: 8 })
          .onClick(() => {
            this.getUIContext().getPromptAction().showToast({
              message: "Disconnecting..."
            })
            setTimeout(() => {
              DeviceManager.unbindDevice(this.connectedDeviceId)
              this.connectedDeviceId = ''
              this.remoteConnectDeviceId = ''
              this.messageList = []
              this.receivedList = []
            }, 100)
          })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .backgroundColor('#F9F9F9')
      .borderRadius({ bottomLeft: 12, bottomRight: 12 })
      .shadow({ radius: 2, color: '#00000010', offsetY: 2 })

      // 连接状态信息
      if (this.isPaired) {
        Row() {
          Text(`Role: ${this.isSender ? 'Sender' : 'Receiver'}`)
            .fontSize(12)
            .fontColor('#8E8E93')
          
          Text('•')
            .fontSize(12)
            .fontColor('#8E8E93')
            .margin({ left: 8, right: 8 })
          
          Text(`Device ID: ${this.remoteConnectDeviceId.substring(0, 8)}...`)
            .fontSize(12)
            .fontColor('#8E8E93')
            .width('60%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor('#F2F2F7')
        .justifyContent(FlexAlign.Center)
      }

      // 消息列表区域
      List({ space: 4 }) {
        // 显示发送的消息
        ForEach(this.messageList, (item: string, index: number) => {
          ListItem() {
            this.MessageBubble(item, true)
          }
        }, (item: string, index: number) => `sent_${index}_${item}`)
        
        // 显示接收的消息
        ForEach(this.receivedList, (item: string, index: number) => {
          ListItem() {
            this.MessageBubble(item, false)
          }
        }, (item: string, index: number) => `received_${index}_${item}`)
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor('#FFFFFF')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      // 底部输入区域
      Row() {
        TextInput({ 
          text: this.textInput, 
          placeholder: 'Type a message...' 
        })
        .layoutWeight(1)
        .height(40)
        .borderRadius(20)
        .backgroundColor('#F2F2F7')
        .padding({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.textInput = value
        })
        .onSubmit(() => {
          if ((!this.connectedDeviceId && !this.remoteConnectDeviceId) || !this.textInput) {
            this.getUIContext().getPromptAction().showToast({
              message: "No device connected or empty message"
            })
            return
          }
          if (this.textInput) {
            this.pushData(this.textInput)
          }
        })

        Button({ type: ButtonType.Circle }) {
          Text('➤')
            .fontSize(20)
            .fontColor(Color.White)
        }
        .width(40)
        .height(40)
        .margin({ left: 8 })
        .backgroundColor(this.textInput ? '#007AFF' : '#C7C7CC')
        .enabled(!!this.textInput)
        .onClick(() => {
          if ((!this.connectedDeviceId && !this.remoteConnectDeviceId) || !this.textInput) {
            this.getUIContext().getPromptAction().showToast({
              message: "No device connected or empty message"
            })
            return
          }

          if (this.textInput) {
            this.pushData(this.textInput)
          }
        })
      }
      .width('100%')
      .padding(12)
      .backgroundColor('#F9F9F9')
      .borderRadius({ topLeft: 12, topRight: 12 })

    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}