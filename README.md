# motoko-canister-wallet-for-agent

基于 Motoko 的多链 Agent Wallet 后端（对齐 `canisterwalletforagent` Rust 项目的接口命名），包含前端调试界面。

## 当前状态

- 后端公开方法名已统一为 Rust 风格（例如 `ethereum_*`, `bitcoin_*`, `internet_computer_*`, `ton_mainnet_*`）
- 网络 ID 已统一为下划线风格（例如 `internet_computer`, `solana_testnet`, `ton_mainnet`）
- 前端已对齐新的网络 ID 与接口映射
- `configured_rpcs / set_configured_rpc / remove_configured_rpc` 已接入，并能影响主要链路的实际 RPC 请求

## 已实现功能（代码层）

### 地址申请

- `ethereum / sepolia / base / bsc / arbitrum / optimism / avalanche / okx / polygon`
- `bitcoin`
- `internet_computer`
- `solana / solana_testnet`
- `tron`
- `ton_mainnet`
- `near_mainnet`
- `aptos_mainnet`
- `sui_mainnet`

### 余额查询

- EVM 原生币 + ERC20
- BTC
- ICP / ICRC
- SOL / SPL（含 testnet）
- TRX / TRC20
- TON / Jetton
- NEAR / NEP-141
- APT / Aptos token
- SUI / Sui token

### 发送交易

- EVM 原生币 + ERC20（优先 EIP-1559，回退 legacy）
- BTC（Taproot key-path）
- ICP / ICRC
- SOL / SPL（SPL 支持目标 ATA 不存在时自动创建）
- TRX / TRC20
- TON / Jetton
- NEAR / NEP-141
- APT / Aptos token
- SUI / Sui token

## 运行与构建

### 后端编译检查

```bash
dfx build backend --check
```

### 前端构建（会自动生成 declarations）

```bash
cd frontend
npm run build
```

## 已知问题 / 与 Rust 版差距

### 1. EVM RPC HTTP outcall 可能失败（会导致原生余额 / Token 余额一起失败）

报错示例：

- `evm rpc http outcall failed: could not perform remote call`

说明：

- 这是 canister HTTP outcall 没有连上远端 RPC（不是 JSON-RPC 返回错误）
- 常见原因是公共 RPC 不稳定、RPC URL 不正确（例如 `wss://`）、本地 `dfx` 出网环境问题

建议：

- 使用 `set_configured_rpc` 为 EVM 网络配置稳定的 `https://` JSON-RPC（Alchemy / Infura / QuickNode / Ankr 等）
- 不要使用 `wss://` 或区块浏览器 API URL

### 2. 仍有少量 parity TODO（非核心链路）

- `internet_computer` 的 `from` 严格校验尚未完全对齐 Rust 版
- `api` 层 owner/auth 约束还有 TODO
- 动态 token metadata discovery 未覆盖所有可能网络/资产类型

### 3. “代码已实现”不等于“全链实网回归已全部验证”

- 当前为代码迁移与编译通过状态
- 仍建议按链逐条进行实网发送/余额回归测试

## 目录说明

- `/backend`：Motoko 后端（链模块、签名、RPC、SDK）
- `/frontend`：前端调试界面（已对齐 Rust 风格接口名）
- `/src/declarations`：`dfx generate` 生成的前端声明（建议本地生成）
