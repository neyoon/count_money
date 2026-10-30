import { AppColors } from '../theme/AppColors';

@Entry
@Component
struct MoneyCard {
  build() {
    Column({ space: 18 }) {
      Text('Tally').fontSize(25).fontWeight(FontWeight.Bold).fontColor(AppColors.ink)
      Row({ space: 8 }) {
        Button('记账').fontSize(13).fontColor(AppColors.onPrimary).backgroundColor(AppColors.primary)
          .onClick(() => postCardAction(this, {
            action: 'router', abilityName: 'EntryAbility', params: { action: 'entry' }
          }))
        Button('识别截图').fontSize(13).fontColor(AppColors.primary).backgroundColor(AppColors.primaryTint)
          .onClick(() => postCardAction(this, {
            action: 'router', abilityName: 'EntryAbility', params: { action: 'ocr' }
          }))
      }
    }.width('100%').height('100%').padding(16).alignItems(HorizontalAlign.Start)
    .backgroundColor(AppColors.surface)
  }
}
