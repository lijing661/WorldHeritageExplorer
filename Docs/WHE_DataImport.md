目标与策略
1. 导入阶段
   - 严格按 CSV 写入；遇到空值直接置 nil.
   - 统计缺失清单（needsImage/needsGallery/needsCoordinates）仅用于任务队列，不必落库字段。
2. 异步富化任务（首次导入完成后后台执行)
   - 任务队列选取缺失项，按来源优先级尝试：
   - 数据源优先级：Wikidata → Wikipedia →  Wikimedia  Commons（坐标与图片）→ 最后兜底 CLGeocoder（仅坐标）.
   		* 坐标：Wikidata P625 → UNESCO → CLGeocoder。
        * 主图：Wikidata P18 → Wikipedia PageImages → Commons 类别首图。
        * 图集：Commons 类别前 3-5 张 → Wikipedia images API。
   - 导入期：缺失字段写入 nil，不填 0 或占位字符串。
   - 富化期：首次导入完成后自动后台运行；逐条补齐，一项成功即保存；记录 enrichedAt、dataSource、imageLicense。

需要的最小模型变更（Core Data，可选字段）
 - enrichedAt: Date
 - dataSource: String（如“wikidata|wikipedia|commons|clgeocoder”）
 - imageLicense: String（存放简名或“CC BY-SA 4.0｜https://...”）
 - 建议顺便加 wikidataQID: String 与 commonsCategory: String（命中率与后续维护更稳）。

富化流程（后台任务）
 1. 识别对象：筛选 mainImageURL 为空、galleryImageURLs 为空、或坐标为空的记录。
 2. 解析 QID：
   * Wikidata search API（wbsearchentities）用英文名+国家，优先过滤实例为“世界遗产”（Q9259）。
   * 若先命中 Wikipedia，再从 pageprops 拿 QID。
 3. 坐标：
   * Wikidata P625 → 若无，用 UNESCO 校验（若可用）→ 兜底 CLGeocoder（标记 dataSource=clgeocoder）。
 4. 主图：
   * Wikidata P18 → Commons imageinfo 拿缩略图与 extmetadata（取 License）。
   * 若无，用 Wikipedia PageImages/REST Summary 取缩略图（大多也回到 Commons）。
 5. 图集：
   * Wikidata P373 或从描述中推断 Commons 类别 → Commons categorymembers 取前 N 张，落到 galleryImageURLs。
 6. 保存：
  * 每条成功更新字段即保存；写入 enrichedAt、dataSource、imageLicense（若获取到）。
 7. 运行策略：
  * 并发 2–4；失败重试有限次；内存/磁盘缓存 QID 与已解析图片，避免重复请求。

UI
 - 不显示版权与署名；缺图用占位图；坐标为地理编码结果时可在详情做“估算”标记（可选）。

后续实施顺序
 1. 轻量迁移：给 Heritage 增加 enrichedAt、dataSource、imageLicense（建议再加 wikidataQID、commonsCategory）。
 2. 新建 EnrichmentService：封装上述 API 调用与限流、缓存。
 3. 在首次 CSV 导入完成后自动触发富化任务（后台），并在 App 生命周期里注入。