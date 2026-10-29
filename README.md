# MoonProcessLens

MoonProcessLens 是使用 MoonBit 实现的**过程日志分析与流程挖掘基础库**。它从订单、工单、审批、生产及流水线中已经发生的活动记录，发现实际处理路径，解释与参考流程的偏差，并定位等待、返工和资源并发压力。

## 0.2.0：从路径分析扩展到模型级流程挖掘

本版新增模型接口，旧版 0.1.0 不包含这些接口。原有 DFG、参考路径和性能接口保留；`EventLog`、`CaseTrace`、`ReferencePath`、`AlignmentSpec` 的内部数组现为私有，外部代码应使用复制返回的访问方法，避免破坏日志不变量。

| 新增核心能力 | 实际可复用的结果 |
| --- | --- |
| 可执行模型发现 | 经典 Alpha 从因果足迹发现含并行结构的接受 Petri Net；前缀网发现保留观察到的有限轨迹语言，支持重复活动和短循环样例，不将 DFG 换名为模型 |
| 模型级一致性 | 带权普通 P/T 网、初始/终止标识、静默迁移；Dijkstra 在轨迹与标识乘积空间返回最优同步/日志/模型偏差证据；预算不足显式报错 |
| 模型行为检查 | 可达状态图、终止可达、能否从已探索状态完成、剩余令牌完成异常、死锁与死迁移；未完成探索标记 complete=false，不冒充完整 soundness 证明 |
| BPMN 控制流接入 | 支持一个起止事件、普通 task、XOR/AND 分支及汇合的受限 BPMN 2.0 XML，转换成 Petri Net 后按语义检查；不执行条件、事件、数据或子流程 |
| 标准格式互操作 | XES 完成事件和 start/complete 配对、时间/资源/实例身份；PNML 带权网与明确终止标识；XML 双向交换，明确投影与不支持项 |
| 批量变体复用 | 同一模型、同一标签序列只搜索一次，逐实例重新绑定事件 ID；成本与证据与不复用版本一致，可统计实际搜索工作 |

另外新增 **声明式响应/前置/互斥/职责分离规则、响应时限、完整实例筛选、资源交接网络、群组变体分布差异**。资源缺失返回 inconclusive，群组差异是描述统计，不当作因果或统计显著性结论。

### 三个新增完整场景

```sh
moon run --target native examples/model_discovery
moon run --target native examples/model_conformance
moon run --target native examples/standard_workflow
```

- 生产履约：从两种并行交错发现模型，两种顺序均通过，漏做质检产生代价 1；PNML 交换后行为保持。
- 审批复核：读取 XOR 审批 BPMN，人工或自动审批各自合法，重复走两个分支被指出；不是将网关当普通活动。
- 工单治理：XES 交换后检查审批时限和“四眼原则”，找到延误与自审批，筛出慢实例并构建资源交接网络。

三个都是合成数据上的可运行断言示例，不是生产用户采用声明。模型选择、支持矩阵和算法代价详见 [模型能力与互操作](docs/models.md)。

### 与成熟工具对照及量化证据

`python scripts/compare_pm4py.py` 使用独立 PM4Py 2.7.23（开发期 oracle，非运行依赖）。已实测 484 个无权模型对齐成本、6 个 Alpha 发现行为、8 个 XES 事件、2 个 PNML 成本、3 个 BPMN 行为一致；PM4Py 写出的 XES/PNML 再由本库读取验证 2 个实例。另有 121 个带权成本使用 PM4Py 执行语义枚举接受语言加独立距离计算，不冒称其对齐器本身支持该权重样例。完整版本条件和局限见 [验证说明](docs/models.md)。

参照对象是真实安装的 PM4Py 发布包，不是自写的替身；但“使用成熟完整工具作参照”不等于“覆盖其全部能力”。[PM4Py 能力对应与验证矩阵](docs/reference-coverage.md) 逐项列出已实现、独立对照、语义差异与未覆盖能力。项目不是 PM4Py 的源码移植，也不依赖 Python 执行核心计算。

`moon run --target native --release examples/model_scale` 对 2000 个实例、4 个变体做 10 轮成本及完整证据一致性对比。本机重复变体负载下每轮复用 1996 个实例，搜索状态 32 对 16000，最近一次 P50 为 3ms 对 52ms（前次 4ms 对 52ms）；不保证其他分布、更复杂模型或跨机器收益。

本轮本地 `moon check/build/test --target all --deny-warn` 已通过；wasm、wasm-gc、JavaScript、native 每个后端各 158 项测试通过。CI 同时执行四后端及独立 PM4Py job；远程执行状态以 [GitHub Actions](https://github.com/xingsiyi/MoonProcessLens/actions) 对应提交为准，不以本地结果代替。

输入是带 `case_id / activity / started / completed / resource` 的区间日志；输出是可供报表、可视化及业务工具使用的流程关系图、路径变体、对齐证据和耗时报告。核心分析不依赖外部服务或流计算集群。

## 保留的基础诊断能力

| 能力 | 可复用价值 |
| --- | --- |
| 日志重建与 JSON 互操作 | 将乱序业务区间按实例重建，验证身份、时间与容量，便于应用或现有协议库接入。 |
| 流程关系和变体发现 | 区分活动次数与实例覆盖，识别直接相邻关系、自循环、起止节点和完整处理路径。 |
| 最优加权轨迹对齐 | 对有限参考路径解释额外活动和缺失步骤，输出活动身份与逐步证据，支持不同偏差成本。 |
| 区间性能和资源诊断 | 区分服务工作量、并发区间覆盖和真正空闲，分析分位数、环节间隔及资源并发峰值。 |

## 本地使用

模块为 `xingsiyi/processlens`。GitHub 与 Mooncakes 发布账号均为 `xingsiyi`；项目继续使用原本地文件夹，文件夹名称不代表产品名称。

安装模型能力版本：`moon add xingsiyi/processlens@0.2.0`。

```moonbit
import { "xingsiyi/processlens" @lens }
```

```moonbit
fn main raise {
  let log = @lens.EventLog::new([
    @lens.LogEvent::new("o1", "order/7", "create", 0L, 1L),
    @lens.LogEvent::new("o2", "order/7", "ship", 5L, 6L),
  ])
  let model = @lens.ReferencePath::new("approved-order", ["create", "approve", "ship"])
  let result = log.align([model])
  assert_eq(result[0].cost, 1)
  println(@lens.alignment_to_json(result[0]).stringify())
  println(@lens.process_map_to_json(log.discover()).stringify())
  println(@lens.performance_to_json(log.performance()).stringify())
}
```

生产根包仅使用 MoonBit 标准库。文件 CLI 的 IO 使用 `moonbitlang/x@0.4.49`；核心分析支持 wasm、wasm-gc、JavaScript、native，开发工具链为 moonc 0.10.16。

## 完整业务场景

| 示例 | 输入、分析和可核验结果 |
| --- | --- |
| procurement | 两笔乱序订单，发现正常和跳过审批两种路径；对齐明确指出缺失审批，并报告处理空闲。 |
| support | 工单反复调查形成自循环；对齐给出多余活动证据，并输出客服环节服务耗时分布。 |
| pipeline | 构建与测试并行；区间并集避免把并发工作量误算成总耗时，计算资源并发峰值。 |
| repairs | 正常维修和复检返工走不同参考路径；识别变体，比较工位服务时间和跨工单并发。 |

```sh
moon run --target native examples/procurement
moon run --target native examples/support
moon run --target native examples/pipeline
moon run --target native examples/repairs
moon run --target native --release examples/process_scale
```

上述示例都有实际输出和断言，使用自建合成数据。规模示例处理 60,000 个事件、20,000 个实例，实际完成发现、对齐和性能分析；不据此宣称优于其他实现。

## 文件工具

```sh
moon run --target native cmd/processlens -- analyze examples/files/process-log.json
moon run --target native cmd/processlens -- align examples/files/process-log.json examples/files/reference-paths.json
```

`analyze` 输出流程图和性能报告；`align` 对全部实例预先检查累计计算预算，再输出逐步偏差证据。格式、边界、算法复杂度见 [API](docs/api.md)、[语义](docs/semantics.md)、[JSON](docs/formats.md) 和 [性能](docs/performance.md)。

新增文件工具可直接连接标准日志与模型：

```sh
moon run --target native cmd/processlens -- check examples/files/model-log.xes examples/files/parallel.bpmn
moon run --target native cmd/processlens -- discover examples/files/model-log.xes alpha
moon run --target native cmd/processlens -- discover-pnml examples/files/model-log.xes prefix
moon run --target native cmd/processlens -- model examples/files/parallel.bpmn
moon run --target native cmd/processlens -- audit examples/files/model-log.xes examples/files/policies.json
python scripts/verify_model_cli.py
```

`check` 和 `audit` 会输出证据；发现不一致/违反或不可判定时退出码 3。非法输入/预算失败为 1，命令用法错误为 2。`analyze/model/compare/resources` 是描述性报告命令，不能以退出 0 当作完整模型正确性证明。

## 功能边界

关系图仍只描述指定排序下的相邻活动；`align` 针对有限参考路径，新 `align_net` 才是接受模型的最优对齐。Alpha 是经典算法、有明确完备性假设及 16 活动上限；短循环应显式选择前缀网，后者不泛化未知循环次数。支持普通 Petri Net 与限定 BPMN/XES/PNML profile，不是完整 BPMN/XES/PNML 标准实现或 PM4Py 等价替代；不支持 OCEL、Inductive Miner、执行工作流、统计因果推断。无工作日历/资源容量时仅报告观察到的耗时和并发。

根包与旧序列引擎相互独立。早期 MoonCEP 的实现和测试保留在可选 `sequence` 子包，工具入口为 `cmd/sequence`，详见 [历史能力文档](docs/sequence/api.md)。沿革和代码来源如实保留，项目更名不等于历史被删除。

## 验证

```sh
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
moon fmt --check
moon info
git diff --exit-code
python scripts/verify_repository.py
```

本机 Windows 0.10.16 如遇官方扩展路径问题，使用 `& .\scripts\Invoke-Moon.ps1 ...` 替代 `moon ...`。该适配仅转发参数，不修改全局工具。

测试含独立的公共子序列穷举对齐预言机、整数时间槽区间覆盖/并发预言机、JSON 边界和旧检测器回归。CI 验证所有后端、完整场景与文件工具；远端运行状态以仓库 Actions 页面为准。

采用 MIT 许可证，AI 辅助独立实现；参考、依赖和演进来源见 [来源说明](docs/sources.md)。申报书与过程报告保存在仓库外。

## Source-workspace extensions (unreleased)

Compiler requirement: **moonc >= 0.10.16**. See
[the API, scope and complexity notes](docs/FEATURE_EXTENSIONS.md) for **资源并发时间线与案例流量窗口**.
These additions are available in this source tree; the previously published package
version does not yet contain them. Run the assertion-based example from the repository:

```sh
moon run examples/workload_windows --target wasm-gc --deny-warn
```
