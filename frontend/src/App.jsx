import { useEffect, useState } from 'react';

const TOKEN_VLIST_HEIGHT = 420;
const TOKEN_VLIST_ROW_HEIGHT = 124;
const TOKEN_VLIST_OVERSCAN = 3;

const NETWORK_CONFIG = {
  ethereum: {
    title: 'Ethereum',
    nativeSymbol: 'ETH',
    nativeLabel: 'ETH 地址',
    tokenLabel: 'Token 合约地址',
    tokenSymbol: 'USDC',
    showToken: true
  },
  sepolia: {
    title: 'Sepolia',
    nativeSymbol: 'ETH',
    nativeLabel: 'Sepolia 地址',
    tokenLabel: 'ERC20 合约地址',
    tokenSymbol: 'USDC',
    showToken: true
  },
  base: {
    title: 'Base',
    nativeSymbol: 'ETH',
    nativeLabel: 'Base 地址',
    tokenLabel: 'Token 合约地址',
    tokenSymbol: 'USDC',
    showToken: true
  },
  bsc: {
    title: 'BNB Smart Chain',
    nativeSymbol: 'BNB',
    nativeLabel: 'BSC 地址',
    tokenLabel: 'BEP20 合约地址',
    tokenSymbol: 'USDT',
    showToken: true
  },
  arbitrum: {
    title: 'Arbitrum',
    nativeSymbol: 'ETH',
    nativeLabel: 'Arbitrum 地址',
    tokenLabel: 'ERC20 合约地址',
    tokenSymbol: 'USDC',
    showToken: true
  },
  optimism: {
    title: 'Optimism',
    nativeSymbol: 'ETH',
    nativeLabel: 'Optimism 地址',
    tokenLabel: 'ERC20 合约地址',
    tokenSymbol: 'USDC',
    showToken: true
  },
  avalanche: {
    title: 'Avalanche',
    nativeSymbol: 'AVAX',
    nativeLabel: 'Avalanche 地址',
    tokenLabel: 'ERC20 合约地址',
    tokenSymbol: 'USDC.e',
    showToken: true
  },
  okx: {
    title: 'OKX Chain',
    nativeSymbol: 'OKB',
    nativeLabel: 'OKX 链地址',
    tokenLabel: 'ERC20 合约地址',
    tokenSymbol: 'USDT',
    showToken: true
  },
  polygon: {
    title: 'Polygon',
    nativeSymbol: 'POL',
    nativeLabel: 'Polygon 地址',
    tokenLabel: 'ERC20 合约地址',
    tokenSymbol: 'USDC',
    showToken: true
  },
  internet_computer: {
    title: 'Internet Computer',
    nativeSymbol: 'ICP',
    nativeLabel: '账户地址',
    tokenLabel: 'ICRC Token Canister',
    tokenSymbol: 'ICRC',
    showToken: true
  },
  bitcoin: {
    title: 'Bitcoin',
    nativeSymbol: 'BTC',
    nativeLabel: 'BTC 地址',
    tokenLabel: 'Token 地址',
    tokenSymbol: '',
    showToken: true
  },
  solana: {
    title: 'Solana',
    nativeSymbol: 'SOL',
    nativeLabel: 'Solana 地址',
    tokenLabel: 'SPL Token Mint',
    tokenSymbol: 'USDC',
    showToken: true
  },
  solana_testnet: {
    title: 'Solana Testnet',
    nativeSymbol: 'SOL',
    nativeLabel: 'Solana Testnet 地址',
    tokenLabel: 'SPL Token Mint',
    tokenSymbol: 'USDC',
    showToken: true
  },
  tron: {
    title: 'TRON',
    nativeSymbol: 'TRX',
    nativeLabel: 'TRX 地址',
    tokenLabel: 'TRC20 合约地址',
    tokenSymbol: 'USDT',
    showToken: true
  },
  ton_mainnet: {
    title: 'TON',
    nativeSymbol: 'TON',
    nativeLabel: 'TON 地址',
    tokenLabel: 'Jetton Master 地址',
    tokenSymbol: 'USDT',
    showToken: true
  },
  near_mainnet: {
    title: 'NEAR',
    nativeSymbol: 'NEAR',
    nativeLabel: 'NEAR 账户',
    tokenLabel: 'NEP-141 Token 合约',
    tokenSymbol: 'USDT',
    showToken: true
  },
  aptos_mainnet: {
    title: 'Aptos',
    nativeSymbol: 'APT',
    nativeLabel: 'Aptos 地址',
    tokenLabel: 'Token 地址',
    tokenSymbol: 'APT',
    showToken: true
  },
  sui_mainnet: {
    title: 'Sui',
    nativeSymbol: 'SUI',
    nativeLabel: 'Sui 地址',
    tokenLabel: 'Token Type',
    tokenSymbol: 'SUI',
    showToken: true
  }
};

const DEFAULT_NETWORK_ORDER = [
  'ethereum',
  'sepolia',
  'base',
  'bsc',
  'arbitrum',
  'optimism',
  'avalanche',
  'okx',
  'polygon',
  'internet_computer',
  'bitcoin',
  'solana',
  'solana_testnet',
  'tron',
  'ton_mainnet',
  'near_mainnet',
  'aptos_mainnet',
  'sui_mainnet'
];

function normalizeNetworkId(networkId) {
  const n = String(networkId || '')
    .trim()
    .toLowerCase()
    .replaceAll('-', '_');
  if (!n) return '';
  if (n === 'internetcomputer') return 'internet_computer';
  return n;
}

function fallbackNetworkConfig(networkId) {
  const upper = String(networkId || 'unknown').toUpperCase();
  return {
    title: upper,
    nativeSymbol: upper,
    nativeLabel: `${upper} 地址`,
    tokenLabel: 'Token 地址',
    tokenSymbol: 'Token',
    showToken: false
  };
}

function readOpt(value) {
  if (Array.isArray(value)) {
    return value.length > 0 ? value[0] : null;
  }
  return value ?? null;
}

function formatWalletError(err) {
  if (!err || typeof err !== 'object') return '未知错误';
  if ('InvalidInput' in err) return err.InvalidInput;
  if ('Internal' in err) return err.Internal;
  if ('Forbidden' in err) return '无权限';
  if ('Paused' in err) return '服务已暂停';
  if ('Unimplemented' in err) {
    const v = err.Unimplemented || {};
    return `未实现: ${v.network || 'unknown'}/${v.operation || 'unknown'}`;
  }
  return '未知错误';
}

function parseBalanceResponse(resp) {
  return {
    network: normalizeNetworkId(resp?.network || ''),
    account: resp?.account || '',
    token: readOpt(resp?.token) || '',
    amount: readOpt(resp?.amount),
    decimals: readOpt(resp?.decimals),
    pending: Boolean(resp?.pending),
    blockRef: readOpt(resp?.block_ref),
    message: readOpt(resp?.message) || ''
  };
}

function parseConfiguredToken(resp) {
  return {
    network: normalizeNetworkId(resp?.network || ''),
    symbol: resp?.symbol || '',
    name: resp?.name || '',
    tokenAddress: resp?.token_address || '',
    decimals: Number(resp?.decimals ?? 0)
  };
}

function parseConfiguredRpc(resp) {
  return {
    network: normalizeNetworkId(resp?.network || ''),
    rpcUrl: resp?.rpc_url || ''
  };
}

function parseConfiguredExplorer(resp) {
  return {
    network: normalizeNetworkId(resp?.network || ''),
    addressUrlTemplate: resp?.address_url_template || '',
    tokenUrlTemplate: readOpt(resp?.token_url_template) || ''
  };
}

function parseTransferResponse(resp) {
  return {
    network: normalizeNetworkId(resp?.network || ''),
    accepted: Boolean(resp?.accepted),
    txId: readOpt(resp?.tx_id) || '',
    message: resp?.message || ''
  };
}

function parseAddressResponse(resp) {
  return {
    network: normalizeNetworkId(resp?.network || ''),
    address: resp?.address || '',
    publicKeyHex: resp?.public_key_hex || '',
    keyName: resp?.key_name || '',
    message: readOpt(resp?.message) || ''
  };
}

async function loadBackendActor() {
  const mod = await import('declarations/backend');
  return mod?.backend || null;
}

function parseServiceInfo(info) {
  if (!info) return null;
  const owner = readOpt(info.owner);
  const note = readOpt(info.note);

  return {
    version: info.version || '--',
    owner: owner?.toText?.() || String(owner || '未设置'),
    paused: Boolean(info.paused),
    caller: info.caller?.toText?.() || String(info.caller || '--'),
    note: note || ''
  };
}

function parseWalletNetworkInfo(row) {
  const id = normalizeNetworkId(typeof row?.id === 'string' ? row.id : '');
  return {
    id,
    primarySymbol: row?.primary_symbol || '',
    addressFamily: row?.address_family || '',
    sharedAddressGroup: row?.shared_address_group || '',
    supportsSend: Boolean(row?.supports_send),
    supportsBalance: Boolean(row?.supports_balance),
    defaultRpcUrl: readOpt(row?.default_rpc_url) || ''
  };
}

function sortNetworksByPreferredOrder(rows) {
  const order = new Map(DEFAULT_NETWORK_ORDER.map((id, index) => [id, index]));
  return [...rows].sort((a, b) => {
    const ai = order.has(a.id) ? order.get(a.id) : Number.MAX_SAFE_INTEGER;
    const bi = order.has(b.id) ? order.get(b.id) : Number.MAX_SAFE_INTEGER;
    if (ai !== bi) return ai - bi;
    return String(a.id).localeCompare(String(b.id));
  });
}

async function loadBackendSnapshot() {
  try {
    const actor = await loadBackendActor();
    if (!actor) {
      return {
        networks: null,
        networkNames: null,
        serviceInfo: null,
        canisterId: null,
        source: 'missing-actor'
      };
    }
    const mod = await import('declarations/backend');

    const [networkRows, walletNetworkRows, serviceInfoRaw] = await Promise.all([
      actor.supported_networks ? actor.supported_networks().catch(() => null) : Promise.resolve(null),
      actor.wallet_networks ? actor.wallet_networks().catch(() => null) : Promise.resolve(null),
      actor.service_info ? actor.service_info().catch(() => null) : Promise.resolve(null)
    ]);

    const parsedWalletRows =
      walletNetworkRows
        ?.map(parseWalletNetworkInfo)
        .filter((row) => typeof row.id === 'string' && row.id.length > 0) ??
      null;

    const parsedRows =
      networkRows?.map((row) => ({
        network: normalizeNetworkId(typeof row?.network === 'string' ? row.network : ''),
        balance_ready: Boolean(row?.balance_ready),
        transfer_ready: Boolean(row?.transfer_ready),
        note: readOpt(row?.note) || ''
      })) ?? null;

    const supportedNetworks =
      parsedRows
        ?.map((row) => row.network)
        .filter((v) => typeof v === 'string' && v.trim().length > 0) ??
      null;

    const walletNetworks = parsedWalletRows?.map((row) => row.id) ?? null;
    const networks = walletNetworks?.length ? walletNetworks : supportedNetworks;

    return {
      networks: networks && networks.length ? [...new Set(networks)] : null,
      networkNames: null,
      serviceInfo: parseServiceInfo(serviceInfoRaw),
      canisterId: typeof mod?.canisterId === 'string' ? mod.canisterId : null,
      source: 'backend'
    };
  } catch {
    return {
      networks: null,
      networkNames: null,
      serviceInfo: null,
      canisterId: null,
      source: 'fallback'
    };
  }
}

async function queryConfiguredTokens(actor, network) {
  const method = actor?.configured_tokens;
  if (typeof method !== 'function') return [];
  try {
    const rows = await method(network);
    return Array.isArray(rows) ? rows.map(parseConfiguredToken) : [];
  } catch {
    return [];
  }
}

async function queryWalletNetworks(actor) {
  const method = actor?.wallet_networks;
  if (typeof method !== 'function') return [];
  try {
    const rows = await method();
    const parsed = Array.isArray(rows) ? rows.map(parseWalletNetworkInfo) : [];
    return sortNetworksByPreferredOrder(parsed.filter((row) => row.id));
  } catch {
    return [];
  }
}

async function queryConfiguredRpcs(actor) {
  const method = actor?.configured_rpcs;
  if (typeof method !== 'function') return [];
  try {
    const rows = await method();
    return Array.isArray(rows) ? rows.map(parseConfiguredRpc).filter((row) => row.network) : [];
  } catch {
    return [];
  }
}

async function upsertConfiguredRpc(actor, network, rpcUrl) {
  const method = actor?.set_configured_rpc;
  if (typeof method !== 'function') {
    return { ok: false, error: '后端未暴露接口: set_configured_rpc' };
  }
  try {
    const result = await method({ network, rpc_url: rpcUrl });
    if (result?.Ok) return { ok: true, data: parseConfiguredRpc(result.Ok) };
    if (result?.Err) return { ok: false, error: formatWalletError(result.Err) };
    return { ok: false, error: '后端返回格式不识别' };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : '调用后端失败' };
  }
}

async function deleteConfiguredRpc(actor, network) {
  const method = actor?.remove_configured_rpc;
  if (typeof method !== 'function') {
    return { ok: false, error: '后端未暴露接口: remove_configured_rpc' };
  }
  try {
    const result = await method({ network });
    if (result?.Ok !== undefined) return { ok: true, removed: Boolean(result.Ok) };
    if (result?.Err) return { ok: false, error: formatWalletError(result.Err) };
    return { ok: false, error: '后端返回格式不识别' };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : '调用后端失败' };
  }
}

async function queryConfiguredExplorer(actor, network) {
  const method = actor?.configured_explorer;
  if (typeof method !== 'function') return null;
  try {
    const opt = await method(network);
    const row = readOpt(opt);
    return row ? parseConfiguredExplorer(row) : null;
  } catch {
    return null;
  }
}

function getTransferMethodName(network, assetKind) {
  const n = normalizeNetworkId(network);
  const isToken = assetKind === 'token';
  if (n === 'ethereum') return isToken ? 'ethereum_transfer_erc20' : 'ethereum_transfer_eth';
  if (n === 'sepolia') return isToken ? 'sepolia_transfer_erc20' : 'sepolia_transfer_eth';
  if (n === 'base') return isToken ? 'base_transfer_erc20' : 'base_transfer_eth';
  if (n === 'bsc') return isToken ? 'bsc_transfer_bep20' : 'bsc_transfer_bnb';
  if (n === 'arbitrum') return isToken ? 'arbitrum_transfer_erc20' : 'arbitrum_transfer_eth';
  if (n === 'optimism') return isToken ? 'optimism_transfer_erc20' : 'optimism_transfer_eth';
  if (n === 'avalanche') return isToken ? 'avalanche_transfer_erc20' : 'avalanche_transfer_avax';
  if (n === 'okx') return isToken ? 'okx_transfer_erc20' : 'okx_transfer_okb';
  if (n === 'polygon') return isToken ? 'polygon_transfer_erc20' : 'polygon_transfer_pol';
  if (n === 'internet_computer') return isToken ? 'internet_computer_transfer_icrc' : 'internet_computer_transfer_icp';
  if (n === 'bitcoin') return 'bitcoin_transfer_btc';
  if (n === 'solana') return isToken ? 'solana_transfer_spl' : 'solana_transfer_sol';
  if (n === 'solana_testnet')
    return isToken ? 'solana_testnet_transfer_spl' : 'solana_testnet_transfer_sol';
  if (n === 'tron') return isToken ? 'tron_transfer_trc20' : 'tron_transfer_trx';
  if (n === 'ton_mainnet') return isToken ? 'ton_mainnet_transfer_jetton' : 'ton_mainnet_transfer_ton';
  if (n === 'near_mainnet') return isToken ? 'near_mainnet_transfer_nep141' : 'near_mainnet_transfer_near';
  if (n === 'aptos_mainnet') return isToken ? 'aptos_mainnet_transfer_token' : 'aptos_mainnet_transfer_apt';
  if (n === 'sui_mainnet') return isToken ? 'sui_mainnet_transfer_token' : 'sui_mainnet_transfer_sui';
  return `${n}_transfer`;
}

async function queryTransfer(actor, network, asset, fromAddress, toAddress, amount) {
  const methodName = getTransferMethodName(network, asset?.kind || 'token');
  const method = actor?.[methodName];
  if (typeof method !== 'function') {
    return { ok: false, error: `后端未暴露接口: ${methodName}` };
  }

  const tokenAddress = asset?.kind === 'token' ? String(asset?.tokenAddress || '').trim() : '';
  let result;
  try {
    result = await method({
      from: fromAddress ? [fromAddress] : [],
      to: toAddress,
      amount,
      token: tokenAddress ? [tokenAddress] : [],
      memo: [],
      nonce: [],
      metadata: []
    });
  } catch (err) {
    return {
      ok: false,
      error: err instanceof Error ? err.message : '调用后端发送接口失败'
    };
  }

  if (result?.Ok) {
    return { ok: true, data: parseTransferResponse(result.Ok) };
  }
  if (result?.Err) {
    return { ok: false, error: formatWalletError(result.Err) };
  }
  return { ok: false, error: '后端发送接口返回格式不识别' };
}

function getAddressMethodName(network) {
  const n = normalizeNetworkId(network);
  if (n === 'ethereum') return 'ethereum_request_address';
  if (n === 'sepolia') return 'sepolia_request_address';
  if (n === 'base') return 'base_request_address';
  if (n === 'bsc') return 'bsc_request_address';
  if (n === 'arbitrum') return 'arbitrum_request_address';
  if (n === 'optimism') return 'optimism_request_address';
  if (n === 'avalanche') return 'avalanche_request_address';
  if (n === 'okx') return 'okx_request_address';
  if (n === 'polygon') return 'polygon_request_address';
  if (n === 'bitcoin') return 'bitcoin_request_address';
  if (n === 'solana') return 'solana_request_address';
  if (n === 'solana_testnet') return 'solana_testnet_request_address';
  if (n === 'tron') return 'tron_request_address';
  if (n === 'ton_mainnet') return 'ton_mainnet_request_address';
  if (n === 'near_mainnet') return 'near_mainnet_request_address';
  if (n === 'aptos_mainnet') return 'aptos_mainnet_request_address';
  if (n === 'sui_mainnet') return 'sui_mainnet_request_address';
  return null;
}

async function queryRequestAddress(actor, network) {
  const methodName = getAddressMethodName(network);
  if (!methodName) return { ok: false, error: `后端未暴露地址申请接口: ${network}` };
  const method = actor?.[methodName];
  if (typeof method !== 'function') {
    return { ok: false, error: `后端未暴露接口: ${methodName}` };
  }

  let result;
  try {
    result = await method();
  } catch (err) {
    return {
      ok: false,
      error: err instanceof Error ? err.message : '调用地址申请接口失败'
    };
  }

  if (result?.Ok) {
    return { ok: true, data: parseAddressResponse(result.Ok) };
  }
  if (result?.Err) {
    return { ok: false, error: formatWalletError(result.Err) };
  }
  return { ok: false, error: '后端地址申请返回格式不识别' };
}

function getBalanceMethodName(network, token = '') {
  const n = normalizeNetworkId(network);
  const hasToken = typeof token === 'string' && token.trim().length > 0;
  if (n === 'ethereum') return hasToken ? 'ethereum_get_balance_erc20' : 'ethereum_get_balance_eth';
  if (n === 'sepolia') return hasToken ? 'sepolia_get_balance_erc20' : 'sepolia_get_balance_eth';
  if (n === 'base') return hasToken ? 'base_get_balance_erc20' : 'base_get_balance_eth';
  if (n === 'bsc') return hasToken ? 'bsc_get_balance_bep20' : 'bsc_get_balance_bnb';
  if (n === 'arbitrum') return hasToken ? 'arbitrum_get_balance_erc20' : 'arbitrum_get_balance_eth';
  if (n === 'optimism') return hasToken ? 'optimism_get_balance_erc20' : 'optimism_get_balance_eth';
  if (n === 'avalanche') return hasToken ? 'avalanche_get_balance_erc20' : 'avalanche_get_balance_avax';
  if (n === 'okx') return hasToken ? 'okx_get_balance_erc20' : 'okx_get_balance_okb';
  if (n === 'polygon') return hasToken ? 'polygon_get_balance_erc20' : 'polygon_get_balance_pol';
  if (n === 'bitcoin') return 'bitcoin_get_balance_btc';
  if (n === 'internet_computer') return hasToken ? 'internet_computer_get_balance_icrc' : 'internet_computer_get_balance_icp';
  if (n === 'solana') return hasToken ? 'solana_get_balance_spl' : 'solana_get_balance_sol';
  if (n === 'solana_testnet')
    return hasToken ? 'solana_testnet_get_balance_spl' : 'solana_testnet_get_balance_sol';
  if (n === 'tron') return hasToken ? 'tron_get_balance_trc20' : 'tron_get_balance_trx';
  if (n === 'ton_mainnet') return hasToken ? 'ton_mainnet_get_balance_jetton' : 'ton_mainnet_get_balance_ton';
  if (n === 'near_mainnet') return hasToken ? 'near_mainnet_get_balance_nep141' : 'near_mainnet_get_balance_near';
  if (n === 'aptos_mainnet') return hasToken ? 'aptos_mainnet_get_balance_token' : 'aptos_mainnet_get_balance_apt';
  if (n === 'sui_mainnet') return hasToken ? 'sui_mainnet_get_balance_token' : 'sui_mainnet_get_balance_sui';
  return `${n}_get_balance`;
}

async function queryBalance(actor, network, account, token) {
  const methodName = getBalanceMethodName(network, token);
  const method = actor?.[methodName];
  if (typeof method !== 'function') {
    return { ok: false, error: `后端未暴露接口: ${methodName}` };
  }

  let result;
  try {
    result = await method({
      account,
      token: token ? [token] : []
    });
  } catch (err) {
    return {
      ok: false,
      error: err instanceof Error ? err.message : '调用后端失败'
    };
  }

  if (result?.Ok) {
    return { ok: true, data: parseBalanceResponse(result.Ok) };
  }
  if (result?.Err) {
    return { ok: false, error: formatWalletError(result.Err) };
  }
  return { ok: false, error: '后端返回格式不识别' };
}

function fillExplorerTemplate(template, params) {
  if (!template) return '';
  return String(template)
    .replaceAll('{address}', encodeURIComponent(params.address || ''))
    .replaceAll('{token}', encodeURIComponent(params.token || ''));
}

function buildExplorerUrlFromConfig(config, account, tokenAddress) {
  const address = String(account || '').trim();
  const token = String(tokenAddress || '').trim();
  if (!config || !address) return '';

  if (token && config.tokenUrlTemplate) {
    return fillExplorerTemplate(config.tokenUrlTemplate, { address, token });
  }
  return fillExplorerTemplate(config.addressUrlTemplate, { address, token });
}

export default function App() {
  const [networkOptions, setNetworkOptions] = useState(DEFAULT_NETWORK_ORDER);
  const [networkDisplayNames, setNetworkDisplayNames] = useState({});
  const [selectedNetwork, setSelectedNetwork] = useState(DEFAULT_NETWORK_ORDER[0]);
  const [nativeAddressInput, setNativeAddressInput] = useState('');
  const [tokenAddressInput, setTokenAddressInput] = useState('');
  const [statusText, setStatusText] = useState('初始化中...');
  const [toast, setToast] = useState(null);
  const [serviceInfo, setServiceInfo] = useState(null);
  const [backendCanisterId, setBackendCanisterId] = useState('');
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [nativeBalanceState, setNativeBalanceState] = useState({
    phase: 'idle',
    data: null,
    error: ''
  });
  const [tokenBalanceState, setTokenBalanceState] = useState({
    phase: 'idle',
    data: null,
    error: ''
  });
  const [configuredTokens, setConfiguredTokens] = useState([]);
  const [configuredExplorer, setConfiguredExplorer] = useState(null);
  const [selectedConfiguredTokenAddress, setSelectedConfiguredTokenAddress] = useState('');
  const [tokenListScrollTop, setTokenListScrollTop] = useState(0);
  const [tokenRowBalances, setTokenRowBalances] = useState({});
  const [selectedAssetRowKey, setSelectedAssetRowKey] = useState('__native__');
  const [tokenDetailAddress, setTokenDetailAddress] = useState('');
  const [tokenTransferTo, setTokenTransferTo] = useState('');
  const [tokenTransferAmount, setTokenTransferAmount] = useState('');
  const [isTokenSending, setIsTokenSending] = useState(false);
  const [detailBalanceState, setDetailBalanceState] = useState({
    phase: 'idle',
    data: null,
    error: ''
  });
  const [isRpcManagerOpen, setIsRpcManagerOpen] = useState(false);
  const [rpcManagerLoading, setRpcManagerLoading] = useState(false);
  const [rpcManagerError, setRpcManagerError] = useState('');
  const [rpcManagerRows, setRpcManagerRows] = useState([]);
  const [rpcOverrideRows, setRpcOverrideRows] = useState([]);
  const [rpcDraftByNetwork, setRpcDraftByNetwork] = useState({});
  const [rpcSavingNetwork, setRpcSavingNetwork] = useState('');
  const [rpcRemovingNetwork, setRpcRemovingNetwork] = useState('');

  const selectedConfig =
    NETWORK_CONFIG[selectedNetwork] || fallbackNetworkConfig(selectedNetwork);

  const rpcOverrideMap = Object.fromEntries(
    rpcOverrideRows.map((row) => [normalizeNetworkId(row.network), row.rpcUrl || ''])
  );

  const rpcManagerDisplayRows =
    (rpcManagerRows.length
      ? rpcManagerRows
      : networkOptions.map((id) => ({
          id,
          primarySymbol: '',
          addressFamily: '',
          sharedAddressGroup: '',
          supportsSend: true,
          supportsBalance: true,
          defaultRpcUrl: ''
        }))
    ).map((row) => {
      const id = normalizeNetworkId(row.id);
      const cfg = NETWORK_CONFIG[id] || fallbackNetworkConfig(id);
      const overrideRpcUrl = rpcOverrideMap[id] || '';
      const defaultRpcUrl = row.defaultRpcUrl || '';
      const effectiveRpcUrl = overrideRpcUrl || defaultRpcUrl;
      const draftRpcUrl =
        rpcDraftByNetwork[id] !== undefined ? rpcDraftByNetwork[id] : overrideRpcUrl || defaultRpcUrl;
      return {
        ...row,
        id,
        title: networkDisplayNames[id] || cfg.title,
        nativeSymbol: row.primarySymbol || cfg.nativeSymbol || '',
        defaultRpcUrl,
        overrideRpcUrl,
        effectiveRpcUrl,
        draftRpcUrl
      };
    });

  useEffect(() => {
    setNativeAddressInput('');
    setTokenAddressInput('');
    setConfiguredTokens([]);
    setConfiguredExplorer(null);
    setSelectedConfiguredTokenAddress('');
    setTokenListScrollTop(0);
    setTokenRowBalances({});
    setSelectedAssetRowKey('__native__');
    setTokenDetailAddress('');
    setTokenTransferTo('');
    setTokenTransferAmount('');
    setDetailBalanceState({ phase: 'idle', data: null, error: '' });
    setNativeBalanceState({ phase: 'idle', data: null, error: '' });
    setTokenBalanceState({ phase: 'idle', data: null, error: '' });
    setStatusText(`已切换到 ${selectedConfig.title}`);
  }, [selectedNetwork, selectedConfig.title]);

  useEffect(() => {
    let cancelled = false;

    (async () => {
      const snapshot = await loadBackendSnapshot();
      if (cancelled) return;

      if (snapshot.networks?.length) {
        setNetworkOptions(snapshot.networks);
        setSelectedNetwork((current) =>
          snapshot.networks.includes(current) ? current : snapshot.networks[0]
        );
      }
      if (snapshot.networkNames && Object.keys(snapshot.networkNames).length > 0) {
        setNetworkDisplayNames(snapshot.networkNames);
      }
      if (snapshot.serviceInfo) {
        setServiceInfo(snapshot.serviceInfo);
      }
      if (snapshot.canisterId) {
        setBackendCanisterId(snapshot.canisterId);
      }

      if (snapshot.source === 'backend') {
        setStatusText('已连接后端：网络列表与名称来自 canister 接口');
      } else {
        setStatusText('未连接后端声明，使用本地网络配置（仍可预览 UI）');
      }
    })();

    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (!toast) return undefined;
    const timer = window.setTimeout(() => setToast(null), 2200);
    return () => window.clearTimeout(timer);
  }, [toast]);

  useEffect(() => {
    if (!isRpcManagerOpen) return undefined;
    function onKeyDown(event) {
      if (event.key === 'Escape') {
        closeRpcManager();
      }
    }
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [isRpcManagerOpen]);

  useEffect(() => {
    let cancelled = false;

    (async () => {
      if (!selectedConfig.showToken) {
        setConfiguredTokens([]);
        setSelectedConfiguredTokenAddress('');
        setTokenAddressInput('');
        return;
      }

      let actor = null;
      try {
        actor = await loadBackendActor();
      } catch {
        actor = null;
      }

      if (!actor) {
        if (!cancelled) {
          setConfiguredTokens([]);
          setSelectedConfiguredTokenAddress('');
          setTokenAddressInput('');
        }
        return;
      }

      const tokens = await queryConfiguredTokens(actor, selectedNetwork);
      if (cancelled) return;

      setConfiguredTokens(tokens);
      const firstAddr = tokens[0]?.tokenAddress || '';
      setSelectedConfiguredTokenAddress(firstAddr);
      setTokenAddressInput(firstAddr);
    })();

    return () => {
      cancelled = true;
    };
  }, [selectedNetwork, selectedConfig.showToken]);

  useEffect(() => {
    let cancelled = false;

    (async () => {
      let actor = null;
      try {
        actor = await loadBackendActor();
      } catch {
        actor = null;
      }
      if (!actor) {
        if (!cancelled) setConfiguredExplorer(null);
        return;
      }

      const explorer = await queryConfiguredExplorer(actor, selectedNetwork);
      if (cancelled) return;
      setConfiguredExplorer(explorer);
    })();

    return () => {
      cancelled = true;
    };
  }, [selectedNetwork]);

  useEffect(() => {
    let cancelled = false;

    (async () => {
      const addressMethod = getAddressMethodName(selectedNetwork);
      const canUseIcpCanisterId = selectedNetwork === 'internet_computer';
      if (!addressMethod && !canUseIcpCanisterId) return;

      let actor = null;
      try {
        actor = await loadBackendActor();
      } catch {
        actor = null;
      }
      if (!actor || cancelled) return;

      setNativeBalanceState({ phase: 'loading', data: null, error: '' });
      setStatusText(`正在申请 ${selectedConfig.title} 地址并查询 ${selectedConfig.nativeSymbol} 余额...`);

      let autoAddress = '';
      if (canUseIcpCanisterId) {
        autoAddress = (backendCanisterId || '').trim();
        if (!autoAddress) {
          setNativeAddressInput('');
          setNativeBalanceState({
            phase: 'error',
            data: null,
            error: '未读取到 backend canister id'
          });
          setStatusText('ICP 地址加载失败: 未读取到 backend canister id');
          return;
        }
      } else {
        const addrRes = await queryRequestAddress(actor, selectedNetwork);
        if (cancelled) return;
        if (!addrRes.ok) {
          setNativeAddressInput('');
          setNativeBalanceState({ phase: 'error', data: null, error: addrRes.error });
          setStatusText(`${selectedConfig.title} 地址申请失败: ${addrRes.error}`);
          return;
        }
        autoAddress = addrRes.data.address;
      }
      setNativeAddressInput(autoAddress);

      const balRes = await queryBalance(actor, selectedNetwork, autoAddress, '');
      if (cancelled) return;
      if (balRes.ok) {
        setNativeBalanceState({ phase: 'ok', data: balRes.data, error: '' });
        setStatusText(`已自动加载 ${selectedConfig.title} 地址与 ${selectedConfig.nativeSymbol} 余额`);
      } else {
        setNativeBalanceState({ phase: 'error', data: null, error: balRes.error });
        setStatusText(`${selectedConfig.nativeSymbol} 余额查询失败: ${balRes.error}`);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [backendCanisterId, selectedConfig.nativeSymbol, selectedConfig.title, selectedNetwork]);

  useEffect(() => {
    let cancelled = false;

    (async () => {
      if (!selectedConfig.showToken) {
        setTokenBalanceState({ phase: 'idle', data: null, error: '' });
        return;
      }

      const address = nativeAddressInput.trim();
      const tokenAddress = tokenAddressInput.trim();
      if (!address || !tokenAddress) {
        setTokenBalanceState({ phase: 'idle', data: null, error: '' });
        return;
      }

      let actor = null;
      try {
        actor = await loadBackendActor();
      } catch {
        actor = null;
      }
      if (!actor || cancelled) {
        if (!cancelled) {
          setTokenBalanceState({ phase: 'error', data: null, error: '前端未连接到 backend actor' });
        }
        return;
      }

      setTokenBalanceState({ phase: 'loading', data: null, error: '' });
      const tokenRes = await queryBalance(actor, selectedNetwork, address, tokenAddress);
      if (cancelled) return;
      if (tokenRes.ok) {
        setTokenBalanceState({ phase: 'ok', data: tokenRes.data, error: '' });
      } else {
        setTokenBalanceState({ phase: 'error', data: null, error: tokenRes.error });
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [selectedConfig.showToken, selectedNetwork, nativeAddressInput, tokenAddressInput]);

  useEffect(() => {
    setTokenRowBalances({});
  }, [selectedNetwork, nativeAddressInput]);

  async function handleRefresh() {
    const address = nativeAddressInput.trim();
    const tokenAddress = tokenAddressInput.trim();
    if (!address) {
      const msg = `请先输入 ${selectedConfig.nativeLabel}`;
      setStatusText(msg);
      setToast(msg);
      return;
    }

    setIsRefreshing(true);
    setNativeBalanceState({ phase: 'loading', data: null, error: '' });
    if (selectedConfig.showToken) {
      if (tokenAddress) {
        setTokenBalanceState({ phase: 'loading', data: null, error: '' });
      } else {
        setTokenBalanceState({ phase: 'idle', data: null, error: '' });
      }
    } else {
      setTokenBalanceState({ phase: 'idle', data: null, error: '' });
    }

    setStatusText(`正在查询 ${selectedConfig.title} 余额...`);

    let actor = null;
    try {
      actor = await loadBackendActor();
    } catch {
      actor = null;
    }

    if (!actor) {
      setIsRefreshing(false);
      setNativeBalanceState({ phase: 'error', data: null, error: '前端未连接到 backend actor' });
      setStatusText('无法连接后端 actor，余额查询失败');
      setToast('无法连接后端 actor');
      return;
    }

    const snapshot = await loadBackendSnapshot();
    if (snapshot.networks?.length) {
      setNetworkOptions(snapshot.networks);
    }
    if (snapshot.serviceInfo) {
      setServiceInfo(snapshot.serviceInfo);
    }
    if (snapshot.canisterId) {
      setBackendCanisterId(snapshot.canisterId);
    }

    const nativeRes = await queryBalance(actor, selectedNetwork, address, '');
    if (nativeRes.ok) {
      setNativeBalanceState({ phase: 'ok', data: nativeRes.data, error: '' });
    } else {
      setNativeBalanceState({ phase: 'error', data: null, error: nativeRes.error });
    }

    if (selectedConfig.showToken && tokenAddress) {
      const tokenRes = await queryBalance(actor, selectedNetwork, address, tokenAddress);
      if (tokenRes.ok) {
        setTokenBalanceState({ phase: 'ok', data: tokenRes.data, error: '' });
      } else {
        setTokenBalanceState({ phase: 'error', data: null, error: tokenRes.error });
      }
    }

    setIsRefreshing(false);
    setStatusText(`已完成 ${selectedConfig.title} 查询（展示后端真实返回）`);
  }

  function handleLoginClick() {
    const msg = '登录逻辑待接入（可接 Internet Identity 或你自己的登录方案）';
    setStatusText(msg);
    setToast(msg);
  }

  async function refreshRpcManagerPanel() {
    setRpcManagerLoading(true);
    setRpcManagerError('');

    let actor = null;
    try {
      actor = await loadBackendActor();
    } catch {
      actor = null;
    }

    if (!actor) {
      setRpcManagerRows([]);
      setRpcOverrideRows([]);
      setRpcManagerError('前端未连接到 backend actor');
      setRpcManagerLoading(false);
      return;
    }

    const [walletRows, overrideRows] = await Promise.all([
      queryWalletNetworks(actor),
      queryConfiguredRpcs(actor)
    ]);

    setRpcManagerRows(walletRows);
    setRpcOverrideRows(overrideRows);
    setRpcDraftByNetwork((prev) => {
      const next = { ...prev };
      const seen = new Set();
      for (const row of walletRows) {
        const id = normalizeNetworkId(row.id);
        if (!id) continue;
        seen.add(id);
        const override = overrideRows.find((item) => normalizeNetworkId(item.network) === id)?.rpcUrl || '';
        const fallback = row.defaultRpcUrl || '';
        if (!(id in next)) next[id] = override || fallback;
      }
      for (const row of overrideRows) {
        const id = normalizeNetworkId(row.network);
        if (!id || seen.has(id)) continue;
        if (!(id in next)) next[id] = row.rpcUrl || '';
      }
      return next;
    });
    setRpcManagerLoading(false);
  }

  function openRpcManager() {
    setIsRpcManagerOpen(true);
    void refreshRpcManagerPanel();
  }

  function closeRpcManager() {
    setIsRpcManagerOpen(false);
    setRpcManagerError('');
    setRpcSavingNetwork('');
    setRpcRemovingNetwork('');
  }

  function handleRpcDraftChange(network, value) {
    const id = normalizeNetworkId(network);
    setRpcDraftByNetwork((prev) => ({ ...prev, [id]: value }));
  }

  async function handleRpcSaveClick(network) {
    const id = normalizeNetworkId(network);
    const rpcUrl = String(rpcDraftByNetwork[id] || '').trim();
    if (!rpcUrl) {
      const msg = `请输入 ${id} 的 RPC 地址`;
      setRpcManagerError(msg);
      setToast(msg);
      setStatusText(msg);
      return;
    }

    let actor = null;
    try {
      actor = await loadBackendActor();
    } catch {
      actor = null;
    }
    if (!actor) {
      const msg = '前端未连接到 backend actor';
      setRpcManagerError(msg);
      setToast(msg);
      setStatusText(msg);
      return;
    }

    setRpcSavingNetwork(id);
    const res = await upsertConfiguredRpc(actor, id, rpcUrl);
    setRpcSavingNetwork('');
    if (!res.ok) {
      const msg = `设置 RPC 失败 (${id}): ${res.error}`;
      setRpcManagerError(msg);
      setToast(msg);
      setStatusText(msg);
      return;
    }

    setRpcOverrideRows((prev) => {
      const next = prev.filter((row) => normalizeNetworkId(row.network) !== id);
      next.push({ network: id, rpcUrl });
      return next;
    });
    const msg = `已设置 ${id} RPC`;
    setRpcManagerError('');
    setStatusText(msg);
    setToast(msg);
  }

  async function handleRpcRemoveClick(network) {
    const id = normalizeNetworkId(network);

    let actor = null;
    try {
      actor = await loadBackendActor();
    } catch {
      actor = null;
    }
    if (!actor) {
      const msg = '前端未连接到 backend actor';
      setRpcManagerError(msg);
      setToast(msg);
      setStatusText(msg);
      return;
    }

    setRpcRemovingNetwork(id);
    const res = await deleteConfiguredRpc(actor, id);
    setRpcRemovingNetwork('');
    if (!res.ok) {
      const msg = `删除 RPC 失败 (${id}): ${res.error}`;
      setRpcManagerError(msg);
      setToast(msg);
      setStatusText(msg);
      return;
    }

    setRpcOverrideRows((prev) => prev.filter((row) => normalizeNetworkId(row.network) !== id));
    setRpcDraftByNetwork((prev) => {
      const next = { ...prev };
      const row = rpcManagerRows.find((item) => normalizeNetworkId(item.id) === id);
      next[id] = row?.defaultRpcUrl || '';
      return next;
    });

    const msg = res.removed ? `已删除 ${id} RPC 覆盖` : `${id} 没有可删除的 RPC 覆盖`;
    setRpcManagerError('');
    setStatusText(msg);
    setToast(msg);
  }

  const nativeBalanceValue =
    nativeBalanceState.phase === 'loading'
      ? '查询中...'
      : nativeBalanceState.phase === 'error'
        ? '查询失败'
        : nativeBalanceState.data?.amount || '未查询/无返回值';

  const nativeBalanceMeta =
    nativeBalanceState.phase === 'error'
      ? nativeBalanceState.error
      : nativeBalanceState.data?.message ||
        (nativeBalanceState.data?.pending ? '后端返回 pending=true' : '等待查询');

  const tokenBalanceValue =
    tokenBalanceState.phase === 'loading'
      ? '查询中...'
      : tokenBalanceState.phase === 'error'
        ? '查询失败'
        : tokenBalanceState.data?.amount || (selectedConfig.showToken ? '未查询/无返回值' : '--');

  const tokenBalanceMeta =
    tokenBalanceState.phase === 'error'
      ? tokenBalanceState.error
      : tokenBalanceState.data?.message ||
        (tokenBalanceState.data?.pending
          ? '后端返回 pending=true'
          : configuredTokens.length
            ? `已从 config 加载 ${configuredTokens.length} 个 Token`
            : '当前网络 config 未配置 Token');

  const selectedConfiguredToken =
    configuredTokens.find((t) => t.tokenAddress === selectedConfiguredTokenAddress) ||
    configuredTokens[0] ||
    null;
  const nativeDecimals = nativeBalanceState.data?.decimals ?? null;
  const nativeAssetRow = {
    rowKey: '__native__',
    kind: 'native',
    symbol: selectedConfig.nativeSymbol,
    name: `${selectedConfig.title} Native`,
    tokenAddress: '',
    decimals: nativeDecimals,
    network: selectedNetwork
  };
  const assetListItems = [
    nativeAssetRow,
    ...configuredTokens.map((token) => ({
      rowKey: `token:${token.tokenAddress}`,
      kind: 'token',
      symbol: token.symbol,
      name: token.name,
      tokenAddress: token.tokenAddress,
      decimals: token.decimals,
      network: token.network
    }))
  ];
  const selectedAsset =
    assetListItems.find((item) => item.rowKey === selectedAssetRowKey) || assetListItems[0] || null;
  const detailAsset =
    assetListItems.find((item) =>
      item.kind === 'native' ? tokenDetailAddress === '__native__' : item.tokenAddress === tokenDetailAddress
    ) || null;
  const detailTokenRowBalance =
    detailAsset && detailAsset.kind === 'token'
      ? tokenRowBalances[detailAsset.tokenAddress] || null
      : null;
  const detailTokenBalanceValue =
    detailTokenRowBalance?.phase === 'loading'
      ? '查询中...'
      : detailTokenRowBalance?.phase === 'error'
        ? '查询失败'
        : detailTokenRowBalance?.amount || tokenBalanceValue;
  const detailTokenBalanceMeta =
    detailTokenRowBalance?.phase === 'error'
      ? detailTokenRowBalance.error
      : detailTokenRowBalance?.message ||
        (detailTokenRowBalance?.pending ? 'pending=true' : tokenBalanceMeta);
  const detailBalanceValue =
    detailBalanceState.phase === 'loading'
      ? '查询中...'
      : detailBalanceState.phase === 'error'
        ? '查询失败'
        : detailBalanceState.data?.amount ||
          (detailAsset?.kind === 'native' ? nativeBalanceValue : detailTokenBalanceValue);
  const detailBalanceMeta =
    detailBalanceState.phase === 'error'
      ? detailBalanceState.error
      : detailBalanceState.data?.message ||
        (detailBalanceState.data?.pending
          ? '后端返回 pending=true'
          : detailAsset?.kind === 'native'
            ? nativeBalanceMeta
            : detailTokenBalanceMeta);

  const tokenListCount = assetListItems.length;
  const tokenVisibleRows = Math.max(1, Math.ceil(TOKEN_VLIST_HEIGHT / TOKEN_VLIST_ROW_HEIGHT));
  const tokenStartIndex = Math.max(
    0,
    Math.floor(tokenListScrollTop / TOKEN_VLIST_ROW_HEIGHT) - TOKEN_VLIST_OVERSCAN
  );
  const tokenEndIndex = Math.min(
    tokenListCount,
    tokenStartIndex + tokenVisibleRows + TOKEN_VLIST_OVERSCAN * 2
  );
  const visibleAssetItems = assetListItems.slice(tokenStartIndex, tokenEndIndex);
  const visibleTokenItems = visibleAssetItems.filter((item) => item.kind === 'token');
  const visibleTokenAddressesKey = visibleTokenItems.map((t) => t.tokenAddress).join('|');

  useEffect(() => {
    let cancelled = false;

    (async () => {
      if (!selectedConfig.showToken) return;
      const account = nativeAddressInput.trim();
      if (!account || !visibleTokenItems.length) return;

      const pendingTokens = visibleTokenItems.filter((token) => {
        const state = tokenRowBalances[token.tokenAddress];
        return !state || state.phase === 'idle';
      });
      if (!pendingTokens.length) return;

      setTokenRowBalances((prev) => {
        const next = { ...prev };
        for (const token of pendingTokens) {
          next[token.tokenAddress] = { phase: 'loading', amount: '', error: '' };
        }
        return next;
      });

      let actor = null;
      try {
        actor = await loadBackendActor();
      } catch {
        actor = null;
      }
      if (!actor || cancelled) {
        if (!cancelled) {
          setTokenRowBalances((prev) => {
            const next = { ...prev };
            for (const token of pendingTokens) {
              next[token.tokenAddress] = {
                phase: 'error',
                amount: '',
                error: '前端未连接到 backend actor'
              };
            }
            return next;
          });
        }
        return;
      }

      const results = [];
      for (const token of pendingTokens) {
        if (cancelled) return;
        const resp = await queryBalance(actor, selectedNetwork, account, token.tokenAddress);
        results.push({ tokenAddress: token.tokenAddress, resp });
      }
      if (cancelled) return;

      setTokenRowBalances((prev) => {
        const next = { ...prev };
        for (const row of results) {
          if (row.resp.ok) {
            next[row.tokenAddress] = {
              phase: 'ok',
              amount: row.resp.data?.amount || '',
              error: '',
              pending: Boolean(row.resp.data?.pending),
              message: row.resp.data?.message || ''
            };
          } else {
            next[row.tokenAddress] = {
              phase: 'error',
              amount: '',
              error: row.resp.error || '查询失败'
            };
          }
        }
        return next;
      });
    })();

    return () => {
      cancelled = true;
    };
  }, [selectedConfig.showToken, selectedNetwork, nativeAddressInput, visibleTokenAddressesKey]);

  useEffect(() => {
    let cancelled = false;

    (async () => {
      if (!detailAsset) {
        setDetailBalanceState({ phase: 'idle', data: null, error: '' });
        return;
      }

      const account = nativeAddressInput.trim();
      if (!account) {
        setDetailBalanceState({ phase: 'error', data: null, error: '当前钱包地址未就绪' });
        return;
      }

      let actor = null;
      try {
        actor = await loadBackendActor();
      } catch {
        actor = null;
      }
      if (!actor || cancelled) {
        if (!cancelled) {
          setDetailBalanceState({
            phase: 'error',
            data: null,
            error: '前端未连接到 backend actor'
          });
        }
        return;
      }

      setDetailBalanceState({ phase: 'loading', data: null, error: '' });
      const token =
        detailAsset.kind === 'token' ? String(detailAsset.tokenAddress || '').trim() : '';
      const result = await queryBalance(actor, selectedNetwork, account, token);
      if (cancelled) return;

      if (result.ok) {
        setDetailBalanceState({ phase: 'ok', data: result.data, error: '' });

        if (detailAsset.kind === 'native') {
          setNativeBalanceState({ phase: 'ok', data: result.data, error: '' });
        } else if (token) {
          setTokenBalanceState({ phase: 'ok', data: result.data, error: '' });
          setTokenRowBalances((prev) => ({
            ...prev,
            [token]: {
              phase: 'ok',
              amount: result.data?.amount || '',
              error: '',
              pending: Boolean(result.data?.pending),
              message: result.data?.message || ''
            }
          }));
        }
      } else {
        setDetailBalanceState({ phase: 'error', data: null, error: result.error });
        if (detailAsset.kind === 'token' && token) {
          setTokenRowBalances((prev) => ({
            ...prev,
            [token]: { phase: 'error', amount: '', error: result.error || '查询失败' }
          }));
        }
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [detailAsset?.kind, detailAsset?.tokenAddress, nativeAddressInput, selectedNetwork]);

  function openTokenDetail(asset) {
    if (!asset) return;
    setSelectedAssetRowKey(asset.rowKey);
    if (asset.kind === 'native') {
      setTokenAddressInput('');
      setTokenDetailAddress('__native__');
      setTokenBalanceState({ phase: 'idle', data: null, error: '' });
    } else {
      const nextAddress = asset.tokenAddress || '';
      setSelectedConfiguredTokenAddress(nextAddress);
      setTokenAddressInput(nextAddress);
      setTokenDetailAddress(nextAddress);
      setTokenBalanceState({ phase: 'idle', data: null, error: '' });
    }
    setTokenTransferTo('');
    setTokenTransferAmount('');
    setDetailBalanceState({ phase: 'idle', data: null, error: '' });
  }

  function closeTokenDetail() {
    setTokenDetailAddress('');
    setTokenTransferTo('');
    setTokenTransferAmount('');
    setDetailBalanceState({ phase: 'idle', data: null, error: '' });
  }

  async function handleTokenSendClick() {
    const asset = detailAsset;
    if (!asset) {
      const msg = '请先选择资产';
      setToast(msg);
      setStatusText(msg);
      return;
    }
    if (!nativeAddressInput.trim()) {
      const msg = '当前钱包地址未就绪，无法发送';
      setToast(msg);
      setStatusText(msg);
      return;
    }
    if (!tokenTransferTo.trim()) {
      const msg = '请输入 To 地址';
      setToast(msg);
      setStatusText(msg);
      return;
    }
    if (!tokenTransferAmount.trim()) {
      const msg = '请输入发送数量';
      setToast(msg);
      setStatusText(msg);
      return;
    }

    let actor = null;
    try {
      actor = await loadBackendActor();
    } catch {
      actor = null;
    }
    if (!actor) {
      const msg = '前端未连接到 backend actor';
      setToast(msg);
      setStatusText(msg);
      return;
    }

    setIsTokenSending(true);
    setStatusText(`正在发送 ${selectedNetwork} ${asset.symbol || 'Asset'} ...`);

    const sendRes = await queryTransfer(
      actor,
      selectedNetwork,
      asset,
      nativeAddressInput.trim(),
      tokenTransferTo.trim(),
      tokenTransferAmount.trim()
    );

    if (sendRes.ok) {
      const txLabel = sendRes.data?.txId ? ` tx=${sendRes.data.txId}` : '';
      const toLabel = ` to=${tokenTransferTo.trim()}`;
      const msg = sendRes.data?.accepted
        ? `发送成功${toLabel}${txLabel}`
        : `发送未执行: ${sendRes.data?.message || '后端返回 accepted=false'}`;
      setStatusText(msg);
      setToast(msg);
    } else {
      const msg = `发送失败: ${sendRes.error}`;
      setStatusText(msg);
      setToast(msg);
    }

    setIsTokenSending(false);
  }

  function handleOpenExplorerClick() {
    if (!detailAsset) {
      const msg = '当前未选中资产';
      setToast(msg);
      setStatusText(msg);
      return;
    }
    const account = nativeAddressInput.trim();
    if (!account) {
      const msg = '当前地址未就绪，无法打开区块浏览器';
      setToast(msg);
      setStatusText(msg);
      return;
    }

    const tokenAddress = detailAsset.kind === 'token' ? detailAsset.tokenAddress : '';
    const url = buildExplorerUrlFromConfig(configuredExplorer, account, tokenAddress);
    if (!url) {
      const msg = `当前网络 config 未配置区块浏览器链接: ${selectedNetwork}`;
      setToast(msg);
      setStatusText(msg);
      return;
    }

    window.open(url, '_blank', 'noopener,noreferrer');
    setStatusText(`已打开区块浏览器：${selectedConfig.title} ${detailAsset.symbol || 'Asset'}`);
  }

  return (
    <div className="app-shell">
      <div className="bg-grid" aria-hidden="true" />
      <div className="bg-orb bg-orb--a" aria-hidden="true" />
      <div className="bg-orb bg-orb--b" aria-hidden="true" />
      {toast && (
        <div className="toast" role="status" aria-live="polite">
          <span className="toast__dot" aria-hidden="true" />
          <span>{toast}</span>
        </div>
      )}

      <header className="topbar">
        <div className="brand">
          <div className="brand__eyebrow">AGENT WALLET CONTROL PLANE</div>
          <div className="brand__title">motoko-wallet-for-agent</div>
          <div className="brand__meta" title={backendCanisterId || ''}>
            <span className="brand__meta-label">Backend Canister ID</span>
            <code className="brand__meta-value">{backendCanisterId || '未读取'}</code>
          </div>
        </div>

        <div className="topbar__actions">
          <label className="network-picker">
            <span className="network-picker__label">NETWORK</span>
            <select
              className="network-picker__select"
              value={selectedNetwork}
              onChange={(event) => setSelectedNetwork(event.target.value)}
              aria-label="选择网络"
            >
              {networkOptions.map((networkId) => {
                const cfg = NETWORK_CONFIG[networkId] || fallbackNetworkConfig(networkId);
                const displayName = networkDisplayNames[networkId] || cfg.title;
                return (
                  <option key={networkId} value={networkId}>
                    {displayName}
                  </option>
                );
              })}
            </select>
          </label>

          <button type="button" className="button button--ghost" onClick={openRpcManager}>
            RPC 管理
          </button>

          <button type="button" className="button button--ghost" onClick={handleLoginClick}>
            登录
          </button>
        </div>
      </header>

      <main className="layout layout--single">
        <section className="layout__main">
          <section className="asset-grid" aria-label="资产卡片">
            <article className="panel asset-card asset-card--native">
              <header className="asset-card__head">
                <div>
                  <p className="asset-card__eyebrow">NATIVE ASSET</p>
                  <h2>{selectedConfig.nativeSymbol}</h2>
                </div>
                <span className="pill pill--glow">Primary</span>
              </header>

              <div className="asset-card__row">
                <div className="asset-card__label">地址</div>
                <div className="mono-block">{nativeAddressInput.trim() || '--'}</div>
              </div>

              <div className="asset-card__row">
                <div className="asset-card__label">余额</div>
                <div className="asset-card__balance">{nativeBalanceValue}</div>
                <div className="asset-card__sub">{nativeBalanceMeta}</div>
              </div>

              {selectedConfig.showToken && (
                <div className="asset-card__row token-vlist">
                  <div className="token-vlist__header">
                    <div className="asset-card__label token-vlist__title">Token 列表</div>
                    <span className="pill">
                      {tokenListCount ? `${tokenListCount} items` : 'No assets'}
                    </span>
                  </div>

                  {tokenListCount ? (
                    <>
                      <div
                        className="token-vlist__viewport"
                        onScroll={(event) => setTokenListScrollTop(event.currentTarget.scrollTop)}
                        role="list"
                        aria-label={`${selectedConfig.title} Token 列表`}
                      >
                        <div
                          className="token-vlist__spacer"
                          style={{ height: `${tokenListCount * TOKEN_VLIST_ROW_HEIGHT}px` }}
                        >
                          {visibleAssetItems.map((asset, offset) => {
                            const index = tokenStartIndex + offset;
                            const isActive = asset.rowKey === selectedAssetRowKey;
                            const rowBalance = asset.kind === 'native' ? null : tokenRowBalances[asset.tokenAddress];
                            const rowBalanceText =
                              asset.kind === 'native'
                                ? nativeBalanceValue
                                : rowBalance?.phase === 'loading'
                                  ? '查询中...'
                                  : rowBalance?.phase === 'error'
                                    ? '查询失败'
                                    : rowBalance?.amount || '未查询';
                            const rowBalanceMeta =
                              asset.kind === 'native'
                                ? nativeBalanceMeta
                                : rowBalance?.phase === 'error'
                                  ? rowBalance.error
                                  : rowBalance?.message ||
                                    (rowBalance?.pending
                                      ? 'pending=true'
                                      : `decimals: ${String(asset.decimals ?? '--')}`);
                            return (
                              <button
                                key={asset.rowKey}
                                type="button"
                                className={`token-vlist__item${isActive ? ' token-vlist__item--active' : ''}`}
                                style={{ transform: `translateY(${index * TOKEN_VLIST_ROW_HEIGHT}px)` }}
                                onClick={() => openTokenDetail(asset)}
                                role="listitem"
                                aria-pressed={isActive}
                              >
                                <div className="token-vlist__item-main">
                                  <div className="token-vlist__symbol">{asset.symbol || 'TOKEN'}</div>
                                  <div className="token-vlist__name">
                                    {asset.kind === 'native' ? 'Native Asset' : asset.name || 'Unnamed Token'}
                                  </div>
                                </div>
                                <div className="token-vlist__item-meta">
                                  <div className="token-vlist__addr">
                                    {asset.kind === 'native'
                                      ? `地址: ${nativeAddressInput.trim() || '--'}`
                                      : `合约: ${asset.tokenAddress}`}
                                  </div>
                                  <div className="token-vlist__decimals">
                                    精度: {String(asset.decimals ?? '--')}
                                  </div>
                                  <div className="token-vlist__balance">余额: {rowBalanceText}</div>
                                  <div className="token-vlist__balance-meta">{rowBalanceMeta}</div>
                                </div>
                              </button>
                            );
                          })}
                        </div>
                      </div>
                    </>
                  ) : (
                    <div className="mono-block">当前网络 config 未配置 Token</div>
                  )}
                </div>
              )}
            </article>
          </section>
        </section>
      </main>

      {isRpcManagerOpen && (
        <div className="rpc-manager-modal" role="dialog" aria-modal="true" aria-label="RPC 管理">
          <div className="rpc-manager-modal__backdrop" onClick={closeRpcManager} aria-hidden="true" />
          <section className="panel rpc-manager-modal__panel">
            <div className="rpc-manager-modal__shell">
              <header className="rpc-manager-modal__head">
                <div>
                  <p className="asset-card__eyebrow">RPC MANAGER</p>
                  <h2>链路 RPC 配置</h2>
                  <p className="rpc-manager-modal__sub">
                    显示所有链的默认 RPC 与当前覆盖配置。保存后会写入 canister runtime state。
                  </p>
                </div>
                <div className="rpc-manager-modal__head-actions">
                  <button
                    type="button"
                    className="button button--ghost"
                    onClick={() => void refreshRpcManagerPanel()}
                    disabled={rpcManagerLoading}
                  >
                    {rpcManagerLoading ? '刷新中...' : '刷新'}
                  </button>
                  <button type="button" className="button button--ghost" onClick={closeRpcManager}>
                    关闭
                  </button>
                </div>
              </header>

              <div className="rpc-manager-modal__body">
                {rpcManagerError && <div className="rpc-manager-alert">{rpcManagerError}</div>}

                <div className="rpc-manager-list" role="list" aria-label="RPC 配置列表">
                  {rpcManagerDisplayRows.map((row) => {
                    const hasOverride = Boolean(row.overrideRpcUrl);
                    const saveBusy = rpcSavingNetwork === row.id;
                    const removeBusy = rpcRemovingNetwork === row.id;
                    const noExternalRpc = !row.defaultRpcUrl && row.id === 'internet_computer';

                    return (
                      <section className="rpc-manager-row" key={row.id} role="listitem">
                        <div className="rpc-manager-row__top">
                          <div>
                            <div className="rpc-manager-row__title">{row.title}</div>
                            <div className="rpc-manager-row__meta">
                              <code>{row.id}</code>
                              {row.nativeSymbol ? <span>{row.nativeSymbol}</span> : null}
                              {row.addressFamily ? <span>{row.addressFamily}</span> : null}
                            </div>
                          </div>
                          <div className="rpc-manager-row__badges">
                            {hasOverride ? (
                              <span className="pill pill--glow">Override</span>
                            ) : (
                              <span className="pill">Default</span>
                            )}
                          </div>
                        </div>

                        <div className="rpc-manager-row__grid">
                          <div className="rpc-manager-kv">
                            <div className="asset-card__label">默认 RPC</div>
                            <div className="mono-block rpc-manager-kv__value">
                              {row.defaultRpcUrl || '无（该链不依赖外部 RPC 或未配置）'}
                            </div>
                          </div>

                          <div className="rpc-manager-kv">
                            <div className="asset-card__label">当前覆盖（override）</div>
                            <div className="mono-block rpc-manager-kv__value">
                              {row.overrideRpcUrl || '未设置'}
                            </div>
                          </div>

                          <div className="rpc-manager-kv rpc-manager-kv--full">
                            <div className="asset-card__label">生效中的 RPC</div>
                            <div className="mono-block rpc-manager-kv__value">
                              {row.effectiveRpcUrl || '无'}
                            </div>
                          </div>

                          <label className="rpc-manager-field rpc-manager-kv--full">
                            <span className="asset-card__label">设置 / 覆盖 RPC（HTTPS）</span>
                            <input
                              value={row.draftRpcUrl}
                              onChange={(event) => handleRpcDraftChange(row.id, event.target.value)}
                              placeholder={`为 ${row.id} 输入 https:// RPC URL`}
                              spellCheck={false}
                            />
                          </label>
                        </div>

                        <div className="rpc-manager-row__actions">
                          <button
                            type="button"
                            className="button button--primary"
                            onClick={() => void handleRpcSaveClick(row.id)}
                            disabled={saveBusy}
                          >
                            {saveBusy ? '保存中...' : hasOverride ? '更新 Override' : '添加 Override'}
                          </button>
                          <button
                            type="button"
                            className="button button--ghost"
                            onClick={() => void handleRpcRemoveClick(row.id)}
                            disabled={removeBusy || !hasOverride}
                          >
                            {removeBusy ? '删除中...' : '删除 Override'}
                          </button>
                          {noExternalRpc ? (
                            <span className="rpc-manager-row__hint">该链通常不使用外部 RPC。</span>
                          ) : null}
                        </div>
                      </section>
                    );
                  })}

                  {!rpcManagerDisplayRows.length && !rpcManagerLoading && (
                    <div className="mono-block">未读取到链配置（请确认前端已连接 backend actor）</div>
                  )}
                </div>
              </div>
            </div>
          </section>
        </div>
      )}

      {detailAsset && (
        <div className="token-detail-modal" role="dialog" aria-modal="true" aria-label="Token 详情">
          <div className="token-detail-modal__backdrop" onClick={closeTokenDetail} aria-hidden="true" />
          <section className="panel token-detail-modal__panel">
            <div className="token-detail-modal__shell">
              <header className="token-detail-modal__head">
                <div>
                  <p className="asset-card__eyebrow">ASSET DETAIL</p>
                  <h2>
                    {detailAsset.symbol || 'TOKEN'}{' '}
                    <span>{detailAsset.kind === 'native' ? 'Native Asset' : detailAsset.name || ''}</span>
                  </h2>
                </div>
                <div className="token-detail-modal__head-actions">
                  <span className="pill">{selectedConfig.title}</span>
                  <span className={`pill ${detailAsset.kind === 'native' ? 'pill--glow' : ''}`}>
                    {detailAsset.kind === 'native' ? 'Native' : 'Token'}
                  </span>
                  <button type="button" className="button button--ghost" onClick={closeTokenDetail}>
                    关闭
                  </button>
                </div>
              </header>

              <div className="token-detail-modal__body">
                <section className="token-detail-card">
                  <div className="token-detail-card__title">资产信息</div>

                  <div className="token-detail-kv">
                    <div className="asset-card__label">当前钱包地址（From）</div>
                    <div className="mono-block">{nativeAddressInput.trim() || '未获取到当前钱包地址'}</div>
                  </div>

                  <div className="token-detail-kv">
                    <div className="asset-card__label">
                      {detailAsset.kind === 'native' ? '资产类型' : 'Token 合约地址'}
                    </div>
                    <div className="mono-block">
                      {detailAsset.kind === 'native' ? '原生币（无合约地址）' : detailAsset.tokenAddress}
                    </div>
                  </div>

                  <div className="token-detail-stats">
                    <div className="token-detail-stat">
                      <div className="asset-card__label">精度</div>
                      <div className="mono-block">{String(detailAsset.decimals ?? '--')}</div>
                    </div>
                    <div className="token-detail-stat token-detail-stat--balance">
                      <div className="asset-card__label">余额</div>
                      <div className="mono-block token-detail-stat__balance">
                        {detailBalanceValue}
                      </div>
                      <div className="asset-card__sub">
                        {detailBalanceMeta}
                      </div>
                    </div>
                  </div>

                  <div className="token-detail-card__hint">
                    当前地址与币种信息来自后端 canister 接口与 config 配置。
                  </div>

                  <div className="token-detail-card__actions">
                    <button
                      type="button"
                      className="button button--ghost"
                      onClick={handleOpenExplorerClick}
                    >
                      区块浏览器查看
                    </button>
                  </div>
                </section>

                <section className="token-detail-card token-detail-card--send">
                  <div className="token-detail-card__title">发送交易</div>

                  <label className="token-detail-modal__field">
                    <span className="asset-card__label">To 地址</span>
                    <input
                      value={tokenTransferTo}
                      onChange={(event) => setTokenTransferTo(event.target.value)}
                      placeholder="请输入接收方地址"
                    />
                  </label>

                  <label className="token-detail-modal__field">
                    <span className="asset-card__label">数量</span>
                    <input
                      value={tokenTransferAmount}
                      onChange={(event) => setTokenTransferAmount(event.target.value)}
                      placeholder={`请输入 ${detailAsset.symbol || 'Asset'} 数量`}
                    />
                  </label>

                  <div className="token-detail-send-preview">
                    <div className="token-detail-send-preview__row">
                      <span>网络</span>
                      <strong>{selectedConfig.title}</strong>
                    </div>
                    <div className="token-detail-send-preview__row">
                      <span>资产</span>
                      <strong>{detailAsset.symbol || 'Asset'}</strong>
                    </div>
                    <div className="token-detail-send-preview__row">
                      <span>From</span>
                      <code>{nativeAddressInput.trim() || '--'}</code>
                    </div>
                    <div className="token-detail-send-preview__row">
                      <span>To</span>
                      <code>{tokenTransferTo.trim() || '--'}</code>
                    </div>
                  </div>

                  <div className="token-detail-modal__actions">
                    <button
                      type="button"
                      className="button button--primary"
                      onClick={handleTokenSendClick}
                      disabled={isTokenSending}
                    >
                      {isTokenSending ? '发送中...' : '发送'}
                    </button>
                  </div>
                </section>
              </div>
            </div>
          </section>
        </div>
      )}
    </div>
  );
}
