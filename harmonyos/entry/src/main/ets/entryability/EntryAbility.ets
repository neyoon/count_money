import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.acceptWant(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.acceptWant(want);
  }

  private acceptWant(want: Want): void {
    const action = want.parameters?.action;
    AppStorage.setOrCreate('launchAction', typeof action === 'string' ? action : '');
    AppStorage.setOrCreate('launchEpoch', Date.now());
  }

  onWindowStageCreate(stage: window.WindowStage): void {
    stage.loadContent('pages/Index');
  }
}
