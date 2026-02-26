# Canister HTTP Outcall / Cycles / 并发查询问题说明

## 适用场景

本说明用于排查以下现象（主要发生在 EVM 链余额查询）：

- 前端页面打开后，原生币和多个 Token 余额同时查询失败
- 报错包含：
  - `could not perform self call`
  - `Canister ... is out of cycles`
- `dfx canister call` 单独调用某个余额接口又能成功

典型例子：

- `ethereum_get_balance_eth`
- `polygon_get_balance_pol`
- `*_get_balance_erc20`

## 问题现象（为什么 CLI 成功，但前端失败）

`dfx canister call` 一次通常只调用一个方法，所以只触发一条链路请求。

前端页面加载时会同时触发多条请求，例如：

- 原生币余额查询
- Token 列表中多个 token 的余额查询
- 详情面板重复查询（如果当前资产卡会自动拉取详情）

对于 EVM `ERC20` 余额，后端内部还会调用多次 JSON-RPC（例如 `eth_call` 获取 `decimals` + `balanceOf`）。

结果是：

- 单次调用没问题
- 页面并发调用时，短时间内触发多个 `canister_http` outcall
- 瞬时 cycles 压力升高，导致 `IC0504 ... out of cycles`

## 根因拆解

### 1) `could not perform self call`

这类错误不是余额逻辑错误，通常发生在 canister HTTP outcall 参数编码/运行时路径异常时。

本项目已处理：

- Motoko `outcall` 参数去掉 `transform` 字段编码（即使是 `null`，某些环境下也可能触发问题）

相关文件：

- `backend/outcall.mo`

### 2) `Canister ... is out of cycles`

这不一定表示 canister 总余额为 0，而可能是：

- 某次 `canister_http` 调用附加的 cycles 不够
- 或并发请求瞬时过多，把临时可用 cycles 打满

特别是页面并发加载多个 token 余额时更明显。

## 当前已做的修复（项目内）

### A. 后端：HTTP outcall 按响应大小动态附加 cycles

已实现：

- 使用 `max_response_bytes` 动态计算附加 cycles，而不是固定值

相关文件：

- `backend/outcall.mo`
- `backend/config/app_config.mo`

说明：

- `outcall.mo` 根据 `max_response_bytes` 计算 `attached_http_cycles(...)`
- `app_config.mo` 只保留一个较小的 base floor，避免前端并发场景下瞬时开销过大

### B. 后端：EVM RPC 按方法缩小 `max_response_bytes`

已实现：

- `eth_getBalance` / `eth_call` / `eth_getTransactionCount` 等不再统一按大响应上限计算
- 不同方法使用更小的 `max_response_bytes`

相关文件：

- `backend/evm_rpc.mo`

这会直接降低单次 `canister_http` 的附加 cycles 需求。

### C. 前端：Token 列表余额查询从并发改为串行

已实现：

- 可见 token 列表余额查询从 `Promise.all(...)` 改为逐个 `await`

相关文件：

- `frontend/src/App.jsx`

作用：

- 降低页面初始加载的瞬时请求峰值
- 避免一口气触发多条 `ERC20` 余额链路

### D. 前端：增加 RPC 管理全屏面板

已实现：

- 主界面新增 `RPC 管理` 按钮
- 可查看所有链默认 RPC / 当前 override / 生效 RPC
- 可按链添加、更新、删除 RPC override

相关文件：

- `frontend/src/App.jsx`
- `frontend/src/styles.css`

## 解决办法（操作层）

### 1) 先确认是否是“正常返回 0”

如果返回：

- `Ok`
- `message = "RPC eth_getBalance (formatted ETH)"`
- `amount = "0"`

这表示查询成功，只是该地址在该链余额为 0，不是错误。

### 2) 出现 `out of cycles` 时先补 cycles

```bash
dfx canister status backend
dfx canister deposit-cycles 3000000000000 backend
dfx canister status backend
```

### 3) 确保前后端都部署到最新版本

后端修复和前端节流是两部分，建议都部署：

```bash
dfx deploy backend
cd frontend && npm run build && cd ..
dfx deploy frontend
```

然后浏览器强制刷新（`Cmd + Shift + R`）。

### 4) 使用稳定 RPC（尤其是 EVM 主网）

通过前端 `RPC 管理` 或 CLI 设置：

```bash
dfx canister call backend set_configured_rpc '(record { network = "ethereum"; rpc_url = "https://YOUR_ETH_RPC" })'
```

查看当前 override：

```bash
dfx canister call backend configured_rpcs '()'
```

删除 override（回退默认）：

```bash
dfx canister call backend remove_configured_rpc '(record { network = "ethereum" })'
```

## 如果后端并发请求很多，怎么办（建议方案）

这是后续扩展时最重要的部分。

### 短期（已做/推荐继续做）

1. 前端限流 / 串行化部分读取请求
- 已做：Token 列表可见项余额串行查询
- 可继续做：详情面板与列表查询去重（避免重复同一 token 的余额请求）

2. 缩小 `max_response_bytes`
- 已做：EVM 方法级响应上限
- 可继续做：更多链（TON / Sui / Aptos）按接口粒度缩小上限

3. 使用稳定 RPC，减少重试和超时
- 公共 RPC 容易抖动，失败重试会进一步放大并发压力

### 中期（建议在后端实现）

1. 做“相同查询去重”（request coalescing）
- Key 示例：`network + account + token`
- 同一时间多个请求命中同一个 key 时，只发一次 RPC，其他请求等待结果

2. 做短 TTL 缓存（尤其 token metadata）
- `decimals / symbol / name` 基本不会频繁变化
- 避免每次 `ERC20` 余额都重复查 `decimals`

3. 按网络做并发上限（bounded concurrency）
- 例如每条链同一时间最多 2~4 个外部 RPC
- 超出的请求排队或快速失败（返回 `busy`）

4. 区分优先级
- 原生币余额（用户当前主视图）优先
- token 列表后台刷新次之
- 批量预取/探测类请求最低

### 长期（更稳的架构方向）

1. 增加后台任务队列
- 将高并发查询转成内部队列处理
- 前端轮询状态或订阅结果

2. 独立缓存层/聚合层
- 将常见 RPC 查询结果缓存到 canister state（短 TTL）
- 降低外部 RPC 调用频率

3. 更细的指标与日志
- 统计每条链：
  - 请求数
  - outcall 失败率
  - `out of cycles` 次数
  - 平均响应时间

## 建议实施顺序（后端并发优化）

1. 先做 `token metadata` 缓存（收益高、风险低）
2. 再做同 key 余额查询去重（`network + account + token`）
3. 再加每链并发上限（信号量/排队）
4. 最后再做完整任务队列

## 一句话结论

这类问题不是“余额逻辑错了”，而是：

- `canister_http` 成本
- 前端并发模式
- RPC 稳定性

三者叠加导致的运行时问题。单条 CLI 调用成功时，优先从“并发请求峰值”和“outcall cycles 配置”排查。

