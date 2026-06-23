import UIAbility from '@ohos.app.ability.UIAbility';
import window from '@ohos.window';
import Want from '@ohos.app.ability.Want';
import { AbilityConstant } from '@kit.AbilityKit';
export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 应用初始化
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err) {
        console.error('Failed to load the content.', JSON.stringify(err));
        return;
      }
    });
  }
}