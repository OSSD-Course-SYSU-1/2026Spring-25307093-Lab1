import common from '@ohos.app.ability.common';
import promptAction from '@ohos.promptAction';
import distributedKVStore from '@ohos.data.distributedKVStore';
import display from '@ohos.display';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { AbilityConstant, Want } from '@kit.AbilityKit';


// ========== 常量 ==========
const PRIORITY_LOW = 1;
const PRIORITY_MID = 2;
const PRIORITY_HIGH = 3;

const FONT_SMALL = 14;
const FONT_MID = 16;
const FONT_LARGE = 18;

const STORE_NAME = 'TodoStore';
const PET_STORE_NAME = 'PetStore';
const KEY_TODO_LIST = 'todoList';
const KEY_THEME = 'appTheme';
const KEY_FONT_SIZE = 'fontSize';
const KEY_PET_DATA = 'petData';

const BREAKPOINT_XS = 0;
const BREAKPOINT_SM = 1;
const BREAKPOINT_MD = 2;
const BREAKPOINT_LG = 3;

const MIGRATION_KEY_TODOLIST = 'migrationTodoList';
const MIGRATION_KEY_FILTER = 'migrationFilter';

const THEME_COLOR = '#8AB4D6'; // 柔和浅蓝

interface TodoItem {
  id: number;
  content: string;
  isCompleted: boolean;
  priority: number;
  deadline: string;
  deadTimeStamp: number;
}



const DEFAULT_PET: PetData = {
  name: '小乖',
  stage: 0,
  exp: 0,
  mood: 80,
  lastFeedTime: Date.now(),
  completedTasks: 0,
  totalTasks: 0
};

@Entry
@Component
struct TodoList {
  @State todoList: TodoItem[] = [];
  @State inputText: string = '';
  @State editingId: number = -1;
  @State filterType: number = 0;
  @State showDeleteDialog: boolean = false;
  @State currentDeleteId: number = -1;
  @State isDarkTheme: boolean = false;
  @State selectPriority: number = PRIORITY_MID;
  @State searchKey: string = '';
  @State showSearch: boolean = false;
  @State showMenu: boolean = false;
  @State showDatePicker: boolean = false;
  @State currentFontSize: number = FONT_MID;
  @State selectDeadline: Date = new Date();

  @State currentBreakpoint: number = BREAKPOINT_XS;
  @State currentTabIndex: number = 0;

  @State petData: PetData = { name: '小乖', stage: 0, exp: 0, mood: 80, lastFeedTime: Date.now(), completedTasks: 0, totalTasks: 0 };
  @State petTapScale: number = 1;

  // ===== 番茄钟状态（已移至 PomodoroPage 自管理） =====
  @State pomodoroPlaceholder: number = 0;

  private kvManager?: distributedKVStore.KVManager;
  private kvStore?: distributedKVStore.SingleKVStore;
  private petKvStore?: distributedKVStore.SingleKVStore;

  async aboutToAppear(): Promise<void> {
    await this.initKVStore();
    await this.loadData();
    await this.loadPetData();
    this.setupDataChangeListener();
    this.updateBreakpoint();
    this.checkMigrationData();
  }

  checkMigrationData(): void {
    try {
      const migrationData = AppStorage.get<string>('migrationData');
      const migrationFilter = AppStorage.get<number>('migrationFilter');
      if (migrationData && migrationData.length > 0) {
        const parsedData: TodoItem[] = JSON.parse(migrationData) as TodoItem[];
        if (parsedData && parsedData.length > 0) {
          this.todoList = parsedData;
          if (migrationFilter !== undefined && migrationFilter !== null && migrationFilter >= 0) {
            this.filterType = migrationFilter;
          }
          this.saveData();
          promptAction.showToast({ message: "📱 已迁移 " + this.todoList.length + " 项任务" });
        }
      }
      AppStorage.setOrCreate('migrationData', '');
      AppStorage.setOrCreate('migrationFilter', -1);
    } catch (e) {
      console.error('检查迁移数据失败: ' + JSON.stringify(e));
    }
  }

  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    try {
      wantParam[MIGRATION_KEY_TODOLIST] = JSON.stringify(this.todoList);
      wantParam[MIGRATION_KEY_FILTER] = this.filterType;
      return AbilityConstant.OnContinueResult.AGREE;
    } catch (error) {
      return AbilityConstant.OnContinueResult.REJECT;
    }
  }

  updateBreakpoint(): void {
    try {
      const width: number = px2vp(display.getDefaultDisplaySync().width);
      if (width < 520) this.currentBreakpoint = BREAKPOINT_XS;
      else if (width < 600) this.currentBreakpoint = BREAKPOINT_SM;
      else if (width < 840) this.currentBreakpoint = BREAKPOINT_MD;
      else this.currentBreakpoint = BREAKPOINT_LG;
    } catch (e) {
      this.currentBreakpoint = BREAKPOINT_XS;
    }
  }

  isTablet(): boolean { return this.currentBreakpoint >= BREAKPOINT_MD; }

  getBreakpointName(): string {
    switch (this.currentBreakpoint) {
      case BREAKPOINT_XS: return '手机';
      case BREAKPOINT_SM: return '大手机';
      case BREAKPOINT_MD: return '折叠屏';
      case BREAKPOINT_LG: return '平板';
      default: return '未知';
    }
  }

  getGridColumns(): number {
    if (this.currentBreakpoint >= BREAKPOINT_LG) return 3;
    else if (this.currentBreakpoint >= BREAKPOINT_MD) return 2;
    else return 1;
  }

  getContentPadding(): number {
    if (this.currentBreakpoint >= BREAKPOINT_LG) return 24;
    else if (this.currentBreakpoint >= BREAKPOINT_MD) return 20;
    else return 16;
  }

  getTitleFontSize(): number {
    if (this.currentBreakpoint >= BREAKPOINT_LG) return 32;
    else if (this.currentBreakpoint >= BREAKPOINT_MD) return 28;
    else return 24;
  }

  // ===== KVStore =====
  async initKVStore(): Promise<void> {
    try {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const config: distributedKVStore.KVManagerConfig = { context, bundleName: context.applicationInfo.name };
      this.kvManager = await distributedKVStore.createKVManager(config);

      const options: distributedKVStore.Options = {
        createIfMissing: true,
        encrypt: false,
        backup: false,
        autoSync: true,
        kvStoreType: distributedKVStore.KVStoreType.SINGLE_VERSION,
        securityLevel: distributedKVStore.SecurityLevel.S1
      };
      this.kvStore = await this.kvManager.getKVStore(STORE_NAME, options);
      this.petKvStore = await this.kvManager.getKVStore(PET_STORE_NAME, options);
    } catch (error) {
      console.error('KVStore初始化失败: ' + JSON.stringify(error));
    }
  }

  async loadData(): Promise<void> {
    try {
      if (!this.kvStore) return;
      const todoData = await this.kvStore.get(KEY_TODO_LIST);
      if (todoData) this.todoList = JSON.parse(todoData as string) as TodoItem[];
      else this.todoList = [];
      const themeData = await this.kvStore.get(KEY_THEME);
      if (themeData) this.isDarkTheme = themeData === 'true';
      const fontData = await this.kvStore.get(KEY_FONT_SIZE);
      if (fontData) this.currentFontSize = parseInt(fontData as string);
    } catch (e) {
      this.todoList = [];
    }
  }

  async loadPetData(): Promise<void> {
    try {
      if (!this.petKvStore) return;
      const petData = await this.petKvStore.get(KEY_PET_DATA);
      if (petData) {
        const parsed = JSON.parse(petData as string) as PetData;
        this.petData = parsed;
      } else {
        this.petData = { name: '小乖', stage: 0, exp: 0, mood: 80, lastFeedTime: Date.now(), completedTasks: 0, totalTasks: 0 };
        await this.savePetData();
      }
    } catch (e) {
      this.petData = { name: '小乖', stage: 0, exp: 0, mood: 80, lastFeedTime: Date.now(), completedTasks: 0, totalTasks: 0 };
    }
  }

  async saveData(): Promise<void> {
    try {
      if (!this.kvStore) return;
      await this.kvStore.put(KEY_TODO_LIST, JSON.stringify(this.todoList));
      await this.kvStore.put(KEY_THEME, this.isDarkTheme ? 'true' : 'false');
      await this.kvStore.put(KEY_FONT_SIZE, this.currentFontSize.toString());
    } catch (e) {
      console.error('保存数据失败: ' + JSON.stringify(e));
    }
  }

  async savePetData(): Promise<void> {
    try {
      if (!this.petKvStore) return;
      await this.petKvStore.put(KEY_PET_DATA, JSON.stringify(this.petData));
    } catch (e) {
      console.error('保存宠物数据失败: ' + JSON.stringify(e));
    }
  }

  setupDataChangeListener(): void {
    if (!this.kvStore) return;
    this.kvStore.on('dataChange', distributedKVStore.SubscribeType.SUBSCRIBE_TYPE_ALL, () => { this.loadData(); });
  }

  // ===== 完成任务 → 宠物成长 =====
  onTaskComplete(): void {
    this.petData.exp += 10;
    this.petData.mood = Math.min(100, this.petData.mood + 5);
    this.petData.completedTasks += 1;

    const oldStage = this.petData.stage;
    if (this.petData.exp >= 500) this.petData.stage = 4;
    else if (this.petData.exp >= 300) this.petData.stage = 3;
    else if (this.petData.exp >= 150) this.petData.stage = 2;
    else if (this.petData.exp >= 50) this.petData.stage = 1;

    if (this.petData.stage > oldStage) {
      const stageNames = ['蛋', '幼年', '成长', '成年', '传说'];
      promptAction.showToast({
        message: `🎉 宠物进化了！现在是 ${stageNames[this.petData.stage]}阶段！`
      });
    }
    this.savePetData();
  }

  onPetTap(): void {
    this.petTapScale = 1.3;
    setTimeout(() => { this.petTapScale = 1; }, 300);
    this.currentTabIndex = 1;
  }

  // ===== 共享任务 =====
  async shareTask(item: TodoItem): Promise<void> {
    try {
      const priorityText = item.priority === PRIORITY_HIGH ? '高' : (item.priority === PRIORITY_MID ? '中' : '低');
      const shareText = `【待办任务】\n内容：${item.content}\n优先级：${priorityText}\n截止日期：${item.deadline}\n状态：${item.isCompleted ? '已完成' : '未完成'}`;
      const shareData: systemShare.SharedData = new systemShare.SharedData({ utd: utd.UniformDataType.PLAIN_TEXT, content: shareText });
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      await controller.show(context, {});
    } catch (error) {
      console.error('分享失败: ' + JSON.stringify(error));
    }
  }

  // ===== 合并数组（不用扩展运算符） =====
  private concatArrays(arr1: TodoItem[], arr2: TodoItem[], arr3: TodoItem[], arr4: TodoItem[]): TodoItem[] {
    const result: TodoItem[] = [];
    for (let i = 0; i < arr1.length; i++) {
      result.push(arr1[i]);
    }
    for (let i = 0; i < arr2.length; i++) {
      result.push(arr2[i]);
    }
    for (let i = 0; i < arr3.length; i++) {
      result.push(arr3[i]);
    }
    for (let i = 0; i < arr4.length; i++) {
      result.push(arr4[i]);
    }
    return result;
  }

  sortByPriority(list: TodoItem[]): TodoItem[] {
    const unFinish: TodoItem[] = [];
    const finish: TodoItem[] = [];
    for (let i = 0; i < list.length; i++) {
      if (list[i].isCompleted) {
        finish.push(list[i]);
      } else {
        unFinish.push(list[i]);
      }
    }
    const high: TodoItem[] = [];
    const mid: TodoItem[] = [];
    const low: TodoItem[] = [];
    for (let i = 0; i < unFinish.length; i++) {
      const p = unFinish[i].priority;
      if (p === PRIORITY_HIGH) {
        high.push(unFinish[i]);
      } else if (p === PRIORITY_MID) {
        mid.push(unFinish[i]);
      } else {
        low.push(unFinish[i]);
      }
    }
    return this.concatArrays(high, mid, low, finish);
  }

  getFilteredList(): TodoItem[] {
    let res: TodoItem[] = [];
    const lowerKey = this.searchKey.toLowerCase();
    for (let i = 0; i < this.todoList.length; i++) {
      if (this.todoList[i].content.toLowerCase().indexOf(lowerKey) !== -1) {
        res.push(this.todoList[i]);
      }
    }
    if (this.filterType === 1) {
      const filtered: TodoItem[] = [];
      for (let i = 0; i < res.length; i++) {
        if (!res[i].isCompleted) {
          filtered.push(res[i]);
        }
      }
      res = filtered;
    } else if (this.filterType === 2) {
      const filtered: TodoItem[] = [];
      for (let i = 0; i < res.length; i++) {
        if (res[i].isCompleted) {
          filtered.push(res[i]);
        }
      }
      res = filtered;
    }
    return this.sortByPriority(res);
  }

  isOverTime(timestamp: number): boolean {
    if (isNaN(timestamp) || timestamp <= 0) return false;
    const endOfDay = timestamp + 24 * 60 * 60 * 1000 - 1;
    return Date.now() > endOfDay;
  }

  confirmDelete(): void {
    if (this.currentDeleteId !== -1) {
      const newList: TodoItem[] = [];
      for (let i = 0; i < this.todoList.length; i++) {
        if (this.todoList[i].id !== this.currentDeleteId) {
          newList.push(this.todoList[i]);
        }
      }
      this.todoList = newList;
      if (this.editingId === this.currentDeleteId) {
        this.editingId = -1;
        this.inputText = '';
      }
      this.saveData();
    }
    this.showDeleteDialog = false;
    this.currentDeleteId = -1;
  }

  clearCompletedTask(): void {
    const newList: TodoItem[] = [];
    for (let i = 0; i < this.todoList.length; i++) {
      if (!this.todoList[i].isCompleted) {
        newList.push(this.todoList[i]);
      }
    }
    this.todoList = newList;
    this.saveData();
    promptAction.showToast({ message: "已清空已完成" });
  }

  clearAllTask(): void {
    this.todoList = [];
    this.saveData();
    promptAction.showToast({ message: "已清空全部" });
  }

  toggleComplete(id: number, checked: boolean): void {
    for (let i = 0; i < this.todoList.length; i++) {
      if (this.todoList[i].id === id) {
        if (!this.todoList[i].isCompleted && checked) {
          this.onTaskComplete();
        }
        this.todoList[i].isCompleted = checked;
        this.saveData();
        break;
      }
    }
  }

  getCompletedCount(): number {
    let cnt = 0;
    for (let i = 0; i < this.todoList.length; i++) {
      if (this.todoList[i].isCompleted) cnt++;
    }
    return cnt;
  }

  getPriorityColor(level: number): string {
    if (level === PRIORITY_HIGH) return '#D4A0A0'; // 柔和玫瑰红
    if (level === PRIORITY_MID) return '#D4BFA0'; // 柔和暖金
    return '#A0C4A0'; // 柔和鼠尾草绿
  }

  changeFontSize(): void {
    if (this.currentFontSize === FONT_SMALL) this.currentFontSize = FONT_MID;
    else if (this.currentFontSize === FONT_MID) this.currentFontSize = FONT_LARGE;
    else this.currentFontSize = FONT_SMALL;
    this.saveData();
  }

  startContinue(): void {
    try {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const want: Want = {
        bundleName: context.applicationInfo.name,
        abilityName: context.abilityInfo.name,
        parameters: { 'ability.params.stream': { continuation: { isContinuation: true, continuationType: 0 } } }
      };
      context.startAbility(want);
      promptAction.showToast({ message: "🔄 正在查找附近设备..." });
    } catch (error) {
      promptAction.showToast({ message: "❌ 迁移失败，请确保已登录同一华为账号" });
    }
  }

  getStageEmoji(): string {
    const emojis = ['🥚', '🐣', '🐥', '🦊', '🔥'];
    return emojis[this.petData.stage] || '🥚';
  }

  // ============================================================
  //  任务卡片
  // ============================================================
  @Builder
  TodoCard(item: TodoItem) {
    Row() {
      Row() {
        Checkbox()
          .select(item.isCompleted)
          .onChange((c: boolean) => this.toggleComplete(item.id, c))
          .width(22)
          .height(22);

        Column() {
          Text(item.content)
            .fontSize(this.currentFontSize)
            .fontColor(item.isCompleted ? '#8E8E93' : (this.isDarkTheme ? '#FFFFFF' : '#1C1C1E'))
            .decoration({ type: item.isCompleted ? TextDecorationType.LineThrough : TextDecorationType.None })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });

          Row({ space: 4 }) {
            Text(item.deadline)
              .fontSize(12)
              .fontColor('#8E8E93');
            if (this.isOverTime(item.deadTimeStamp) && !item.isCompleted) {
              Text('· 已逾期')
                .fontSize(12)
                .fontColor('#D4A0A0');
            }
          }
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 10 })
        .layoutWeight(1);
      }
      .layoutWeight(1);

      Row({ space: 6 }) {
        Circle({ width: 8, height: 8 })
          .fill(this.getPriorityColor(item.priority));

        Button() { Text('📤').fontSize(14) }
        .width(32)
        .height(28)
        .backgroundColor('transparent')
        .fontColor('#8E8E93')
        .onClick(() => this.shareTask(item));

        Button() { Text('✏️').fontSize(14) }
        .width(32)
        .height(28)
        .backgroundColor('transparent')
        .fontColor('#8E8E93')
        .onClick(() => {
          this.editingId = item.id;
          this.inputText = item.content;
          this.selectPriority = item.priority;
          this.selectDeadline = new Date(item.deadTimeStamp);
          this.showDatePicker = true;
        });

        Button() { Text('🗑️').fontSize(14) }
        .width(32)
        .height(28)
        .backgroundColor('transparent')
        .fontColor('#D4A0A0')
        .onClick(() => {
          this.currentDeleteId = item.id;
          this.showDeleteDialog = true;
        });
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.isDarkTheme ? '#2C2C2E' : '#FAFAF8')
    .borderRadius(12)
    .shadow({ radius: 4, color: this.isDarkTheme ? 'rgba(0,0,0,0.3)' : 'rgba(0,0,0,0.06)', offsetY: 2 })
    .height(60)
    .alignItems(VerticalAlign.Center)
  }

  // ============================================================
  //  主布局
  // ============================================================
  build() {
    Stack() {
      Column() {
        if (this.currentTabIndex === 0) {
          // ===== Tab 0: 任务列表 =====
          Column() {
            // 顶部
            Column() {
              Row() {
                Column() {
                  Text('📋 待办清单')
                    .fontSize(this.getTitleFontSize())
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#FFFFFF');
                  Text(`${this.todoList.filter(item => !item.isCompleted).length} 项待办 · ${this.getCompletedCount()} 项已完成`)
                    .fontSize(13)
                    .fontColor('rgba(255,255,255,0.7)')
                    .margin({ top: 2 });
                }
                .alignItems(HorizontalAlign.Start);

                Blank();

                Row({ space: 6 }) {
                  Button() { Text('🔄').fontSize(18) }
                  .width(38)
                  .height(38)
                  .backgroundColor('rgba(255,255,255,0.2)')
                  .borderRadius(10)
                  .onClick(() => this.startContinue());

                  Button() { Text('🔍').fontSize(16) }
                  .width(38)
                  .height(38)
                  .backgroundColor('rgba(255,255,255,0.2)')
                  .borderRadius(10)
                  .onClick(() => this.showSearch = !this.showSearch);

                  Button() { Text('⋯').fontSize(18) }
                  .width(38)
                  .height(38)
                  .backgroundColor('rgba(255,255,255,0.2)')
                  .borderRadius(10)
                  .onClick(() => this.showMenu = !this.showMenu);

                  Button() { Text('+').fontSize(22) }
                  .width(38)
                  .height(38)
                  .backgroundColor(THEME_COLOR)
                  .borderRadius(10)
                  .onClick(() => {
                    this.editingId = -1;
                    this.inputText = '';
                    this.selectPriority = PRIORITY_MID;
                    this.selectDeadline = new Date();
                    this.showDatePicker = true;
                  });
                }
              }
              .width('100%')
              .padding({ left: 20, right: 20, top: 48, bottom: 20 });
            }
            .width('100%')
            .backgroundColor('#8AB4D6')
            .borderRadius({ bottomLeft: 24, bottomRight: 24 });

            // 搜索框
            if (this.showSearch) {
              TextInput({ text: this.searchKey, placeholder: '🔍 搜索任务...' })
                .width(`calc(100% - ${this.getContentPadding() * 2}vp)`)
                .height(40)
                .backgroundColor(this.isDarkTheme ? '#2C2C2E' : '#F2F0EC')
                .borderRadius(10)
                .margin({ left: this.getContentPadding(), right: this.getContentPadding(), top: 12, bottom: 8 })
                .onChange((v: string) => this.searchKey = v);
            }

            // 菜单
            if (this.showMenu) {
              Column({ space: 4 }) {
                Button('🌙 切换主题').width('100%').height(40).backgroundColor('#8B8B8B').fontColor(Color.White).onClick(() => { this.isDarkTheme = !this.isDarkTheme; this.saveData(); this.showMenu = false; });
                Button(`🔤 字体 (${this.currentFontSize}px)`).width('100%').height(40).backgroundColor('#8B8B8B').fontColor(Color.White).onClick(() => { this.changeFontSize(); this.showMenu = false; });
                Button('🗑️ 清空已完成').width('100%').height(40).backgroundColor('#D4BFA0').fontColor(Color.White).onClick(() => { this.clearCompletedTask(); this.showMenu = false; });
                Button('⚠️ 清空全部').width('100%').height(40).backgroundColor('#D4A0A0').fontColor(Color.White).onClick(() => { this.clearAllTask(); this.showMenu = false; });
              }
              .width(this.isTablet() ? '40%' : '75%')
              .backgroundColor(this.isDarkTheme ? '#1C1C1E' : '#FAFAF8')
              .padding(12)
              .borderRadius(14)
              .shadow({ radius: 12, color: 'rgba(0,0,0,0.15)' })
              .alignSelf(ItemAlign.End)
              .margin({ right: this.getContentPadding(), top: 4 });
            }

            // 优先级选择
            Row({ space: 6 }) {
              Button('全部')
                .height(30)
                .fontSize(13)
                .backgroundColor(this.selectPriority === 0 ? THEME_COLOR : 'transparent')
                .fontColor(this.selectPriority === 0 ? '#FFFFFF' : '#8E8E93')
                .borderRadius(15)
                .padding({ left: 16, right: 16 })
                .onClick(() => this.selectPriority = 0);

              Button('⬤ 低')
                .height(30)
                .fontSize(13)
                .backgroundColor(this.selectPriority === PRIORITY_LOW ? '#A0C4A0' : 'transparent')
                .fontColor(this.selectPriority === PRIORITY_LOW ? '#FFFFFF' : '#8E8E93')
                .borderRadius(15)
                .padding({ left: 14, right: 14 })
                .onClick(() => this.selectPriority = PRIORITY_LOW);

              Button('⬤ 中')
                .height(30)
                .fontSize(13)
                .backgroundColor(this.selectPriority === PRIORITY_MID ? '#D4BFA0' : 'transparent')
                .fontColor(this.selectPriority === PRIORITY_MID ? '#FFFFFF' : '#8E8E93')
                .borderRadius(15)
                .padding({ left: 14, right: 14 })
                .onClick(() => this.selectPriority = PRIORITY_MID);

              Button('⬤ 高')
                .height(30)
                .fontSize(13)
                .backgroundColor(this.selectPriority === PRIORITY_HIGH ? '#D4A0A0' : 'transparent')
                .fontColor(this.selectPriority === PRIORITY_HIGH ? '#FFFFFF' : '#8E8E93')
                .borderRadius(15)
                .padding({ left: 14, right: 14 })
                .onClick(() => this.selectPriority = PRIORITY_HIGH);
            }
            .width(`calc(100% - ${this.getContentPadding() * 2}vp)`)
            .margin({ top: 12, bottom: 8 });

            // 任务列表
            if (this.getFilteredList().length === 0) {
              Column() {
                Text('📭')
                  .fontSize(48)
                  .margin({ bottom: 12 });
                Text('暂无任务')
                  .fontSize(18)
                  .fontColor('#3A3A3C')
                  .fontWeight(FontWeight.Medium);
                Text('点击「+ 添加」创建你的第一个任务')
                  .fontSize(13)
                  .fontColor('#8E8E93')
                  .margin({ top: 4 });
              }
              .width('100%')
              .height(200)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center);
            } else {
              Grid() {
                ForEach(this.getFilteredList(), (item: TodoItem) => {
                  GridItem() {
                    this.TodoCard(item)
                  }
                  .padding({ left: 2, right: 2, top: 3, bottom: 3 })
                }, (item: TodoItem) => item.id.toString())
              }
              .columnsTemplate('1fr '.repeat(this.getGridColumns()).trim())
              .columnsGap(10)
              .rowsGap(8)
              .width('100%')
              .padding({ left: this.getContentPadding() - 2, right: this.getContentPadding() - 2, top: 4, bottom: 80 })
              .layoutWeight(1)
              .height('auto');
            }

            // 底部筛选
            Row({ space: 0 }) {
              Button('全部')
                .height(34)
                .fontSize(14)
                .fontWeight(this.filterType === 0 ? FontWeight.Medium : FontWeight.Normal)
                .backgroundColor(this.filterType === 0 ? '#FAFAF8' : 'transparent')
                .fontColor(this.filterType === 0 ? THEME_COLOR : '#8E8E93')
                .borderRadius(8)
                .padding({ left: 20, right: 20 })
                .shadow(this.filterType === 0 ? { radius: 4, color: 'rgba(0,0,0,0.08)' } : null)
                .onClick(() => this.filterType = 0)
                .layoutWeight(1);

              Button('未完成')
                .height(34)
                .fontSize(14)
                .fontWeight(this.filterType === 1 ? FontWeight.Medium : FontWeight.Normal)
                .backgroundColor(this.filterType === 1 ? '#FAFAF8' : 'transparent')
                .fontColor(this.filterType === 1 ? THEME_COLOR : '#8E8E93')
                .borderRadius(8)
                .padding({ left: 20, right: 20 })
                .shadow(this.filterType === 1 ? { radius: 4, color: 'rgba(0,0,0,0.08)' } : null)
                .onClick(() => this.filterType = 1)
                .layoutWeight(1);

              Button('已完成')
                .height(34)
                .fontSize(14)
                .fontWeight(this.filterType === 2 ? FontWeight.Medium : FontWeight.Normal)
                .backgroundColor(this.filterType === 2 ? '#FAFAF8' : 'transparent')
                .fontColor(this.filterType === 2 ? THEME_COLOR : '#8E8E93')
                .borderRadius(8)
                .padding({ left: 20, right: 20 })
                .shadow(this.filterType === 2 ? { radius: 4, color: 'rgba(0,0,0,0.08)' } : null)
                .onClick(() => this.filterType = 2)
                .layoutWeight(1);
            }
            .width(`calc(100% - ${this.getContentPadding() * 2}vp)`)
            .height(44)
            .backgroundColor(this.isDarkTheme ? '#2C2C2E' : '#F2F0EC')
            .borderRadius(12)
            .padding(4)
            .margin({ bottom: 0 });
          }
          .width('100%')
          .height('100%')
          .backgroundColor(this.isDarkTheme ? '#1C1C1E' : '#F2F0EC')
          .alignItems(HorizontalAlign.Center);

          // 宠物浮窗
          Column() {
            Text(this.getStageEmoji())
              .fontSize(44)
              .scale({ x: this.petTapScale, y: this.petTapScale })
              .onClick(() => { this.onPetTap(); });
          }
          .padding(10)
          .backgroundColor('#FAFAF8')
          .borderRadius(30)
          .shadow({ radius: 12, color: 'rgba(0,0,0,0.15)' })
          .position({ x: '85%', y: '82%' })
          .onClick(() => { this.onPetTap(); });

        } else if (this.currentTabIndex === 1) {
          // ===== Tab 1: 宠物页面 =====
          PetPage({
            petData: this.petData
          })
        } else {
          // ===== Tab 2: 番茄钟 =====
          PomodoroPage({ })
        }

        // ---- 底部 TabBar ----
        Row({ space: 0 }) {
          Button() {
            Column() {
              Text('📋')
                .fontSize(22);
              Text('任务')
                .fontSize(10)
                .fontColor(this.currentTabIndex === 0 ? '#8AB4D6' : '#8E8E93');
            }
            .justifyContent(FlexAlign.Center)
            .height(48)
            .width('100%')
          }
          .height(48)
          .layoutWeight(1)
          .backgroundColor('transparent')
          .onClick(() => { this.currentTabIndex = 0; });

          Button() {
            Column() {
              Text('🐾')
                .fontSize(22);
              Text('宠物')
                .fontSize(10)
                .fontColor(this.currentTabIndex === 1 ? '#8AB4D6' : '#8E8E93');
            }
            .justifyContent(FlexAlign.Center)
            .height(48)
            .width('100%')
          }
          .height(48)
          .layoutWeight(1)
          .backgroundColor('transparent')
          .onClick(() => { this.currentTabIndex = 1; });

          Button() {
            Column() {
              Text('🍅')
                .fontSize(22);
              Text('番茄钟')
                .fontSize(10)
                .fontColor(this.currentTabIndex === 2 ? '#8AB4D6' : '#8E8E93');
            }
            .justifyContent(FlexAlign.Center)
            .height(48)
            .width('100%')
          }
          .height(48)
          .layoutWeight(1)
          .backgroundColor('transparent')
          .onClick(() => { this.currentTabIndex = 2; });
        }
        .width('100%')
        .height(56)
        .backgroundColor(this.isDarkTheme ? '#1C1C1E' : '#FAFAF8')
        .border({
          width: { top: 0.5 },
          color: '#E0DDD8'
        })
        .padding({ bottom: 8 });
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.isDarkTheme ? '#1C1C1E' : '#F2F0EC');

      // ---- 弹窗 ----
      if (this.showDatePicker) {
        Column() {
          Text(this.editingId === -1 ? '📝 添加任务' : '✏️ 编辑任务')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .margin({ bottom: 16 });

          TextInput({ text: this.inputText, placeholder: '输入任务内容...' })
            .width('100%')
            .height(44)
            .backgroundColor('#F2F0EC')
            .borderRadius(10)
            .padding({ left: 12 })
            .onChange((v: string) => this.inputText = v);

          Text('📅 截止日期')
            .fontSize(14)
            .fontColor('#8E8E93')
            .margin({ top: 12, bottom: 4 });

          DatePicker({
            start: new Date(2024, 0, 1),
            end: new Date(2035, 11, 31),
            selected: this.selectDeadline
          })
            .width('100%')
            .onChange((value: DatePickerResult) => {
              const year = value.year ?? this.selectDeadline.getFullYear();
              const month = value.month ?? this.selectDeadline.getMonth();
              const day = value.day ?? this.selectDeadline.getDate();
              if (year > 0 && month >= 0 && month <= 11 && day >= 1 && day <= 31) {
                this.selectDeadline = new Date(year, month, day);
              }
            });

          Row({ space: 10 }) {
            Button('取消')
              .width('45%')
              .height(44)
              .backgroundColor('#F2F0EC')
              .fontColor('#8E8E93')
              .fontSize(16)
              .borderRadius(10)
              .onClick(() => {
                this.showDatePicker = false;
                this.editingId = -1;
                this.inputText = '';
              });

            Button('确定')
              .width('45%')
              .height(44)
              .backgroundColor(THEME_COLOR)
              .fontColor(Color.White)
              .fontSize(16)
              .borderRadius(10)
              .onClick(() => {
                if (this.inputText.trim() === '') {
                  promptAction.showToast({ message: '请输入任务内容' });
                  return;
                }
                const d = this.selectDeadline;
                const deadlineStr = `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
                if (this.editingId === -1) {
                  let maxId = 0;
                  for (let i = 0; i < this.todoList.length; i++) {
                    if (this.todoList[i].id > maxId) maxId = this.todoList[i].id;
                  }
                  this.todoList.push({
                    id: maxId + 1,
                    content: this.inputText.trim(),
                    isCompleted: false,
                    priority: this.selectPriority,
                    deadline: deadlineStr,
                    deadTimeStamp: d.getTime()
                  });
                } else {
                  for (let i = 0; i < this.todoList.length; i++) {
                    if (this.todoList[i].id === this.editingId) {
                      this.todoList[i].content = this.inputText.trim();
                      this.todoList[i].priority = this.selectPriority;
                      this.todoList[i].deadline = deadlineStr;
                      this.todoList[i].deadTimeStamp = d.getTime();
                      break;
                    }
                  }
                }
                this.inputText = '';
                this.showDatePicker = false;
                this.editingId = -1;
                this.saveData();
                promptAction.showToast({ message: '✅ 保存成功' });
              });
          }
          .width('100%')
          .margin({ top: 16 });
        }
        .width(this.isTablet() ? '45%' : '85%')
        .padding(24)
        .backgroundColor(this.isDarkTheme ? '#1C1C1E' : '#FAFAF8')
        .borderRadius(16)
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.2)' })
        .position({ x: this.isTablet() ? '27.5%' : '7.5%', y: '20%' })
        .zIndex(10);
      }

      if (this.showDeleteDialog) {
        Column() {
          Text('⚠️ 确认删除')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .margin({ bottom: 8 });

          Text('确定要删除此任务吗？')
            .fontSize(15)
            .fontColor('#8E8E93')
            .margin({ bottom: 20 });

          Row({ space: 10 }) {
            Button('取消')
              .width('45%')
              .height(44)
              .backgroundColor('#F2F0EC')
              .fontColor('#8E8E93')
              .fontSize(16)
              .borderRadius(10)
              .onClick(() => {
                this.showDeleteDialog = false;
                this.currentDeleteId = -1;
              });

            Button('删除')
              .width('45%')
              .height(44)
              .backgroundColor('#D4A0A0')
              .fontColor(Color.White)
              .fontSize(16)
              .borderRadius(10)
              .onClick(() => this.confirmDelete());
          }
          .width('100%');
        }
        .width(this.isTablet() ? '35%' : '75%')
        .padding(24)
        .backgroundColor(this.isDarkTheme ? '#1C1C1E' : '#FAFAF8')
        .borderRadius(16)
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.2)' })
        .position({ x: this.isTablet() ? '32.5%' : '12.5%', y: '30%' })
        .zIndex(10);
      }
    }
    .width('100%')
    .height('100%')
  }
}
// ============================================================
//  PetPage 组件（内联到本文件，无需单独 import）
// ============================================================
interface PetData {
  name: string;
  stage: number;
  exp: number;
  mood: number;
  lastFeedTime: number;
  completedTasks: number;
  totalTasks: number;
}

@Component
struct PetPage {
  @Prop petData: PetData;

  getStageEmoji(): string {
    const emojis: Record<number, string> = { 0: '🥚', 1: '🐣', 2: '🐥', 3: '🦊', 4: '🔥' };
    return emojis[this.petData.stage] || '🥚';
  }

  getStageName(): string {
    const names: Record<number, string> = { 0: '蛋', 1: '幼年', 2: '成长', 3: '成年', 4: '传说' };
    return names[this.petData.stage] || '蛋';
  }

  getExpProgress(): number {
    const thresholds: Record<number, number> = { 0: 0, 1: 50, 2: 150, 3: 300, 4: 500 };
    const current: number = thresholds[this.petData.stage] || 0;
    const next: number = thresholds[this.petData.stage + 1] || 500;
    if (this.petData.stage >= 4) {
      return 100;
    }
    return Math.min(100, ((this.petData.exp - current) / (next - current)) * 100);
  }

  build() {
    Column() {
      Text(this.getStageEmoji())
        .fontSize(120)
        .margin({ top: 60 })
      Text(this.petData.name)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 16 })
      Text('阶段：' + this.getStageName())
        .fontSize(16)
        .fontColor('#8E8E93')
        .margin({ top: 4 })
      Column() {
        Row() {
          Text('经验 ' + this.petData.exp)
            .fontSize(14)
            .fontColor('#8E8E93')
          Blank()
          Text(Math.round(this.getExpProgress()) + '%')
            .fontSize(14)
            .fontColor('#8E8E93')
        }
        .width('100%')
        Progress({
          value: this.getExpProgress(),
          total: 100,
          type: ProgressType.Linear
        })
          .width('100%')
          .height(8)
          .color('#8AB4D6')
          .backgroundColor('#E0DDD8')
          .borderRadius(4)
          .margin({ top: 4 })
      }
      .width('80%')
      .margin({ top: 24 })
      Row() {
        this.StatItem('❤️ 心情', this.petData.mood + '%')
        this.StatItem('✅ 已完成', this.petData.completedTasks + '项')
        this.StatItem('📊 总任务', this.petData.totalTasks + '项')
      }
      .width('80%')
      .margin({ top: 30 })
      .justifyContent(FlexAlign.SpaceAround)
      Text(this.getMotivation())
        .fontSize(16)
        .fontColor('#8E8E93')
        .margin({ top: 40 })
        .textAlign(TextAlign.Center)
        .width('80%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F2F0EC')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  StatItem(label: string, value: string) {
    Column() {
      Text(value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#3A3A3C')
      Text(label)
        .fontSize(12)
        .fontColor('#8E8E93')
        .margin({ top: 2 })
    }
    .alignItems(HorizontalAlign.Center)
  }

  getMotivation(): string {
    const list: string[] = [
      '继续加油，你很棒！💪',
      '每天进步一点点！🌟',
      '坚持就是胜利！🏆',
      '你正在变得更强！⚡',
      '小乖为你骄傲！❤️'
    ];
    return list[this.petData.stage] || list[0];
  }
}

// ============================================================
//  PomodoroPage 组件 - 番茄钟（专注倒计时）
// ============================================================
@Component
struct PomodoroPage {
  @State pomodoroMinutes: number = 25;
  @State pomodoroSeconds: number = 0;
  @State pomodoroRunning: boolean = false;
  @State pomodoroPaused: boolean = false;
  @State pomodoroMode: string = 'focus';
  @State pomodoroCycles: number = 0;
  @State pomodoroTotalMinutes: number = 25;
  private timerId?: number = undefined;

  // ===== 计时器方法 =====
  startPomodoro(): void {
    if (this.pomodoroRunning) return;
    if (this.pomodoroPaused) {
      this.pomodoroPaused = false;
      this.pomodoroRunning = true;
      this.startTimer();
      return;
    }
    this.pomodoroMode = 'focus';
    this.pomodoroMinutes = 25;
    this.pomodoroSeconds = 0;
    this.pomodoroTotalMinutes = 25;
    this.pomodoroRunning = true;
    this.pomodoroPaused = false;
    this.startTimer();
    promptAction.showToast({ message: '🍅 专注计时开始！25分钟' });
  }

  pausePomodoro(): void {
    if (!this.pomodoroRunning) return;
    this.pomodoroRunning = false;
    this.pomodoroPaused = true;
    if (this.timerId !== undefined) {
      clearInterval(this.timerId);
      this.timerId = undefined;
    }
    promptAction.showToast({ message: '⏸️ 已暂停' });
  }

  resetPomodoro(): void {
    this.pomodoroRunning = false;
    this.pomodoroPaused = false;
    if (this.timerId !== undefined) {
      clearInterval(this.timerId);
      this.timerId = undefined;
    }
    this.pomodoroMode = 'focus';
    this.pomodoroMinutes = 25;
    this.pomodoroSeconds = 0;
    this.pomodoroTotalMinutes = 25;
    promptAction.showToast({ message: '🔄 已重置' });
  }

  startTimer(): void {
    this.timerId = setInterval(() => {
      if (this.pomodoroSeconds === 0) {
        if (this.pomodoroMinutes === 0) {
          this.onPomodoroComplete();
          return;
        }
        this.pomodoroMinutes--;
        this.pomodoroSeconds = 59;
      } else {
        this.pomodoroSeconds--;
      }
    }, 1000);
  }

  onPomodoroComplete(): void {
    if (this.timerId !== undefined) {
      clearInterval(this.timerId);
      this.timerId = undefined;
    }
    this.pomodoroRunning = false;
    this.pomodoroPaused = false;

    if (this.pomodoroMode === 'focus') {
      this.pomodoroCycles++;
      promptAction.showToast({ message: '🎉 专注完成！休息一下吧！' });
      this.pomodoroMode = 'break';
      this.pomodoroMinutes = 5;
      this.pomodoroSeconds = 0;
      this.pomodoroTotalMinutes = 5;
    } else {
      promptAction.showToast({ message: '🍅 休息结束！开始新的专注！' });
      this.pomodoroMode = 'focus';
      this.pomodoroMinutes = 25;
      this.pomodoroSeconds = 0;
      this.pomodoroTotalMinutes = 25;
    }
  }

  getPomodoroDisplay(): string {
    const mm = this.pomodoroMinutes.toString().padStart(2, '0');
    const ss = this.pomodoroSeconds.toString().padStart(2, '0');
    return `${mm}:${ss}`;
  }

  getPomodoroProgress(): number {
    const totalSec = this.pomodoroTotalMinutes * 60;
    const remainSec = this.pomodoroMinutes * 60 + this.pomodoroSeconds;
    if (totalSec === 0) return 0;
    return ((totalSec - remainSec) / totalSec) * 100;
  }

  build() {
    Column() {
      // 顶部标题栏
      Column() {
        Text('🍅 番茄钟')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .margin({ top: 48 });
        Text('专注当下，提高效率')
          .fontSize(14)
          .fontColor('rgba(255,255,255,0.7)')
          .margin({ top: 4 });
      }
      .width('100%')
      .padding({ bottom: 30 })
      .backgroundColor('#C4A882')
      .borderRadius({ bottomLeft: 30, bottomRight: 30 });

      Scroll() {
        Column() {
          // 模式指示
          Row({ space: 8 }) {
            Text('🎯 专注')
              .fontSize(14)
              .fontWeight(this.pomodoroMode === 'focus' ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.pomodoroMode === 'focus' ? '#C4A882' : '#9A9A9A')
              .padding({ left: 16, right: 16, top: 6, bottom: 6 })
              .backgroundColor(this.pomodoroMode === 'focus' ? 'rgba(255,107,53,0.1)' : 'transparent')
              .borderRadius(12);
            Text('☕ 休息')
              .fontSize(14)
              .fontWeight(this.pomodoroMode === 'break' ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.pomodoroMode === 'break' ? '#A0C4A0' : '#9A9A9A')
              .padding({ left: 16, right: 16, top: 6, bottom: 6 })
              .backgroundColor(this.pomodoroMode === 'break' ? 'rgba(52,199,89,0.1)' : 'transparent')
              .borderRadius(12);
          }
          .margin({ top: 24 });

          // 圆形倒计时
          Column() {
            Stack() {
              Progress({
                value: this.getPomodoroProgress(),
                total: 100,
                type: ProgressType.Ring
              })
                .width(220)
                .height(220)
                .value(this.getPomodoroProgress())
                .color(this.pomodoroMode === 'focus' ? '#C4A882' : '#A0C4A0');

              Column() {
                Text(this.getPomodoroDisplay())
                  .fontSize(56)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.pomodoroMode === 'focus' ? '#C4A882' : '#A0C4A0');

                Text(this.pomodoroMode === 'focus' ? '专注中...' : '休息中...')
                  .fontSize(14)
                  .fontColor('#8E8E93')
                  .margin({ top: 4 })
                  .opacity(this.pomodoroRunning ? 1 : 0);
              }
              .alignItems(HorizontalAlign.Center);
            }
            .width(220)
            .height(220)
            .margin({ top: 30 });
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center);

          // 控制按钮
          Row({ space: 20 }) {
            Button() {
              Text('🔄')
                .fontSize(20);
            }
            .width(56)
            .height(56)
            .backgroundColor('#F2F0EC')
            .borderRadius(28)
            .shadow({ radius: 4, color: 'rgba(0,0,0,0.08)' })
            .onClick(() => this.resetPomodoro());

            Button() {
              Text(this.pomodoroRunning ? '⏸️' : '▶️')
                .fontSize(28);
            }
            .width(72)
            .height(72)
            .backgroundColor(this.pomodoroRunning ? '#D4BFA0' : '#C4A882')
            .borderRadius(36)
            .shadow({ radius: 8, color: 'rgba(255,107,53,0.3)' })
            .onClick(() => {
              if (this.pomodoroRunning) {
                this.pausePomodoro();
              } else {
                this.startPomodoro();
              }
            });

            Button() {
              Text('  ')
                .fontSize(20);
            }
            .width(56)
            .height(56)
            .backgroundColor('transparent')
            .borderRadius(28);
          }
          .margin({ top: 32 });

          // 统计信息
          Row({ space: 30 }) {
            Column() {
              Text('🍅')
                .fontSize(24);
              Text(this.pomodoroCycles.toString())
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor('#3A3A3C');
              Text('已完成')
                .fontSize(12)
                .fontColor('#8E8E93')
                .margin({ top: 2 });
            }
            .alignItems(HorizontalAlign.Center);

            Column() {
              Text('⏱️')
                .fontSize(24);
              Text(this.pomodoroMode === 'focus' ? '25分钟' : '5分钟')
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor('#3A3A3C');
              Text('单次时长')
                .fontSize(12)
                .fontColor('#8E8E93')
                .margin({ top: 2 });
            }
            .alignItems(HorizontalAlign.Center);

            Column() {
              Text('🏆')
                .fontSize(24);
              Text(this.pomodoroCycles > 0 ? (this.pomodoroCycles * 25) + '分钟' : '0分钟')
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor('#3A3A3C');
              Text('总专注')
                .fontSize(12)
                .fontColor('#8E8E93')
                .margin({ top: 2 });
            }
            .alignItems(HorizontalAlign.Center);
          }
          .margin({ top: 40, bottom: 24 })
          .padding(20)
          .backgroundColor('#FAFAF8')
          .borderRadius(16)
          .shadow({ radius: 4, color: 'rgba(0,0,0,0.06)' });

          // 番茄工作法说明
          Column({ space: 6 }) {
            Text('💡 番茄工作法')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#3A3A3C');

            Text('• 专注工作 25 分钟')
              .fontSize(13)
              .fontColor('#8E8E93');
            Text('• 休息 5 分钟')
              .fontSize(13)
              .fontColor('#8E8E93');
            Text('• 每 4 个番茄钟休息 15-30 分钟')
              .fontSize(13)
              .fontColor('#8E8E93');
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(16)
          .backgroundColor('#F8F9FA')
          .borderRadius(12)
          .margin({ top: 8, bottom: 80 });
        }
        .width('90%')
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ top: 8 });
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F2F0EC')
  }
}