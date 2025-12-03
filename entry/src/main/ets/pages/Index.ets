import DeviceManager from '../utils/DeviceManager'
import DeviceListDialog from '../view/CustomDialogComponent';
import { distributedDeviceManager } from '@kit.DistributedServiceKit';
import Log from '../utils/Log';
import { common } from '@kit.AbilityKit';
import KvStoreModel from '../utils/kvStoreUtil';
// import { distributedKVStore } from '@kit.ArkData';
import distributedKVStore from '@ohos.data.distributedKVStore';

// 消息接口定义
interface ChatMessage {
  content: string
  isSent: boolean  // true=自己发的, false=对方发的
  timestamp: number
}

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
  @State allMessages: ChatMessage[] = []  // 合并的消息列表，按时间排序
  private scroller: Scroller = new Scroller()  // 滚动控制器
  @State isSyncing: boolean = false  // 同步状态
  private lastReceivedCount: number = 0  // 跟踪上次处理的接收消息数量
  private syncTimer: number = -1  // 用于防抖的定时器
  private pollTimer: number = -1  // 主动轮询定时器 - 每2秒拉取一次数据
  storage: LocalStorage | undefined = this.getUIContext().getSharedLocalStorage()

  aboutToAppear() {
    Log.info('Index', '========== aboutToAppear START ==========')
    Log.info('Index', 'aboutToAppear - isSender:', this.isSender, 'isReceiver:', this.isReceiver)
    Log.info('Index', 'aboutToAppear - remoteConnectDeviceId:', this.remoteConnectDeviceId)
    
    this.createKVStore()
    
    // 清空本地状态，确保从干净状态开始
    this.messageList = []
    this.receivedList = []
    this.allMessages = []
    this.lastReceivedCount = 0
    Log.info('Index', '✅ Cleared all local message state')
    
    // 清空 KVStore 中的旧数据（延迟执行，等待 KVStore 初始化完成）
    setTimeout(() => {
      Log.info('Index', '🧹 Cleaning old KVStore data...')
      this.kvStoreModel.delete('messages_sender', (success) => {
        Log.info('Index', `Delete messages_sender: ${success}`)
      })
      this.kvStoreModel.delete('messages_receiver', (success) => {
        Log.info('Index', `Delete messages_receiver: ${success}`)
      })
    }, 500)
    
    // 启动主动轮询机制 - 每2秒拉取一次数据
    this.startPolling()
    
    // 初始化时不需要调用updateAllMessages，因为还没有消息
    // updateAllMessages只在接收到新消息时调用
    
    // 只有发送端才清空设备列表,接收端不需要
    if (!this.isReceiver) {
      DeviceManager.clearDeviceList()
    }
    
    // 如果是接收端，记录日志
    if (this.isReceiver) {
      Log.info('Index', 'This is receiver side, waiting for messages...')
    }
    
    Log.info('Index', '========== aboutToAppear END ==========')
  }

  // 启动主动轮询机制
  private startPolling(): void {
    Log.info('Index', '🔄 Starting polling mechanism...')
    
    // 清除旧的定时器
    if (this.pollTimer !== -1) {
      clearInterval(this.pollTimer)
    }
    
    // 每2秒主动拉取一次数据（仅在已连接时）
    this.pollTimer = setInterval(() => {
      // 只在已连接远端设备时才同步
      if (this.remoteConnectDeviceId && this.remoteConnectDeviceId.length > 0) {
        Log.info('Index', '📡 Polling: Manually triggering sync to', this.remoteConnectDeviceId)
        this.kvStoreModel.manualPullSync(this.remoteConnectDeviceId)
      } else {
        Log.info('Index', '⏸️ Polling: No remote device connected, skipping sync')
      }
    }, 2000)
    
    Log.info('Index', '✅ Polling started with 2s interval')
  }

  // 停止轮询
  private stopPolling(): void {
    if (this.pollTimer !== -1) {
      clearInterval(this.pollTimer)
      this.pollTimer = -1
      Log.info('Index', '✅ Polling stopped')
    }
  }

  createKVStore(): void {
    Log.info('Index', '========== createKVStore START ==========')
    Log.info('Index', 'isSender:', this.isSender)
    Log.info('Index', 'isReceiver:', this.isReceiver)
    Log.info('Index', 'remoteConnectDeviceId:', this.remoteConnectDeviceId)
    
    this.kvStoreModel.createKvStore(this.context, (data: distributedKVStore.ChangeNotification) => {
      Log.info('kvStore', '==========================================')
      Log.info('kvStore', 'dataChange event received!')
      Log.info('kvStore', 'deviceId:', data.deviceId)
      Log.info('kvStore', 'insertEntries:', data.insertEntries.length)
      Log.info('kvStore', 'updateEntries:', data.updateEntries.length)
      Log.info('kvStore', 'deleteEntries:', data.deleteEntries.length)
      
      // 不再简单地忽略空deviceId，而是根据key判断
      // 因为远程同步的数据在本地也可能触发空deviceId的事件
      
      // 获取当前设备的角色标识
      let myRole: string
      let remoteRole: string
      
      // 优先使用明确的角色标识
      if (this.isReceiver) {
        // 被远程启动的接收端
        myRole = 'receiver'
        remoteRole = 'sender'
        Log.info('kvStore', '✅ Explicit receiver role (remote started)')
      } else if (this.isSender) {
        // 明确的发送端
        myRole = 'sender'
        remoteRole = 'receiver'
        Log.info('kvStore', '✅ Explicit sender role')
      } else {
        // 本地启动且还没明确角色的情况
        // 根据是否主动连接来推断
        if (this.remoteConnectDeviceId && this.connectedDeviceId) {
          // 有连接ID，说明是主动发起连接的一方
          myRole = 'sender'
          remoteRole = 'receiver'
          Log.info('kvStore', '🔍 No explicit role, inferring as sender (has connection)')
        } else {
          // 否则默认为接收端
          myRole = 'receiver'
          remoteRole = 'sender'
          Log.info('kvStore', '🔍 No explicit role, defaulting to receiver')
        }
      }
      
      Log.info('kvStore', 'Current device role:', myRole)
      Log.info('kvStore', 'Expecting messages from role:', remoteRole)
      Log.info('kvStore', `Will process key: messages_${remoteRole}`)
      Log.info('kvStore', '------------------------------------------')
      
      // 处理插入的数据
      if (data.insertEntries.length > 0) {
        data.insertEntries.forEach((entry) => {
          Log.info('kvStore', 'inside insert', entry.key, entry.value.type, entry.value.value)
          // 只处理对方发送的消息（key 包含对方的角色）
          if (entry.key === `messages_${remoteRole}`) {
            Log.info('kvStore', `✅ Processing remote message (key: ${entry.key})`)
            const value = JSON.parse((entry.value.value) as string) as string[]
            const oldLength = this.receivedList.length
            this.receivedList = value
            
            Log.info('kvStore', `receivedList changed from ${oldLength} to ${value.length} messages`)
            Log.info('kvStore', 'All received messages:', JSON.stringify(value))
            
            // 更新合并消息列表
            this.updateAllMessages()
            
            Log.info('kvStore', 'receivedList after insert:', this.receivedList)
            
            // 主动触发一次同步，确保能继续接收后续消息
            // 使用防抖机制避免短时间内多次sync冲突
            const targetDeviceId = this.remoteConnectDeviceId || this.connectedDeviceId
            if (targetDeviceId) {
              // 清除之前的定时器
              if (this.syncTimer !== -1) {
                clearTimeout(this.syncTimer)
              }
              // 设置新的延迟sync（100ms防抖）
              this.syncTimer = setTimeout(() => {
                Log.info('kvStore', '🔄 Triggering sync after receiving message to ensure continuous updates')
                this.kvStoreModel.sync([targetDeviceId])
                this.syncTimer = -1
              }, 100)
            }
          } else {
            Log.info('kvStore', `⏭️ Skipping local message (key: ${entry.key}, expecting: messages_${remoteRole})`)
          }
        })
      }
      
      // 处理更新的数据
      if (data.updateEntries.length > 0) {
        data.updateEntries.forEach((entry) => {
          Log.info('kvStore', 'inside update', entry.key, entry.value.type, entry.value.value)
          // 只处理对方发送的消息（key 包含对方的角色）
          if (entry.key === `messages_${remoteRole}`) {
            Log.info('kvStore', `✅ Processing remote message (key: ${entry.key})`)
            const value = JSON.parse((entry.value.value) as string) as string[]
            const oldLength = this.receivedList.length
            this.receivedList = value
            
            Log.info('kvStore', `receivedList changed from ${oldLength} to ${value.length} messages`)
            Log.info('kvStore', 'All received messages:', JSON.stringify(value))
            
            // 更新合并消息列表
            this.updateAllMessages()
            
            Log.info('kvStore', 'receivedList after update:', this.receivedList)
            
            // 主动触发一次同步，确保能继续接收后续消息
            // 使用防抖机制避免短时间内多次sync冲突
            const targetDeviceId = this.remoteConnectDeviceId || this.connectedDeviceId
            if (targetDeviceId) {
              // 清除之前的定时器
              if (this.syncTimer !== -1) {
                clearTimeout(this.syncTimer)
              }
              // 设置新的延迟sync（100ms防抖）
              this.syncTimer = setTimeout(() => {
                Log.info('kvStore', '🔄 Triggering sync after receiving message to ensure continuous updates')
                this.kvStoreModel.sync([targetDeviceId])
                this.syncTimer = -1
              }, 100)
            }
          } else {
            Log.info('kvStore', `⏭️ Skipping local message (key: ${entry.key}, expecting: messages_${remoteRole})`)
          }
        })
      }
    })
    
    // 注册同步完成回调，主动拉取远程数据
    this.kvStoreModel.onSyncComplete(() => {
      Log.info('Index', '🔄 syncComplete triggered - fetching remote data')
      
      // 确定远程设备使用的key
      let remoteKey: string
      if (this.isReceiver) {
        // 接收端需要拉取发送端的数据
        remoteKey = 'messages_sender'
      } else {
        // 发送端需要拉取接收端的数据
        remoteKey = 'messages_receiver'
      }
      
      Log.info('Index', `📥 Fetching data with key: ${remoteKey}`)
      
      // 主动从KVStore中获取数据
      this.kvStoreModel.get(remoteKey, (value: string | undefined) => {
        if (value === undefined) {
          Log.info('Index', `⚠️ No data found for key: ${remoteKey}`)
          return
        }
        
        try {
          const messages = JSON.parse(value) as string[]
          Log.info('Index', `✅ Fetched ${messages.length} messages from ${remoteKey}`)
          
          // 更新接收到的消息列表
          const oldLength = this.receivedList.length
          this.receivedList = messages
          
          Log.info('Index', `📊 receivedList updated: ${oldLength} -> ${this.receivedList.length}`)
          
          // 更新UI
          this.updateAllMessages()
        } catch (error) {
          Log.error('Index', `❌ Failed to parse messages: ${JSON.stringify(error)}`)
        }
      })
    })
  }

  aboutToDisappear(): void {
    Log.info('Index', '🛑 aboutToDisappear called - stopping polling')
    this.stopPolling()
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
    Log.info('Index', '=== pushData called ===')
    Log.info('Index', 'isSyncing status:', this.isSyncing)
    
    if (this.isSyncing) {
      Log.info('Index', 'Still syncing previous message, please wait...');
      this.getUIContext().getPromptAction().showToast({
        message: "Syncing previous message..."
      });
      return;
    }
    
    Log.info('Index', '=== pushData START ===')
    Log.info('Index', 'Sending message:', data)
    Log.info('Index', 'connectedDeviceId:', this.connectedDeviceId)
    Log.info('Index', 'remoteConnectDeviceId:', this.remoteConnectDeviceId)
    Log.info('Index', 'Current messageList length:', this.messageList.length)
    Log.info('Index', 'Current allMessages length:', this.allMessages.length)
    
    // 检查连接状态
    if (!this.remoteConnectDeviceId) {
      Log.error('Index', 'No remote device connected!')
      this.getUIContext().getPromptAction().showToast({
        message: "Device not connected!"
      });
      return;
    }
    
    this.messageList.push(data)
    Log.info('Index', 'Added to messageList, new length:', this.messageList.length)
    Log.info('Index', 'All messages in messageList:', JSON.stringify(this.messageList))
    
    // 添加到合并消息列表（使用真实时间戳）
    const timestamp = Date.now()
    this.allMessages.push({
      content: data,
      isSent: true,
      timestamp: timestamp
    })
    Log.info('Index', `Added to allMessages with timestamp ${timestamp}, new length: ${this.allMessages.length}`)
    
    // 按时间排序
    this.allMessages.sort((a, b) => a.timestamp - b.timestamp)
    
    // 使用包含本地 networkId 的唯一 key，这样对方可以识别消息来源
    // 关键修复：本地启动的设备（发起连接的）使用 sender key
    // 远程启动的设备（被连接的）使用 receiver key
    const messageKey = 'messages_' + (this.isReceiver ? 'receiver' : 'sender')
    Log.info('Index', 'Using key:', messageKey)
    Log.info('Index', 'isReceiver:', this.isReceiver, 'isSender:', this.isSender)
    
    this.isSyncing = true
    Log.info('Index', 'Set isSyncing = true')
    
    this.kvStoreModel.put(messageKey, JSON.stringify(this.messageList), this.remoteConnectDeviceId, (success: boolean) => {
      Log.info('Index', 'Sync callback received, success:', success)
      Log.info('Index', 'Setting isSyncing = false')
      this.isSyncing = false
      Log.info('Index', 'isSyncing is now:', this.isSyncing)
      
      if (success) {
        Log.info('Index', 'Message synced successfully')
        Log.info('Index', '=== pushData END (success) ===')
      } else {
        Log.error('Index', 'Message sync failed, will retry...')
        
        // 重试一次
        setTimeout(() => {
          this.kvStoreModel.put(messageKey, JSON.stringify(this.messageList), this.remoteConnectDeviceId, (retrySuccess: boolean) => {
            if (!retrySuccess) {
              this.getUIContext().getPromptAction().showToast({
                message: "Sync failed! Check connection."
              });
            }
          });
        }, 500);
      }
    })
    
    this.textInput = ''  // 清空输入框
    Log.info('Index', 'Cleared textInput, new value:', this.textInput)
    
    // 延迟滚动到底部，等待UI更新
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom)
    }, 100)
  }

  // 更新合并消息列表（增量添加新接收的消息）
  updateAllMessages(): void {
    Log.info('Index', 'updateAllMessages called')
    Log.info('Index', '  - receivedList.length:', this.receivedList.length)
    Log.info('Index', '  - lastReceivedCount:', this.lastReceivedCount)
    Log.info('Index', '  - allMessages.length:', this.allMessages.length)
    
    // 只处理新接收的消息
    if (this.receivedList.length > this.lastReceivedCount) {
      Log.info('Index', `Processing ${this.receivedList.length - this.lastReceivedCount} new messages`)
      
      // 添加新消息，使用当前时间 + 索引偏移确保顺序
      const baseTime = Date.now()
      for (let i = this.lastReceivedCount; i < this.receivedList.length; i++) {
        const timestamp = baseTime + (i - this.lastReceivedCount)
        this.allMessages.push({
          content: this.receivedList[i],
          isSent: false,
          timestamp: timestamp
        })
        Log.info('Index', `Added received message [${i}]: "${this.receivedList[i]}" with timestamp ${timestamp}`)
      }
      
      // 更新计数
      this.lastReceivedCount = this.receivedList.length
      Log.info('Index', `Updated lastReceivedCount to ${this.lastReceivedCount}`)
      
      // 按时间排序
      this.allMessages.sort((a, b) => a.timestamp - b.timestamp)
      
      // 滚动到底部
      setTimeout(() => {
        this.scroller.scrollEdge(Edge.Bottom)
      }, 100)
    } else {
      Log.info('Index', 'No new messages to process')
    }
  }

  @Builder
  MessageBubble(message: string, isSent: boolean) {
    Row() {
      if (isSent) {
        Blank()
      }
      
      // 消息气泡容器
      Column() {
        Text(message)
          .fontSize(16)
          .fontColor(isSent ? Color.White : '#1C1C1E')
          .lineHeight(22)
          .wordBreak(WordBreak.BREAK_WORD)
          .textAlign(TextAlign.Start)
      }
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .constraintSize({ maxWidth: '75%' })  // 最大宽度 75%，自适应内容
      .backgroundColor(isSent ? '#007AFF' : '#E9E9EB')
      .borderRadius(isSent ? { topLeft: 18, topRight: 18, bottomLeft: 18, bottomRight: 4 } : 
                              { topLeft: 18, topRight: 18, bottomLeft: 4, bottomRight: 18 })
      .shadow({ 
        radius: 8, 
        color: isSent ? '#007AFF20' : '#00000010', 
        offsetX: 0, 
        offsetY: 2 
      })
      
      if (!isSent) {
        Blank()
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
    .justifyContent(isSent ? FlexAlign.End : FlexAlign.Start)
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
        Column() {
          Text(this.isPaired ? 'Chat Room' : 'Not Connected')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1C1C1E')
          
          if (this.isPaired) {
            Text('Connected & Syncing')
              .fontSize(12)
              .fontColor('#34C759')
              .margin({ top: 2 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        
        Blank()
        
        Button({ type: ButtonType.Normal }) {
          Text('🔍')
            .fontSize(22)
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor('#F2F2F7')
        .onClick(() => {
          this.startFindingNearbyDevice()
          this.dialogController.open()
        })
        
        if (this.isPaired && this.remoteConnectDeviceId !== '') {
          Button({ type: ButtonType.Normal }) {
            Text('✕')
              .fontSize(22)
              .fontColor('#FF3B30')
              .fontWeight(FontWeight.Medium)
          }
          .width(44)
          .height(44)
          .borderRadius(22)
          .backgroundColor('#F2F2F7')
          .margin({ left: 10 })
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
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .backgroundColor('#FFFFFF')
      .shadow({ radius: 3, color: '#00000008', offsetY: 1 })

      // 连接状态信息
      if (this.isPaired) {
        Row() {
          Row() {
            Text('●')
              .fontSize(10)
              .fontColor('#34C759')
              .margin({ right: 6 })
            
            Text('Online')
              .fontSize(13)
              .fontColor('#34C759')
              .fontWeight(FontWeight.Medium)
          }
          
          Blank()
          
          Text(`ID: ${this.remoteConnectDeviceId.substring(0, 12)}...`)
            .fontSize(12)
            .fontColor('#8E8E93')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .backgroundColor('#F8F8F8')
      }

      // 消息列表区域
      List({ space: 8, scroller: this.scroller }) {
        // 显示所有消息（按时间排序）
        ForEach(this.allMessages, (item: ChatMessage, index: number) => {
          ListItem() {
            this.MessageBubble(item.content, item.isSent)
          }
        }, (item: ChatMessage, index: number) => `msg_${index}_${item.timestamp}`)
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor('#F5F5F5')
      .padding({ top: 8, bottom: 8 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      // 底部输入区域
      Row() {
        TextInput({ 
          text: this.textInput, 
          placeholder: '💬 Type a message...' 
        })
        .layoutWeight(1)
        .height(44)
        .borderRadius(22)
        .backgroundColor('#FFFFFF')
        .padding({ left: 18, right: 18 })
        .fontSize(16)
        .placeholderColor('#AEAEB2')
        .border({ width: 1, color: '#E5E5EA' })
        .onChange((value: string) => {
          this.textInput = value
          Log.info('Index', 'TextInput onChange, new value:', value)
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
          if (this.isSyncing) {
            LoadingProgress()
              .width(22)
              .height(22)
              .color(Color.White)
          } else {
            Text('➤')
              .fontSize(22)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Bold)
          }
        }
        .width(44)
        .height(44)
        .margin({ left: 10 })
        .backgroundColor(this.textInput && !this.isSyncing ? '#007AFF' : '#C7C7CC')
        .shadow({ 
          radius: 8, 
          color: this.textInput && !this.isSyncing ? '#007AFF30' : '#00000010', 
          offsetY: 2 
        })
        .enabled(!!this.textInput && !this.isSyncing)
        .onClick(() => {
          Log.info('Index', '=== Send button clicked ===')
          Log.info('Index', 'textInput:', this.textInput)
          Log.info('Index', 'isSyncing:', this.isSyncing)
          Log.info('Index', 'connectedDeviceId:', this.connectedDeviceId)
          Log.info('Index', 'remoteConnectDeviceId:', this.remoteConnectDeviceId)
          
          if ((!this.connectedDeviceId && !this.remoteConnectDeviceId) || !this.textInput) {
            Log.info('Index', 'Validation failed')
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
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor('#FFFFFF')
      .borderRadius({ topLeft: 16, topRight: 16 })
      .shadow({ radius: 4, color: '#00000008', offsetY: -2 })

    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}