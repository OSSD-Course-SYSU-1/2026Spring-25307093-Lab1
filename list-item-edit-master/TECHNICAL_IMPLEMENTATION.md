# 技术实现细节文档

## 架构设计

### 1. 整体架构
```
┌─────────────────────────────────────────────┐
│                  UI层                        │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐      │
│  │  页面   │ │  组件   │ │  布局   │      │
│  └─────────┘ └─────────┘ └─────────┘      │
└─────────────────────────────────────────────┘
                    │
┌─────────────────────────────────────────────┐
│              业务逻辑层                      │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐      │
│  │状态管理 │ │事件处理 │ │业务规则 │      │
│  └─────────┘ └─────────┘ └─────────┘      │
└─────────────────────────────────────────────┘
                    │
┌─────────────────────────────────────────────┐
│               数据层                        │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐      │
│  │KVStore  │ │AppStorage│ │内存缓存 │      │
│  └─────────┘ └─────────┘ └─────────┘      │
└─────────────────────────────────────────────┘
```

### 2. 核心模块

#### 2.1 数据模型
```typescript
// 待办事项数据模型
interface TodoItem {
  id: number;           // 唯一标识
  content: string;      // 任务内容
  isCompleted: boolean; // 完成状态
  priority: number;     // 优先级 (1-低, 2-中, 3-高)
  deadline: string;     // 截止日期字符串
  deadTimeStamp: number; // 时间戳
}

// 宠物数据模型
interface PetData {
  name: string;         // 宠物名称
  stage: number;        // 成长阶段
  exp: number;          // 经验值
  mood: number;         // 心情值 (0-100)
  lastFeedTime: number; // 最后喂食时间
  completedTasks: number; // 完成任务数
  totalTasks: number;   // 总任务数
}
```

#### 2.2 状态管理
```typescript
@Entry
@Component
struct TodoList {
  @State todoList: TodoItem[] = [];      // 待办事项列表
  @State inputText: string = '';         // 输入框文本
  @State editingId: number = -1;         // 正在编辑的ID
  @State filterType: number = 0;         // 过滤类型
  @State showDeleteDialog: boolean = false; // 删除对话框
  @State currentDeleteId: number = -1;   // 当前删除ID
  @State isDarkTheme: boolean = false;   // 主题模式
  @State selectPriority: number = 2;     // 选择优先级
  @State searchKey: string = '';         // 搜索关键词
  @State showSearch: boolean = false;    // 显示搜索
  @State showMenu: boolean = false;      // 显示菜单
  @State showDatePicker: boolean = false; // 显示日期选择器
  @State currentFontSize: number = 16;   // 字体大小
  @State selectDeadline: Date = new Date(); // 选择截止日期
  
  @State currentBreakpoint: number = 0;  // 当前断点
  @State currentTabIndex: number = 0;    // 当前标签页
  
  @State petData: PetData = DEFAULT_PET; // 宠物数据
  @State petTapScale: number = 1;        // 宠物点击动画
  
  @State pomodoroPlaceholder: number = 0; // 番茄钟占位
}
```

## 关键技术实现

### 1. 分布式数据存储

#### 1.1 KVStore初始化
```typescript
async initKVStore(): Promise<void> {
  try {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const config: distributedKVStore.KVManagerConfig = { 
      context, 
      bundleName: context.applicationInfo.name 
    };
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
```

#### 1.2 数据持久化
```typescript
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
```

### 2. 响应式布局系统

#### 2.1 断点定义
```typescript
const BREAKPOINT_XS = 0;  // 手机 (< 520vp)
const BREAKPOINT_SM = 1;  // 大手机 (520-600vp)
const BREAKPOINT_MD = 2;  // 折叠屏 (600-840vp)
const BREAKPOINT_LG = 3;  // 平板 (≥ 840vp)
```

#### 2.2 屏幕适配
```typescript
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
```

### 3. 宠物养成系统

#### 3.1 宠物成长逻辑
```typescript
// 完成任务时更新宠物经验
onTaskComplete(): void {
  this.petData.exp += 10;
  this.petData.completedTasks += 1;
  this.petData.totalTasks += 1;
  
  // 检查是否升级
  if (this.petData.exp >= 100 && this.petData.stage === 0) {
    this.petData.stage = 1;
    this.petData.exp = 0;
    promptAction.showToast({ message: "🎉 宠物进化了！" });
  } else if (this.petData.exp >= 200 && this.petData.stage === 1) {
    this.petData.stage = 2;
    this.petData.exp = 0;
    promptAction.showToast({ message: "🌟 宠物再次进化！" });
  }
  
  this.savePetData();
}

// 喂食宠物
feedPet(): void {
  this.petData.mood = Math.min(100, this.petData.mood + 20);
  this.petData.lastFeedTime = Date.now();
  this.savePetData();
  promptAction.showToast({ message: "🍖 宠物吃饱了，心情变好了！" });
}

// 检查宠物心情衰减
checkPetMood(): void {
  const now = Date.now();
  const hoursSinceLastFeed = (now - this.petData.lastFeedTime) / (1000 * 60 * 60);
  
  if (hoursSinceLastFeed > 4) {
    this.petData.mood = Math.max(0, this.petData.mood - 10);
    this.savePetData();
  }
}
```

### 4. 数据迁移功能

#### 4.1 迁移数据接收
```typescript
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
```

#### 4.2 迁移数据发送
```typescript
onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
  try {
    wantParam[MIGRATION_KEY_TODOLIST] = JSON.stringify(this.todoList);
    wantParam[MIGRATION_KEY_FILTER] = this.filterType;
    return AbilityConstant.OnContinueResult.AGREE;
  } catch (error) {
    return AbilityConstant.OnContinueResult.REJECT;
  }
}
```

## 性能优化

### 1. 列表渲染优化
```typescript
// 使用LazyForEach优化长列表
LazyForEach(
  this.filteredTodos,
  (item: TodoItem) => item.id.toString(),
  (item: TodoItem) => {
    TodoListItem({
      todo: item,
      onToggle: () => this.toggleTodo(item.id),
      onEdit: () => this.startEdit(item.id),
      onDelete: () => this.showDeleteConfirm(item.id),
      fontSize: this.currentFontSize
    })
  }
)
```

### 2. 状态管理优化
```typescript
// 使用@State装饰器实现响应式更新
@State todoList: TodoItem[] = [];

// 使用计算属性减少重复计算
get filteredTodos(): TodoItem[] {
  if (this.searchKey.trim() !== '') {
    return this.todoList.filter(item => 
      item.content.toLowerCase().includes(this.searchKey.toLowerCase())
    );
  }
  
  switch (this.filterType) {
    case 1: return this.todoList.filter(item => !item.isCompleted);
    case 2: return this.todoList.filter(item => item.isCompleted);
    default: return this.todoList;
  }
}
```

### 3. 内存管理
```typescript
// 及时清理不需要的引用
aboutToDisappear(): void {
  if (this.kvStore) {
    this.kvStore.off('dataChange');
  }
}

// 使用弱引用避免内存泄漏
private weakRefMap: WeakMap<Object, any> = new WeakMap();
```

## 错误处理

### 1. 网络错误处理
```typescript
async saveDataWithRetry(maxRetries: number = 3): Promise<void> {
  for (let i = 0; i < maxRetries; i++) {
    try {
      await this.saveData();
      return;
    } catch (error) {
      if (i === maxRetries - 1) {
        console.error('保存数据失败，已达到最大重试次数: ' + JSON.stringify(error));
        promptAction.showToast({ message: '保存失败，请检查网络连接' });
      } else {
        await new Promise(resolve => setTimeout(resolve, 1000 * (i + 1)));
      }
    }
  }
}
```

### 2. 数据验证
```typescript
validateTodoItem(item: TodoItem): boolean {
  if (!item.content || item.content.trim() === '') {
    promptAction.showToast({ message: '任务内容不能为空' });
    return false;
  }
  
  if (item.priority < 1 || item.priority > 3) {
    promptAction.showToast({ message: '优先级必须在1-3之间' });
    return false;
  }
  
  if (item.deadTimeStamp < Date.now()) {
    promptAction.showToast({ message: '截止日期不能早于当前时间' });
    return false;
  }
  
  return true;
}
```

## 安全考虑

### 1. 数据安全
- 使用KVStore的安全等级S1
- 敏感数据不存储在本地
- 用户数据加密存储

### 2. 权限管理
```json
{
  "module": {
    "requestPermissions": [
      {
        "name": "ohos.permission.NOTIFICATION"
      }
    ]
  }
}
```

### 3. 输入验证
```typescript
sanitizeInput(input: string): string {
  // 移除危险字符
  return input.replace(/[<>'"&]/g, '');
}
```

## 测试策略

### 1. 单元测试
```typescript
// 待办事项测试
describe('TodoList', () => {
  it('should add todo item', () => {
    const todoList = new TodoList();
    todoList.addTodo('Test task', 2, new Date());
    expect(todoList.todoList.length).toBe(1);
  });
  
  it('should toggle todo status', () => {
    const todoList = new TodoList();
    todoList.addTodo('Test task', 2, new Date());
    todoList.toggleTodo(0);
    expect(todoList.todoList[0].isCompleted).toBe(true);
  });
});
```

### 2. 集成测试
- 测试数据持久化
- 测试宠物系统集成
- 测试番茄钟功能
- 测试多设备适配

### 3. 性能测试
- 内存使用监控
- 响应时间测试
- 大数据量测试

## 部署指南

### 1. 构建配置
```json5
// build-profile.json5
{
  "app": {
    "signingConfigs": [],
    "products": [
      {
        "name": "default",
        "signingConfig": "default",
        "compileSdkVersion": 5,
        "compatibleSdkVersion": 5,
        "runtimeOS": "HarmonyOS"
      }
    ],
    "buildModeSet": ["debug", "release"]
  }
}
```

### 2. 发布流程
1. 开发环境构建
2. 测试环境部署
3. 生产环境发布
4. 监控和日志收集

## 监控和维护

### 1. 日志记录
```typescript
// 统一日志记录
class Logger {
  static info(message: string, data?: any): void {
    console.info(`[INFO] ${message}`, data || '');
  }
  
  static error(message: string, error?: any): void {
    console.error(`[ERROR] ${message}`, error || '');
  }
  
  static warn(message: string, data?: any): void {
    console.warn(`[WARN] ${message}`, data || '');
  }
}
```

### 2. 性能监控
- 监控应用启动时间
- 监控内存使用情况
- 监控网络请求性能
- 监控用户操作响应时间

## 故障排除

### 1. 常见问题
1. **数据不同步**: 检查网络连接和KVStore配置
2. **宠物不显示**: 检查宠物数据加载和初始化
3. **番茄钟不工作**: 检查通知权限和定时器设置
4. **布局错乱**: 检查屏幕适配逻辑和断点设置

### 2. 调试工具
- DevEco Studio调试器
- 日志查看器
- 性能分析工具
- 网络调试工具

## 版本兼容性

### 1. 向后兼容
- 支持HarmonyOS 5.0.5及以上版本
- 数据格式向后兼容
- API调用兼容性检查

### 2. 向前兼容
- 使用特性检测
- 优雅降级策略
- 版本迁移工具

---
*文档最后更新: 2026年6月23日*
*版本: v1.1.0*