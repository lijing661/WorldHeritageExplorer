我们要完成一个名为 “世界⽂化遗产”的App。下面我们设计了⼀套完整的技术架构和⽂件组织⽅案，兼顾功能实
现、性能优化和可扩展性。
⼀、技术栈选择
1. 本地数据库
推荐使⽤ Core Data（iOS 原⽣框架）：
优势：与 SwiftUI/UIKit 深度集成，⽀持复杂查询（符合你的多条件筛选需求）、数据持久化（⽆
需担⼼ App 重启后丢失favorite/checked状态），且性能稳定。
2. CSV 数据解析
使⽤ CSV.swift（第三⽅库，通过 CocoaPods 集成）：
作⽤：快速解析 1248 条 CSV 数据，转换为模型对象后存⼊ Core Data。
优势：处理⼤量 CSV 数据时⽐⼿动分割字符串更⾼效，⽀持表头映射。
3. ⽹络图⽚加载与缓存
使⽤ Kingfisher（第三⽅库）：
作⽤：加载 CSV 中提供的main image URL和gallery images URL，⾃动缓存图⽚到本地
（避免重复⽹络请求）。
优势：⽀持占位图、加载动画、缓存管理，适配 SwiftUI/UIKit，性能优异。
4. 地图展示
使⽤ MapKit（iOS 原⽣框架）：
作⽤：显示地图并标注遗产位置，⽀持⾃定义图标（按 “⽂化 / ⾃然 / 混合” 类型区分）。
优势：⽆需集成第三⽅ SDK（如⾼德 / 百度），原⽣⽀持经纬度标注、地图缩放、路径规划等基础
功能。
5. UI 框架
推荐 SwiftUI：
优势：声明式语法，快速搭建列表、地图、详情⻚等界⾯，且与 Core Data、MapKit 的集成更简
洁（相⽐ UIKit 代码量更少）。
适⽤场景：你的 App 以展示和交互为主（列表、筛选、地图标注），SwiftUI ⾜以胜任，开发效率
更⾼。
⼆、数据模型设计（Core Data）
需要创建⼀个Heritage实体，包含以下属性（结合 CSV 字段 + ⾃定义状态）：
属性名 类型 说明
name String 遗产名称（CSV 字段）
country String 所属国家（CSV 字段，⽤于筛选）
region String 所属地区（CSV 字段）
year Int16 ⼊选年份（CSV 字段，⽤于筛选）
latitude Double 纬度（CSV 字段，地图标注⽤）
longitude Double 经度（CSV 字段，地图标注⽤）
category String 类型（⽂化 / ⾃然 / 混合，CSV 字段，⽤于筛选和图
标区分）
shortDescripti
on String 简短描述（CSV 字段）
mainImageURL String 主图 URL（CSV 字段）
galleryImageUR
Ls String 画廊图⽚ URLs（CSV 字段，多个 URL ⽤逗号分
隔）
isFavorite Bool 是否收藏（⾃定义，默认 false）
isChecked Bool 是否已访问（⾃定义，默认 false）
uniqueID String 唯⼀标识（CSV 中若有 ID 则⽤，⽆则⽣成）
三、⽂件架构设计
按 “功能模块 + 职责分层” 组织，确保代码清晰可维护：
WorldHeritageApp/
├── Sources/ # 代码⽂件
│ ├── Data/ # 数据层：处理数据解析、存储、读取
│   ├── CoreData/
│   │   ├── Persistence.swift  # 替代 CoreDataManager，负责数据库初始化和上下文管理
│   │   ├── Heritage+CoreDataClass.swift  # Core Data 实体类（自动生成，可扩展）
│   │   └── Heritage+CoreDataProperties.swift  # 实体属性扩展（自动生成）
│   ├── CSVParser.swift  # 解析 CSV 数据
│   └── DataInitializer.swift  # 调用 CSVParser 和 Persistence，将数据导入 Core Data
│ ├── Models/ # 模型层：数据模型和业务逻辑
│ │ ├── Heritage.swift # 遗产数据模型（与Core Data实体映射）
│ │ └── FilterOptions.swift # 筛选条件模型（国家/年份/类型）
│ ├── Services/ # 服务层：提供图⽚加载、⼯具等通⽤服务
│ │ ├── ImageService.swift # 图⽚加载服务（封装Kingfisher）
│ │ └── LocationService.swift # 位置⼯具（经纬度转换等）
│ ├── UI/ # 界⾯层：所有视图和视图模型
│ │ ├── Tabs/ # 底部标签⻚
│ │ │ ├── ListView.swift # 遗产列表⻚
│ │ │ ├── MapView.swift # 地图⻚
│ │ │ └── MyHeritageView.swift # 我的收藏/已访问⻚
│ │ ├── Components/ # 通⽤UI组件
│ │ │ ├── HeritageCard.swift # 列表中的遗产卡⽚
│ │ │ ├── FilterSheet.swift # 筛选弹窗
│ │ │ └── MapAnnotationView.swift # 地图⾃定义标注
│ │ ├── Detail/ # 详情⻚
│ │ │ └── HeritageDetailView.swift # 遗产详情⻚
│ │ └── ViewModels/ # 视图模型（管理UI数据和交互）
│ │ ├── ListViewModel.swift
│ │ ├── MapViewModel.swift
│ │ └── DetailViewModel.swift
│ └── AppEntry/ # App⼊⼝
│ ├── AppDelegate.swift # ⽣命周期管理（Core Data初始化）
│ └── WorldHeritageApp.swift # SwiftUI⼊⼝
├── Resources/ # 资源⽂件
│ ├── Assets.xcassets # 图⽚资源
│ │ ├── Icons/ # ⾃定义图标（收藏/已访问按钮、地图标注图标）
│ │ │ ├── favorite_filled.png
│ │ │ ├── checked_filled.png
│ │ │ ├── culture_pin.png # ⽂化遗产标注
│ │ │ ├── nature_pin.png # ⾃然遗产标注
│ │ │ └── mixed_pin.png # 混合遗产标注
│ │ └── Placeholders/ # 图⽚加载占位图
│ ├── CSV/ # CSV数据⽂件
│ │ └── world_heritage_data.csv # 从UNESCO下载的原始数据
│ └── Localizable.strings # 多语⾔⽂本（可选）
├── Info.plist # 项⽬配置
├── WorldHeritageApp.xcodeproj # 项⽬⽂件
└── Podfile # 依赖管理（CSV.swift、Kingfisher）
四、核⼼功能实现流程
1. 数据初始化（⾸次启动）
⽤户⾸次打开 App 时，DataInitializer 读取 Resources/CSV/
world_heritage_data.csv，通过CSV.swift解析为Heritage模型数组。
调⽤CoreDataManager将模型数组存⼊本地数据库（⾃动添加isFavorite和isChecked默认
值false）。
2. 列表⻚（带筛选）
ListViewModel 从 Core Data 查询所有遗产，⽀持按country（国家）、year（年份）、
category（类型）筛选（通过 Core Data 的NSPredicate实现）。
筛选条件通过FilterSheet弹窗选择，选择后刷新列表。
列表项使⽤HeritageCard展示缩略图（通过ImageService加载mainImageURL）、名称、国
家、年份。
3. 地图⻚
MapViewModel 从 Core Data 获取所有遗产的经纬度和类型，传递给MapView。
MapView 使⽤MapKit的Map组件，通过Annotation标注每个遗产位置，根据category显示不
同图标（culture_pin/nature_pin/mixed_pin）。
点击标注弹出简要信息，点击可跳转到详情⻚。
4. 详情⻚
接收选中的遗产 ID，DetailViewModel 从 Core Data 查询该遗产的完整信息。
展示mainImage（Kingfisher 加载）、shortDescription、year、category等信息。
提供 “收藏”（isFavorite）和 “已访问”（isChecked）按钮，点击后通过CoreDataManager
更新状态。
5. “我的遗产” ⻚
按isFavorite和isChecked筛选 Core Data 数据，分别展示 “收藏列表” 和 “已访问列表”（可通
过分段控件切换）。
五、关于 UI 设计
⼼布局：
是否需要原型图？ 不是必须，但建议先画简易原型（可⽤ Figma、Sketch 或纸笔），确定以下核
底部标签栏的 3 个⻚⾯（列表 / 地图 / 我的）如何切换；
列表⻚的筛选按钮位置（如顶部导航栏右侧）和筛选弹窗样式；
详情⻚的信息排版（主图在上，⽂字在下，按钮在底部等）；
地图标注的弹窗样式和交互逻辑。
有了原型后，可更清晰地规划UI/Components中的复⽤组件，避免开发中频繁调整布局。
六、依赖配置（Podfile）
platform :ios, '16.0'
use_frameworks!
target 'WorldHeritageApp' do
pod 'CSV.swift', '~> 2.4' # CSV解析
pod 'Kingfisher', '~> 7.0' # 图⽚加载
end
这套架构兼顾了数据处理、UI 交互和性能需求，1248 条数据量不⼤，Core Data 和 Kingfisher ⾜以保证流
畅体验。开发时可按 “数据初始化→列表⻚→详情⻚→地图⻚→我的⻚⾯” 的顺序逐步实现，每完成⼀个模
块就测试⼀次，降低集成⻛险。