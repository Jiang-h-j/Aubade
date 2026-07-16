# TRD 切片进度

- 最近完成 TRD：`无（尚未进入开发）`
- 下一个 TRD：`docs/design/nodes/b01-remaining-balance-fix/01-balance-semantics-fix-trd.md`
- 更新时间：待 discover-trds 写入

## 切片清单

| 切片 | 文件 | 状态 |
|---|---|---|
| 01 | `01-balance-semantics-fix-trd.md` 剩余口径修复 + 单测同步 | 待开发 |
| 02 | `02-double-deduction-notice-trd.md` D7 双重扣减提示（两处录入入口） | 待开发 |

## 下一次开发

从切片 01「剩余口径修复 + 单测同步」开始：删 `BalanceCalculator.swift:14` 日期过滤 + 改注释 + 更新 `testBaselineBoundaryInclusive` 断言 + 补正向断言。
