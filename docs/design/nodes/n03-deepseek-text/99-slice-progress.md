# TRD 切片进度

- 最近完成 TRD：`（尚未开发，TRD 刚生成待用户评审）`
- 下一个 TRD：`docs/design/nodes/n03-deepseek-text/01-parsing-core-trd.md`（评审通过后开发）
- 更新时间：2026-07-14

## 切片清单（顺序）

1. `01-parsing-core-trd.md` — M4 解析底座（协议 + 归一兜底 + 错误 + mock + 真实 Client + Keychain），纯逻辑全单测
2. `02-text-entry-key-trd.md` — 文本识别入口 + 无 Key 拦截 + 最小 Key sheet + 识别状态机 + 识别成功入账
3. `03-result-card-fallback-debug-trd.md` — 结果卡片（复用 TransactionEditor）+ 失败转手动 + DEBUG 调试

## 当前状态

- N03 PRD 已用户评审通过；本目录三切片 TRD 已生成，待 `jflow-review` 自评审 + 用户 TRD 评审。
- 尚无切片进入开发（`completed_trds` 为空）。

## 下一次开发

- 用户「TRD 评审通过」后，提交推送 TRD，进入 `jflow-dev` 实现切片 01。
- 切片 01 全为新增文件（`Aubade/Features/Recognition/Parsing/*`、`Aubade/Persistence/KeychainStore.swift` + 两个测试文件），不改 N00/N01/N02 现有文件，风险最低。
- 分支：`feat/n03`（本节点已用）。
