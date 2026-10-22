# MoonProcessLens

MoonProcessLens 是使用 MoonBit 实现的**过程日志分析与流程挖掘基础库**。它从订单、工单、审批、生产及流水线中已经发生的活动记录，发现实际处理路径，解释与参考流程的偏差，并定位等待、返工和资源并发压力。

输入是带 `case_id / activity / started / completed / resource` 的区间日志；输出是可供报表、可视化及业务工具使用的流程关系图、路径变体、对齐证据和耗时报告。核心分析不依赖外部服务或流计算集群。

## 四项独立能力

| 能力 | 可复用价值 |
| --- | --- |
| 日志重建与 JSON 互操作 | 将乱序业务区间按实例重建，验证身份、时间与容量，便于应用或现有协议库接入。 |
| 流程关系和变体发现 | 区分活动次数与实例覆盖，识别直接相邻关系、自循环、起止节点和完整处理路径。 |
| 最优加权轨迹对齐 | 对有限参考路径解释额外活动和缺失步骤，输出活动身份与逐步证据，支持不同偏差成本。 |
| 区间性能和资源诊断 | 区分服务工作量、并发区间覆盖和真正空闲，分析分位数、环节间隔及资源并发峰值。 |

## 本地使用

模块为 `xingsiyi/processlens`。GitHub 与 Mooncakes 发布账号均为 `xingsiyi`；项目继续使用原本地文件夹，文件夹名称不代表产品名称。

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

## 功能边界

关系图描述指定排序下的相邻活动，不自动证明因果或并行网关。对齐针对有限参考路径，不是完整 BPMN/Petri-net 一致性验证。没有工作日历和资源容量时，只报告观察到的时间与并发，不宣称真实利用率。项目不执行工作流动作，也不宣称兼容 XES/OCEL 标准。

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
