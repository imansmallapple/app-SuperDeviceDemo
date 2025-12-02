import { distributedDeviceManager } from '@kit.DistributedServiceKit';
import { common } from '@kit.AbilityKit';

@CustomDialog
export default struct DeviceListDialog {
  controller?: CustomDialogController
  @Link deviceList: distributedDeviceManager.DeviceBasicInfo[]
  @Link param: string[]
  @State toConnectDeviceId: string = ''
  @Link connectedDeviceId: string
  @State selectedIndex: number = -1
  @State selectedDeviceName: string = ''
  @Link isLoading: boolean
  @Link isPaired: boolean
  cancel: () => void = () => {
  }
  startAbility: (context: common.UIAbilityContext, device: distributedDeviceManager.DeviceBasicInfo,
    textInput: string[]) => void
    = () => {
  }

  getDeviceInfo(index: number): string {
    if (this.deviceList.length == 0) {
      this.getUIContext().getPromptAction().showToast({
        message: 'No available device!'
      })
      return ''
    }

    if (this.deviceList.length == 0) {
      this.isLoading = true
    } else {
      this.isLoading = false
    }

    this.toConnectDeviceId = this.deviceList[index].deviceId

    return this.deviceList[index].deviceName
  }

  build() {
    Column() {
      Row() {
        Text('Select Device')
          .fontSize(20)
          .width('100%')
          .textAlign(TextAlign.Start)
          .fontColor(Color.Black)
          .fontWeight(FontWeight.Bold)
      }
      .padding({
        left: 24,
        right: 24,
        top: 24
      })
      .height(56)

      List() {
        ForEach(this.deviceList, (item: distributedDeviceManager.DeviceBasicInfo, index: number) => {
          ListItem() {
            Column() {
              Row() {
                Row() {
                  Text(item.deviceName)
                    .fontSize(24)
                    .width('78%')
                    .fontColor(Color.Black)
                    .margin({ left: 16 })
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .textAlign(TextAlign.Start)
                }
                .justifyContent(FlexAlign.Start)

                if (index === this.selectedIndex) {
                  Image($r('app.media.icon'))
                    .width('8%')
                    .objectFit(ImageFit.Contain)
                } else {
                  Image($r('app.media.app_icon'))
                    .width('8%')
                    .objectFit(ImageFit.Contain)
                    .opacity(0.5)
                }
              }
              .height(56)
              .onClick(() => {
                this.selectedIndex = index
                this.selectedDeviceName = this.getDeviceInfo(index)
              })
              .padding({
                left: 24,
                right: 24
              })
              .width('100%')
              .justifyContent(FlexAlign.SpaceBetween)

              if (index !== this.deviceList.length - 1) {
                Row() {
                  Divider()
                    .width('100%')
                    .height(1)
                    .opacity(0.1)
                }
                .padding({
                  left: 64,
                  right: 24
                })
                .width('100%')
              }
            }
          }
        }, (item: distributedDeviceManager.DeviceBasicInfo) => item.deviceId)
      }
      .width('100%')

      Row() {
        Column() {
          Text('Cancel')
            .fontColor("#007DFF")
            .fontSize(16)
            .fontWeight(500)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (this.controller !== undefined) {
            this.controller.close()
          }
          this.cancel()
        })

        Divider()
          .vertical(true)
          .height(22)

        Column() {
          Text('Confirm')
            .fontColor("#007DFF")
            .fontSize(16)
            .fontWeight(500)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .height(40)
        .onClick(() => {
          if (-1 === this.selectedIndex) {
            this.getUIContext().getPromptAction().showToast({
              message: 'No available device!'
            })
          } else {
            if (this.controller !== undefined) {
              this.controller.close()
            }
            this.startAbility(this.getUIContext().getHostContext() as common.UIAbilityContext, this.deviceList[this.selectedIndex],
              this.param)
            this.getUIContext().getPromptAction().showToast({
              message: `Device: ${this.selectedDeviceName} connected!`
            })
            this.connectedDeviceId = this.toConnectDeviceId
            this.isPaired = true
          }
        })
      }
      .backgroundColor(Color.White)
    }
  }
}