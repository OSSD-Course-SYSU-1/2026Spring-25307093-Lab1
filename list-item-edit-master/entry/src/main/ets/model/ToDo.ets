// ============================================================
//  PetData 接口定义（只定义一次，在最顶部）
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

// ============================================================
//  导入
// ============================================================
import common from '@ohos.app.ability.common';
import promptAction from '@ohos.promptAction';
import distributedKVStore from '@ohos.data.distributedKVStore';
import display from '@ohos.display';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { AbilityConstant, Want } from '@kit.AbilityKit';

// ============================================================
//  常量
// ============================================================
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

const THEME_COLOR = '#007AFF';

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

// ============================================================
//  TodoList 主组件
// ============================================================
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
    if (level === PRIORITY_HIGH) return '#FF3B30';
    if (level === PRIORITY_MID) return '#FF9500';
    return '#34C759';
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
                .fontColor('#FF3B30');
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
        .fontColor('#FF3B30')
        .onClick(() => {
          this.currentDeleteId = item.id;
          this.showDeleteDialog = true;
        });
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.isDarkTheme ? '#2C2C2E' : '#FFFFFF')
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
            .backgroundColor('#007AFF')
            .borderRadius({ bottomLeft: 24, bottomRight: 24 });

            // 搜索框
            if (this.showSearch) {
              TextInput({ text: this.searchKey, placeholder: '🔍 搜索任务...' })
                .width(`calc(100% - ${this.getContentPadding() * 2}vp)`)
                .height(40)
                .backgroundColor(this.isDarkTheme ? '#2C2C2E' : '#F2F2F7')
                .borderRadius(10)
                .margin({ left: this.getContentPadding(), right: this.getContentPadding(), top: 12, bottom: 8 })
                .onChange((v: string) => this.searchKey = v);
            }

            // 菜单
            if (this.showMenu) {
              Column({ space: 4 }) {
                Button('🌙 切换主题').width('100%').height(40).backgroundColor('#555').fontColor(Color.White).onClick(() => { this.isDarkTheme = !this.isDarkTheme; this.saveData(); this.showMenu = false; });
                Button(`🔤 字体 (${this.currentFontSize}px)`).width('100%').height(40).backgroundColor('#555').fontColor(Color.White).onClick(() => { this.changeFontSize(); this.showMenu = false; });
                Button('🗑️ 清空已完成').width('100%').height(40).backgroundColor('#FF9500').fontColor(Color.White).onClick(() => { this.clearCompletedTask(); this.showMenu = false; });
                Button('⚠️ 清空全部').width('100%').height(40).backgroundColor('#FF3B30').fontColor(Color.White).onClick(() => { this.clearAllTask(); this.showMenu = false; });
              }
              .width(this.isTablet() ? '40%' : '75%')
              .backgroundColor(this.isDarkTheme ? '#1C1C1E' : '#FFFFFF')
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
                .backgroundColor(this.selectPriority === PRIORITY_LOW ? '#34C759' : 'transparent')
                .fontColor(this.selectPriority === PRIORITY_LOW ? '#FFFFFF' : '#8E8E93')
                .borderRadius(15)
                .padding({ left: 14, right: 14 })
                .onClick(() => this.selectPriority = PRIORITY_LOW);

              Button('⬤ 中')
                .height(30)
                .fontSize(13)
                .backgroundColor(this.selectPriority === PRIORITY_MID ? '#FF9500' : 'transparent')
                .fontColor(this.selectPriority === PRIORITY_MID ? '#FFFFFF' : '#8E8E93')
                .borderRadius(15)
                .padding({ left: 14, right: 14 })
                .onClick(() => this.selectPriority = PRIORITY_MID);

              Button('⬤ 高')
                .height(30)
                .fontSize(13)
                .backgroundColor(this.selectPriority === PRIORITY_HIGH ? '#FF3B30' : 'transparent')
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
                  .fontColor('#1C1C1E')
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
                .backgroundColor(this.filterType === 0 ? '#FFFFFF' : 'transparent')
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
                .backgroundColor(this.filterType === 1 ? '#FFFFFF' : 'transparent')
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
                .backgroundColor(this.filterType === 2 ? '#FFFFFF' : 'transparent')
                .fontColor(this.filterType === 2 ? THEME_COLOR : '#8E8E93')
                .borderRadius(8)
                .padding({ left: 20, right: 20 })
                .shadow(this.filterType === 2 ? { radius: 4, color: 'rgba(0,0,0,0.08)' } : null)
                .onClick(() => this.filterType = 2)
                .layoutWeight(1);
            }
            .width(`calc(100% - ${this.getContentPadding() * 2}vp)`)
            .height(44)
            .backgroundColor(this.isDarkTheme ? '#2C2C2E' : '#F2F2F7')
            .borderRadius(12)
            .padding(4)
            .margin({ bottom: this.isTablet() ? 24 : 12 });
          }
          .width('100%')
          .height('100%')
          .backgroundColor(this.isDarkTheme ? '#1C1C1E' : '#F2F2F7')
          .alignItems(HorizontalAlign.Center);

          // 宠物浮窗
          Column() {
            Text(this.getStageEmoji())
              .fontSize(44)
              .scale({ x: this.petTapScale, y: this.petTapScale })
              .onClick(() => { this.onPetTap(); });
          }
          .padding(10)
          .backgroundColor('#FFFFFF')
          .borderRadius(30)
          .shadow({ radius: 12, color: 'rgba(0,0,0,0.15)' })
          .position({ x: '85%', y: '82%' })
          .onClick(() => { this.onPetTap(); });

        } else {
          // ===== Tab 1: 宠物页面 =====
          PetPage({ petData: this.petData })
        }

        // ---- 底部 TabBar ----
        Row({ space: 0 }) {
          Button() {
            Column() {
              Text('📋')
                .fontSize(22);
              Text('任务')
                .fontSize(10)
                .fontColor(this.currentTabIndex === 0 ? '#007AFF' : '#8E8E93');
            }
          }
          .height(50)
          .layoutWeight(1)
          .backgroundColor('transparent')
          .onClick(() => { this.currentTabIndex = 0; });

          Button() {
            Column() {
              Text('🐾')
                .fontSize(22);
              Text('宠物')
                .fontSize(10)
                .fontColor(this.currentTabIndex === 1 ? '#007AFF' : '#8E8E93');
            }
          }
          .height(50)
          .layoutWeight(1)
          .backgroundColor('transparent')
          .onClick(() => { this.currentTabIndex = 1; });
        }
        .width('100%')
        .height(56)
        .backgroundColor(this.isDarkTheme ? '#1C1C1E' : '#FFFFFF')
        .border({
          width: { top: 0.5 },
          color: '#E5E5EA'
        })
        .padding({ bottom: 8 });
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.isDarkTheme ? '#1C1C1E' : '#F2F2F7');

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
            .backgroundColor('#F2F2F7')
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
              .backgroundColor('#F2F2F7')
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
        .backgroundColor(this.isDarkTheme ? '#1C1C1E' : '#FFFFFF')
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
              .backgroundColor('#F2F2F7')
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
              .backgroundColor('#FF3B30')
              .fontColor(Color.White)
              .fontSize(16)
              .borderRadius(10)
              .onClick(() => this.confirmDelete());
          }
          .width('100%');
        }
        .width(this.isTablet() ? '35%' : '75%')
        .padding(24)
        .backgroundColor(this.isDarkTheme ? '#1C1C1E' : '#FFFFFF')
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
//  PetPage 组件（内联在同一个文件，无需单独 import）
// ============================================================
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
          .color('#007AFF')
          .backgroundColor('#E5E5EA')
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
    .backgroundColor('#F2F2F7')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  StatItem(label: string, value: string) {
    Column() {
      Text(value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1C1C1E')
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