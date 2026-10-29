# 资源并发时间线与案例流量窗口

## 资源并发时间线

`EventLog::resource_timeline(resource, from, until, max_segments~)` 对指定观察
资源的活动区间做边界扫描，返回 `[started, completed)` 上恒定的 `active` 数。
包括空闲段，裁剪跨窗口事件，同时边界先合并，零时长事件不贡献占用。
默认最多 4096 段；非法窗口、资源名与预算明确报错。

用于工单团队负荷、设备任务重叠、流水线执行槽位和审批资源压力分析。
结果是日志观察到的并发任务数；没有排班、容量和缺失日志信息时，不能解释成人员利用率。
对于 E 条事件、B 个不同边界，时间 O(E+B log B)，空间 O(B)。

## 整案例流量窗口

`EventLog::flow_windows(from, until, width, max_windows~, max_work~)` 返回固定宽度
窗口内开始/完成案例数、起点活跃数、终点左极限活跃数、观察在制量面积及均值、
已完成案例周期分布。末窗可短于 width。开始和完成按 `[start,end)` 计数，
案例占用按 `[first_start,last_complete)`；瞬时案例计开始/完成但不产生占用面积。

用于订单流量、服务工单积压回看、批处理吞吐与跨窗口案例对照。日志只含完整的
已观察案例；未上报或未完成案例无法推断，结果不是实时队列长度或因果诊断。
面积使用 Double 聚合，大规模乘积不承诺整数精确性。
默认窗口 4096、窗口×案例工作量 10000000；时间 O(E+W*C+sum K_w log K_w)，
空间 O(C+W+sum K_w)，其中 K_w 为该窗完成案例数，排序来自周期分布。

## 验证范围

`workload_windows_wbtest.mbt` 覆盖跨案例重叠、空闲、同时边界、瞬时事件、
窗口边界完成归属、观察面积守恒和非法参数/预算。时间戳遵循现有非负安全整数范围。

## 本地复现

要求 moonc >= 0.10.16。在本地源码目录执行：

```sh
moon update
python tools/verify_toolchain.py
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
moon run examples/workload_windows --target wasm-gc --deny-warn
moon run examples/workload_windows --target native --deny-warn
```

Windows 如遇官方 0.10.16 扩展路径问题，以仓库的 `scripts/Invoke-Moon.ps1`
代替 `moon`；该脚本只转发本机官方工具，不修改全局工具链。

以上 API 从 **0.3.0** 起提供：`moon add xingsiyi/processlens@0.3.0`。
全部示例为可运行断言，不代表已有生产部署。
