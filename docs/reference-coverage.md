# PM4Py 参照范围、能力对应与独立验证

## 参照关系

MoonProcessLens 0.2.0 以成熟流程挖掘库
[PM4Py](https://github.com/process-intelligence-solutions/pm4py) 的能力划分和公开
API 作为工程参照，独立测试固定使用实际发布的 **PM4Py 2.7.23**。
`scripts/compare_pm4py.py` 导入它真实的 Petri 网、Alpha、执行语义、对齐及
XES/PNML/BPMN API，不用自写模拟器冒充成熟库。Python 依赖只用于开发期测试。

这里的“参照完整的成熟工具”指参照对象是真实软件，不表示本项目完整移植、
测试或替代 PM4Py；没有安装并验证全部可选 extras，也不宣称穷尽其算法目录。
[PM4Py 官方能力说明](https://processintelligence.solutions/pm4py/) 展示的范围
还包括预测、对象中心分析等。本项目选择可独立嵌入 MoonBit 的模型分析计算层。

## 功能对应矩阵

| 成熟工具中的能力方向 | 本库实际入口 | 证据与差异 |
| --- | --- | --- |
| 活动、DFG 与变体统计 | `EventLog::discover` | 独立 MoonBit 单测与业务示例；没有把 DFG 计为可执行模型发现，也没有宣称已与 PM4Py 对照全部统计项 |
| Alpha 过程发现 | `discover_alpha` | 实际调用 PM4Py classical Alpha；并行训练及 6 个正反轨迹成本对照。经典假设、16 活动上限，拒绝观测短循环；非 Alpha+ 或噪声鲁棒发现 |
| 精确有限语言接受模型 | `discover_prefix_net` | 共享前缀、允许重复标签与终结前缀；自建单测，不宣称 PM4Py 同名算法逐项等价或未知行为泛化 |
| Petri 网执行 | `PetriNet::new/enabled/fire` | 普通带权 P/T，含静默迁移、明确初始/终止标识；另以 PM4Py 加权执行枚举 AAB 语言，与 121 个轨迹距离对照 |
| 基于模型的最优对齐 | `CaseTrace::align_net`、`EventLog::align_net` | PM4Py Dijkstra 与本库乘积搜索：顺序、XOR、AND、循环四模型共 484 个成本一致；不是仅比参考路径编辑距离 |
| 模型行为与完成性 | `PetriNet::analyze` | 可达图及反向完成可达，检查死锁、剩余令牌、未观察迁移；独立单测，非 PM4Py 全部 soundness 工具对照或结构 WF-net 证明 |
| XES 读写 | `parse_xes`、`EventLog::to_xes` | 本库→PM4Py 8 个事件；与 PNML 组合反向回读 2 个案例。完成/配对、标量默认属性、精确毫秒；非无损全量 XES |
| PNML 读写 | `parse_pnml`、`PetriNet::to_pnml` | 本库→PM4Py 两个案例对齐通过，PM4Py 写出→本库再次检查通过；普通带权网、单页、单显式终止标识，不接受任意扩展弧 |
| BPMN 模型转换 | `parse_bpmn`、`BpmnModel::to_petri_net` | PM4Py 实际导入/转换后 3 个轨迹成本一致；本库只做 plain task、单起止、XOR/AND，非完整 BPMN 执行与发现 |
| 声明式合规 | `check_policies` | Response/Precedence/NotCoexist/职责分离，含时限、事件证据及未知资源状态；独立测试，不宣称与全部 DECLARE 模板等价 |
| 日志筛选及组织诊断 | `select_cases`、`resource_handoffs` | 整案例过滤和相邻资源交接次数/覆盖，独立测试；不是全部过滤、社会网络或组织挖掘算法移植 |
| 性能与变体变化 | `performance`、`compare_cohort` | 区间并集、空闲/服务工作量、分位数、资源并发及变体总变差；独立预言机与场景，不把口径不同的指标直接等同 |

## 可复现的量化对照

使用 Python 3.11、PM4Py 2.7.23；安装到隔离环境或忽略的 `.local/pm4py-runtime`，
在仓库根目录运行：

```sh
python scripts/compare_pm4py.py
python scripts/verify_model_cli.py
moon run --target native --release examples/model_scale
```

Windows moonc 0.10.16 的盘符路径问题使用 `scripts/Invoke-Moon.ps1`；两个 Python
脚本在 Windows 会自动使用该适配器。无需修改全局工具链或将 PM4Py 加入 MoonBit 依赖。

- `model_alignment_costs = 484`：A/B/X 全部长度 0..4 的词，各 121 个，四种模型。
- `weighted_language_costs = 121`：PM4Py 普通带权执行语义枚举有限语言，再用独立编辑距离。
- `alpha_discovery_costs = 6`，`xes_events = 8`，`pnml_import_costs = 2`，
  `bpmn_conversion_costs = 3`，`reverse_interchange_cases = 2`。
- 15 条 CLI 工作流检查真实输出及正常、业务偏差、输入错误、用法错误退出码。
- 2000 案例／4 变体／10 轮，复用与不复用的每一条成本及完整证据一致；
  每轮搜索记录为 32 对 16000。计时条件和结果见 [模型说明](models.md)。

直接对齐采用显式单位成本：同步和静默移动为 0，日志及可见模型移动为 1；
不比较 PM4Py 默认缩放成本或未经定义的归一化 fitness。等成本最优证据可能不唯一，
不要求与 PM4Py 的移动顺序逐字相同。批量复用测试则在本库内部验证完整证据与身份一致。

PM4Py 同步乘积对齐在该加权 fixture 上未返回结果，因此**未将这 121 项算作其
对齐器直接对照通过**；单独使用其加权执行语义加有限语言距离。不能从此样例推断
全部加权模型都存在该问题。固定合成语料不等于完整标准测试或生产实绩。

## 明确未覆盖的成熟库能力

Inductive/Heuristics 等发现算法、完整 token replay/precision/generalization 指标集、
过程树与任意 BPMN、预测与机器学习、对象中心 OCEL、工作日历、数据库连接器和
可视化前端均不在 0.2.0 范围内。常见规则、资源图与筛选能力也不冒称覆盖成熟库
同方向的所有算法。后续应按真实需求逐项扩展和验证，不以放宽预算替代算法能力。

## 独立贡献与许可证

项目贡献是 MoonBit 原生的“模型发现—统一网语义—模型对齐—标准交换—业务诊断”
组合，以及可核验的预算失败、精确接受标识和事件证据复用契约；不是宣称发明
Petri 网、Alpha 或最短路，也不将已有 `moonpetri` 的基础发射能力当作生态空白。
根包不调用历史 `sequence` 引擎；其历史和许可如实保留，不重复计为本轮贡献。

MoonBit 实现为 MIT，未复制或翻译 PM4Py 实现源码；PM4Py 为 AGPL-3.0 外部参照，
不随 Mooncakes 包分发，其独立安装环境应保留上游许可。使用的公开数学算法、
规范、原创合成数据和 AI 辅助说明见 [来源说明](sources.md)。
