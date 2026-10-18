# Technical Architecture Document: JAGAD Vault

| Field | Value |
|---|---|
| Product Name | JAGAD |
| Token Ticker | $JGAD |
| Version | 0.2.0 |
| Status | Draft |
| Date | Oktober 2026 |
| Owner | Mufti Zaka |
| Related Document | PRD.md v0.2.0 |
| Document Type | Technical Architecture |

---

## 1. Purpose

Dokumen ini menjelaskan **bagaimana JAGAD dibangun secara teknis**.

Kalau `PRD.md` menjawab:

- WHAT: produk apa yang dibangun?
- WHY: kenapa produk ini dibutuhkan?

Maka `ARCHITECTURE.md` menjawab:

- HOW: sistemnya gimana cara kerjanya?
- WITH WHAT: tech stack, kontrak, oracle, DEX, automation, dan testing strategy-nya apa?

Arsitektur ini dirancang untuk MVP JAGAD v1.0 sesuai PRD v0.2.0:

- Single-chain deployment di Base.
- Deposit/redeem USDC.
- Multi-asset vault basket (55/25/20).
- Automatic allocation.
- Threshold-based rebalancing.
- Yield/revenue sweep.
- Oracle-backed NAV dengan multi-source validation.
- Virtual shares anti-inflation attack.
- Partial redemption + emergency proportional redemption.
- Multisig admin control dengan timelock.
- Pause mechanism.
- Foundry testing.

---

## 2. Architecture Principles

### 2.1 Security First

JAGAD menyimpan aset pengguna. Karena itu, arsitektur harus mengutamakan:

- aset disimpan di contract vault, bukan wallet admin;
- semua fungsi privileged dilindungi access control;
- oracle harus divalidasi freshness dan outlier;
- rebalancing dan sweep harus punya slippage protection;
- vault harus bisa di-pause saat terjadi anomali;
- invariant solvabilitas harus selalu terjaga;
- virtual shares mencegah inflation/donation attack;
- emergency proportional redemption melindungi user saat paused.

### 2.2 Modularity

Sistem dipecah menjadi modul-modul kecil supaya mudah diuji dan tidak ada satu kontrak raksasa yang sulit diaudit.

Modul utama:

- Token vault share: `JagadToken`
- Core vault: `JagadVault`
- Rebalancing: `Rebalancer`
- Yield sweep: `YieldSweeper`
- Oracle reading: `OracleReader`
- Treasury/fee: `Treasury`
- Asset registry: `AssetRegistry`
- Redemption queue: `RedemptionQueue`

### 2.3 Deterministic Accounting

NAV, bobot aset, drift, fee, dan hasil swap harus bisa dihitung ulang secara on-chain atau melalui indexer.

Semua aksi penting harus memancarkan event:

- deposit;
- redeem;
- mint;
- burn;
- rebalance;
- yield sweep;
- parameter update;
- pause/unpause;
- partial redemption queued;
- emergency redemption.

### 2.4 Gas Efficiency

Karena JAGAD melakukan swap otomatis, arsitektur harus menghindari operasi yang boros gas tanpa manfaat.

Prinsip:

- rebalance hanya jika drift > threshold;
- sweep hanya jika idle yield > minimum threshold;
- ada cooldown antar rebalance;
- ada max slippage;
- batch swap: jual semua dulu jadi USDC, baru beli;
- menggunakan Layer 2 Base untuk menekan gas fee.

### 2.5 Upgradeability with Control

MVP menggunakan pola upgradeable yang aman supaya bug kritis bisa diperbaiki tanpa migrasi manual yang berisiko.

Keputusan:

- `JagadVault` menggunakan UUPS upgradeable pattern.
- Upgrade hanya bisa dilakukan oleh TimelockController yang dikontrol multisig.
- Storage layout harus aman menggunakan storage gap.
- `JagadToken` sebaiknya immutable setelah deploy, kecuali ada alasan kuat untuk upgradeable.

### 2.6 User Protection

Arsitektur harus melindungi user dari skenario terburuk:

- partial redemption jika likuiditas tidak cukup;
- emergency proportional redemption saat vault paused;
- redemption cap per window di soft launch;
- operating reserve USDC untuk redemption normal;
- liquidity gate per aset.

---

## 3. High-Level System Context

```mermaid
flowchart LR
    User([User Wallet]) -->|Deposit USDC| dApp[JAGAD dApp]
    dApp -->|deposit()| Vault[JagadVault]
    Vault -->|mint| Token[$JGAD Token]
    Vault -->|swap| DEX[DEX Router / Aggregator]
    Vault -->|read price| Oracle[OracleReader]
    Oracle --> Chainlink[Chainlink Feeds]
    Oracle --> Pyth[Pyth Cross-check]

    Keeper[Chainlink Automation / Gelato] -->|rebalance()| Rebalancer[Rebalancer]
    Keeper -->|sweepYield()| Sweeper[YieldSweeper]
    Rebalancer --> Vault
    Sweeper --> Vault

    Admin([Multisig Safe]) --> Timelock[TimelockController]
    Timelock --> Vault
    Timelock --> AssetRegistry[AssetRegistry]
    Timelock --> Treasury[Treasury]

    Vault --> Events[On-chain Events]
    Events --> Subgraph[Indexer / Dashboard]

    RedemptionQueue[RedemptionQueue] --> Vault
    EmergencyRedemption[Emergency Proportional Redemption] --> Vault
```

---

## 4. Blockchain and Network Choice

### Primary Network

**Base Mainnet**

Alasan:

- EVM compatible.
- Gas fee rendah dibanding Ethereum L1.
- Ekosistem DeFi dan RWA berkembang.
- Akses ke DEX seperti Aerodrome dan Uniswap.
- Support oracle mainstream.

### Test Network

**Base Sepolia**

Digunakan untuk:

- deploy kontrak;
- simulasi deposit/redeem;
- test rebalancing;
- test yield sweep;
- test partial redemption;
- test emergency proportional redemption;
- test oracle failure;
- dry run frontend.

### Alternative Network

**Arbitrum One**

Dipertimbangkan jika:

- aset RWA tertentu lebih likuid di Arbitrum;
- integrasi oracle/DEX lebih stabil;
- kebutuhan institusional lebih cocok di Arbitrum.

Untuk MVP, satu jaringan dulu. Multi-chain keluar dari scope.

---

## 5. Tech Stack

### 5.1 Smart Contract Stack

| Component | Technology | Reason |
|---|---|---|
| Language | Solidity ^0.8.26 | Standar modern, built-in overflow protection. |
| Framework | Foundry | Fast testing, fuzzing, invariant testing, cheatcodes. |
| Token Standard | ERC-20 | Kompatibel wallet, DEX, dashboard. |
| Vault Pattern | ERC-4626-inspired custom vault | Standar vault share, tapi perlu fleksibilitas multi-aset. |
| Security Library | OpenZeppelin Contracts | AccessControl, Pausable, ReentrancyGuard, UUPS, SafeERC20. |
| Upgradeability | UUPS Proxy | Controlled upgrades via timelock. |
| Math | Fixed-point WAD / BPS | Hindari floating point, gunakan integer math. |

### 5.2 Oracle Stack

| Component | Technology | Reason |
|---|---|---|
| Primary Oracle | Chainlink Data Feeds | Standar industri, luas didukung. |
| Secondary Oracle | Pyth Network | Cross-check harga, mengurangi single oracle risk. |
| Price Validation | Custom OracleReader | Freshness check, deviation check, stale rejection. |
| TWAP | Custom TWAP implementation | Untuk minAmountOut saat rebalance, bukan spot price. |

### 5.3 DEX / Swap Stack

| Component | Technology | Reason |
|---|---|---|
| Primary Router | 1inch Fusion / Router | Aggregasi likuiditas, mengurangi slippage. |
| Secondary Router | Uniswap Universal Router | Fallback jika 1inch unavailable. |
| Base-native DEX | Aerodrome | Likuiditas lokal Base. |
| Slippage Control | minAmountOut / maxAmountIn dari TWAP | Proteksi terhadap price impact dan sandwich attack. |

### 5.4 Automation Stack

| Component | Technology | Reason |
|---|---|---|
| Keeper | Chainlink Automation | Terintegrasi dengan oracle ecosystem. |
| Alternative Keeper | Gelato Network | Fleksibel untuk custom check logic. |

### 5.5 Frontend Stack

| Component | Technology | Reason |
|---|---|---|
| Framework | Next.js | SSR/SSG, ekosistem React matang. |
| Language | TypeScript | Type safety. |
| Web3 Library | Wagmi + Viem | Modern Ethereum interaction. |
| Wallet Connection | RainbowKit / ConnectKit | UX wallet cepat. |
| Styling | Tailwind CSS | Cepat dan konsisten. |
| Charts | Recharts / Visx | Visualisasi NAV dan alokasi. |
| Geo-blocking | Cloudflare / Vercel middleware | Jurisdiction gating di MVP. |

### 5.6 Indexing / Analytics

| Component | Technology | Reason |
|---|---|---|
| MVP | Direct RPC reads via Viem | Simple, cukup untuk dashboard minimal. |
| Later | The Graph subgraph | Query history lebih cepat dan scalable. |
| Optional | Custom indexer | Untuk rebalance/sweep analytics lanjutan. |

---

## 6. Repository Structure

```text
jagad-vault/
├── PRD.md
├── ARCHITECTURE.md
├── TOKENOMICS.md
├── SECURITY.md
├── RUNBOOK.md
├── README.md
├── foundry.toml
├── .env.example
├── .github/
│   └── workflows/
│       ├── test.yml
│       ├── fuzz.yml
│       └── security.yml
├── script/
│   ├── Deploy.s.sol
│   ├── ConfigureAssets.s.sol
│   ├── ConfigureOracles.s.sol
│   └── Verify.s.sol
├── src/
│   ├── interfaces/
│   │   ├── IJagadVault.sol
│   │   ├── IRebalancer.sol
│   │   ├── IYieldSweeper.sol
│   │   ├── IOracleReader.sol
│   │   ├── IAssetRegistry.sol
│   │   ├── ITreasury.sol
│   │   └── IRedemptionQueue.sol
│   ├── libraries/
│   │   ├── RebalancerMath.sol
│   │   ├── NAVMath.sol
│   │   └── SafePrice.sol
│   ├── mocks/
│   │   ├── MockERC20.sol
│   │   ├── MockChainlinkAggregator.sol
│   │   ├── MockPyth.sol
│   │   └── MockDEXRouter.sol
│   ├── JagadToken.sol
│   ├── JagadVault.sol
│   ├── Rebalancer.sol
│   ├── YieldSweeper.sol
│   ├── OracleReader.sol
│   ├── AssetRegistry.sol
│   ├── Treasury.sol
│   └── RedemptionQueue.sol
├── test/
│   ├── unit/
│   │   ├── JagadToken.t.sol
│   │   ├── JagadVault.deposit.t.sol
│   │   ├── JagadVault.redeem.t.sol
│   │   ├── JagadVault.emergencyRedeem.t.sol
│   │   ├── Rebalancer.t.sol
│   │   ├── YieldSweeper.t.sol
│   │   ├── OracleReader.t.sol
│   │   └── RedemptionQueue.t.sol
│   ├── integration/
│   │   ├── DepositToAllocation.t.sol
│   │   ├── RebalanceFlow.t.sol
│   │   ├── SweepFlow.t.sol
│   │   ├── RedeemFlow.t.sol
│   │   ├── PartialRedemption.t.sol
│   │   └── EmergencyRedemption.t.sol
│   ├── fuzz/
│   │   ├── MarketCrash.t.sol
│   │   ├── OracleManipulation.t.sol
│   │   ├── SlippageAttack.t.sol
│   │   └── InflationAttack.t.sol
│   └── invariant/
│       ├── Solvency.t.sol
│       ├── WeightInvariant.t.sol
│       ├── PauseInvariant.t.sol
│       └── VirtualSharesInvariant.t.sol
└── deployments/
    ├── base-sepolia.json
    └── base-mainnet.json
```

---

## 7. Smart Contract Modules

### 7.1 `JagadToken.sol`

Token ERC-20 yang merepresentasikan kepemilikan share vault.

Responsibilities:

- Mint $JGAD saat user deposit.
- Burn $JGAD saat user redeem.
- Hanya `JagadVault` yang boleh mint/burn.
- Emit standard ERC-20 events.
- Optional: permit support untuk UX.

Key functions:

```solidity
function mint(address to, uint256 amount) external onlyVault;
function burn(address from, uint256 amount) external onlyVault;
```

Design decision:

- MVP: token immutable.
- Tidak ada tax, tidak ada rebase, tidak ada blacklist.
- Transferability penuh untuk aset crypto-native.
- Jika ada aset RWA whitelist, pembatasan dilakukan di level vault/asset adapter, bukan token $JGAD.

---

### 7.2 `JagadVault.sol`

Kontrak utama yang menyimpan aset underlying dan mengelola share accounting.

Responsibilities:

- Terima deposit USDC.
- Hitung NAV dengan virtual shares.
- Mint/burn $JGAD.
- Simpan aset basket.
- Panggil allocator/rebalancer.
- Enforce fee.
- Support pause.
- Support partial redemption.
- Support emergency proportional redemption.
- Emit events.
- Expose view functions untuk dashboard.

Core state:

```solidity
IERC20 public immutable usdc;
IJagadToken public immutable jagadToken;
IAssetRegistry public assetRegistry;
IOracleReader public oracleReader;
IRebalancer public rebalancer;
IYieldSweeper public yieldSweeper;
ITreasury public treasury;
IRedemptionQueue public redemptionQueue;

uint256 public depositFeeBps;
uint256 public redeemFeeBps;
uint256 public managementFeeBps;
uint256 public driftThresholdBps;
uint256 public rebalanceCooldown;
uint256 public lastRebalanceTimestamp;
uint256 public operatingReserveBps;
uint256 public minDepositAmount;
uint256 public redemptionCapPerWindow;
uint256 public redemptionWindowSeconds;
```

Key functions:

```solidity
function deposit(uint256 usdcAmount) external whenNotPaused returns (uint256 jagadAmount);
function redeem(uint256 jagadAmount) external whenNotPaused returns (uint256 usdcAmount);
function emergencyRedeem(uint256 jagadAmount) external whenPaused returns (uint256);
function getNav() public view returns (uint256 totalValueWad, uint256 navPerShareWad);
function getTotalAssetsValue() public view returns (uint256);
function getAssetValue(address token) public view returns (uint256);
function getOperatingReserve() public view returns (uint256);
function pause() external onlyPauser;
function unpause() external onlyPauser;
```

#### NAV Calculation dengan Virtual Shares

```solidity
function getNav() public view returns (uint256 totalValueWad, uint256 navPerShareWad) {
    totalValueWad = getTotalAssetsValue();
    uint256 supply = jagadToken.totalSupply();
    
    // Virtual shares: mencegah inflation/donation attack
    uint256 virtualShares = supply + 10 ** DECIMALS_OFFSET;
    uint256 virtualAssets = totalValueWad + 1;
    
    navPerShareWad = (virtualAssets * WAD) / virtualShares;
}
```

#### Deposit Flow:

1. User approve USDC ke vault.
2. Vault validasi minimum deposit (10 USDC).
3. Vault transfer USDC dari user.
4. Vault hitung deposit fee.
5. Vault kirim fee ke Treasury.
6. Vault hitung net deposit.
7. Vault hitung NAV sebelum alokasi (dengan virtual shares).
8. Vault mint $JGAD berdasarkan net deposit / NAV per share.
9. Vault alokasikan net USDC ke basket melalui allocator/rebalancer.
10. Vault emit `Deposited` dan `SharesMinted`.

#### Redeem Flow:

1. User transfer $JGAD ke vault.
2. Vault hitung underlying value berdasarkan NAV.
3. Vault hitung redeem fee.
4. Vault cek apakah likuiditas cukup untuk full redemption.
5. Jika cukup:
   - Vault burn $JGAD.
   - Vault jual aset proporsional ke USDC.
   - Vault kirim net USDC ke user.
   - Vault emit `Redeemed` dan `SharesBurned`.
6. Jika tidak cukup:
   - Vault hitung berapa yang bisa diredeem sekarang.
   - Vault burn $JGAD proporsional.
   - Vault kirim USDC sebagian ke user.
   - Vault masukkan sisa ke RedemptionQueue.
   - Vault emit `PartialRedemption` dan `RedemptionQueued`.

#### Emergency Proportional Redemption Flow:

1. Hanya bisa dipanggil saat vault paused.
2. User transfer $JGAD ke vault.
3. Vault hitung porsi user terhadap total supply.
4. Vault burn $JGAD user.
5. Vault transfer aset underlying langsung ke user sesuai porsi (tanpa swap).
6. Vault emit `EmergencyRedeemed`.

Important invariant:

```text
totalAssetsValue >= totalSharesValue
```

atau lebih tepatnya:

```text
sum(asset balances valued at oracle price) >= outstanding $JGAD supply * navPerShare
```

Karena NAV dihitung dari aset, invariant utama adalah vault tidak boleh berjanji lebih dari yang dimiliki.

---

### 7.3 `AssetRegistry.sol`

Menyimpan daftar aset yang boleh dipegang vault beserta metadata.

Responsibilities:

- Register asset token address.
- Set target weight.
- Set oracle feed.
- Enable/disable asset.
- Store decimals dan tier.
- Prevent duplicate assets.
- Store liquidity gate parameters.

Asset struct:

```solidity
struct AssetConfig {
    address token;
    uint8 decimals;
    uint256 targetWeightBps;
    address priceFeed;
    bool enabled;
    uint8 tier;
    uint256 minLiquidityUsd;
    uint256 maxSlippageBps;
    bool isNumeraire;
}
```

Tier enum:

```solidity
enum Tier {
    BUNKER,
    ENGINE,
    GLOBAL_PROXY
}
```

Example initial config:

| Token | Tier | Target Weight |
|---|---|---:|
| USDC | BUNKER | 30% |
| PAXG | BUNKER | 15% |
| sSilver | BUNKER | 10% |
| WBTC | ENGINE | 25% |
| Energy Proxy | GLOBAL_PROXY | 7% |
| Mining Proxy | GLOBAL_PROXY | 7% |
| REIT Proxy | GLOBAL_PROXY | 3% |
| Agri Proxy | GLOBAL_PROXY | 3% |

Validation:

```solidity
require(sum(targetWeightBps) == 10_000, "Invalid weights");
```

Liquidity gate logic:

```solidity
function checkLiquidity(address token) external view returns (bool) {
    AssetConfig memory config = assets[token];
    uint256 currentLiquidity = IERC20(token).balanceOf(liquidityPool);
    return currentLiquidity >= config.minLiquidityUsd;
}
```

Jika likuiditas di bawah threshold, vault otomatis mengurangi bobot aset tersebut dan mengalihkan ke USDC.

---

### 7.4 `OracleReader.sol`

Wrapper untuk membaca dan memvalidasi harga.

Responsibilities:

- Baca harga dari Chainlink.
- Baca harga dari Pyth sebagai cross-check.
- Normalisasi decimals ke 18 digit.
- Tolak harga stale.
- Tolak harga outlier.
- Expose TWAP jika tersedia.
- Bandingkan harga antar oracle.

Key functions:

```solidity
function getNormalizedPrice(address feed) external view returns (uint256 priceWad);
function getPriceWithMetadata(address feed) external view returns (uint256 priceWad, uint256 updatedAt, bool valid);
function getTWAP(address feed, uint256 windowSeconds) external view returns (uint256 twapWad);
function validatePrice(address feed, uint256 price, uint256 timestamp) internal view returns (bool);
function crossCheckOracles(address chainlinkFeed, address pythFeed) external view returns (bool isValid, uint256 deviationBps);
```

Freshness rule:

```text
block.timestamp - priceTimestamp <= maxStalenessSeconds
```

Default:

```text
maxStalenessSeconds = 3600
```

Cross-check rule:

```text
abs(chainlinkPrice - pythPrice) / chainlinkPrice <= maxOracleDeviationBps
```

Default:

```text
maxOracleDeviationBps = 200 // 2%
```

Jika deviation terlalu besar:

- revert untuk operasi kritis;
- atau trigger circuit breaker dan pause otomatis jika diimplementasikan.

TWAP implementation:

```solidity
function getTWAP(address feed, uint256 windowSeconds) external view returns (uint256) {
    // Ambil harga dari beberapa round terakhir
    // Hitung rata-rata tertimbang berdasarkan waktu
    // Return harga rata-rata dalam WAD
}
```

---

### 7.5 `Rebalancer.sol`

Menjaga alokasi vault tetap dekat dengan target basket.

Responsibilities:

- Hitung current weight tiap aset.
- Hitung drift terhadap target weight.
- Tentukan apakah rebalance perlu dijalankan.
- Jual aset overweight.
- Beli aset underweight.
- Enforce slippage protection dengan TWAP.
- Batch swap untuk efisiensi gas.
- Emit rebalance events.

Math library:

`RebalancerMath.sol`

```solidity
function calculateDriftBps(
    uint256 currentValue,
    uint256 totalValue,
    uint256 targetWeightBps
) internal pure returns (int256 driftBps);
```

Formula:

```text
currentWeightBps = currentValue * 10_000 / totalValue
driftBps = currentWeightBps - targetWeightBps
```

Trigger:

```text
abs(driftBps) > driftThresholdBps
```

Default:

```text
driftThresholdBps = 500 // 5%
```

#### Batch Swap Logic:

```text
1. Hitung semua aset yang overweight dan underweight.
2. Jual SEMUA aset overweight ke USDC dulu (batch sell).
3. Kumpulkan semua USDC hasil penjualan.
4. Beli SEMUA aset underweight dari USDC (batch buy).
5. Cek post-rebalance deviation.
6. Emit event.
```

Ini mengurangi jumlah swap dari N×2 menjadi 2 batch operations.

Safety rules:

- Tidak boleh rebalance saat paused.
- Tidak boleh rebalance jika oracle stale.
- Tidak boleh rebalance jika cooldown belum lewat.
- Tidak boleh rebalance jika estimated gas cost > benefit.
- Setiap swap harus punya `minAmountOut` dari TWAP.
- Tidak boleh menjual aset di bawah `minLiquidityUsd` tanpa override multisig.
- Max slippage per swap: 100 bps (1%).

---

### 7.6 `YieldSweeper.sol`

Mengompounding yield/revenue yang mengendap di vault.

Catatan: Tidak menggunakan istilah "dividend" untuk menghindari klasifikasi security.

Responsibilities:

- Deteksi idle USDC/DAI hasil yield/revenue.
- Jalankan sweep jika balance melebihi threshold.
- Reinvest ke target aset.
- Emit sweep events.
- Jaga agar sweep tidak mengganggu solvabilitas.

Default reinvestment split:

| Destination | Split |
|---|---:|
| Tier 1 | 60% |
| Tier 2 | 30% |
| Tier 3 | 10% |

Alternative aggressive split:

| Destination | Split |
|---|---:|
| Tier 1 | 50% |
| Tier 2 | 30% |
| Tier 3 | 20% |

Parameter ini bisa diubah oleh multisig.

Minimum sweep threshold:

```text
default = $1,000 equivalent USDC
```

Logic:

1. Keeper panggil `canSweep()`.
2. Contract cek idle balance.
3. Jika idle balance < threshold, return false.
4. Jika true, keeper panggil `sweepYield()`.
5. Contract swap idle USDC ke target aset sesuai split.
6. Emit `YieldSwept`.

Accounting note:

Karena sulit membedakan secara on-chain apakah USDC berasal dari principal atau yield, MVP menggunakan pendekatan:

```text
idleUsdcForSweep = usdcBalance - operatingReserve
```

`operatingReserve` adalah USDC minimum yang disimpan untuk fee, gas, dan redeem normal. Default: 20% dari total vault value.

---

### 7.7 `Treasury.sol`

Mengelola fee dan reserve operasional.

Responsibilities:

- Terima deposit fee.
- Terima redeem fee.
- Terima management fee jika diimplementasikan.
- Menyimpan gas reserve.
- Membatasi withdrawal treasury.
- Emit fee events.

Fee destinations:

| Fee Type | Destination |
|---|---|
| Deposit fee | Treasury / gas reserve |
| Redeem fee | Treasury / gas reserve |
| Management fee | Treasury |
| Yield surplus | Gas reserve / protocol revenue |

Safety:

- Treasury withdrawal hanya oleh multisig.
- Ada cap withdrawal per periode.
- Tidak boleh withdraw saat vault paused kecuali emergency procedure.

---

### 7.8 `RedemptionQueue.sol`

Mengelola partial redemption ketika likuiditas tidak cukup.

Responsibilities:

- Terima sisa redemption yang tidak bisa diproses langsung.
- Simpan queue per user.
- Proses queue ketika likuiditas tersedia.
- Emit queue events.

Key functions:

```solidity
function enqueue(address user, uint256 jagadAmount, uint256 expectedUsdc) external onlyVault;
function processQueue() external onlyKeeper;
function getQueuePosition(address user) external view returns (uint256 position, uint256 amount);
function cancelQueue(address user) external onlyVault;
```

Queue processing:

1. Keeper panggil `processQueue()` secara periodik.
2. Contract cek apakah likuiditas cukup untuk proses queue berikutnya.
3. Jika cukup, proses redemption dan kirim USDC ke user.
4. Jika tidak, tunggu sampai likuiditas tersedia.
5. Emit `QueueProcessed`.

---

## 8. Data Model and Units

### 8.1 Decimal Convention

Semua perhitungan internal menggunakan 18 decimals.

```solidity
uint256 constant WAD = 1e18;
uint256 constant BPS_BASE = 10_000;
uint256 constant DECIMALS_OFFSET = 3; // untuk virtual shares
```

Token external bisa punya decimals berbeda, misalnya:

- USDC: 6 decimals.
- WBTC: 8 decimals.
- PAXG: 18 decimals.
- Some RWA tokens: custom decimals.

Maka semua balance dan harga dinormalisasi ke WAD sebelum dihitung.

### 8.2 Price Representation

Harga aset dinyatakan sebagai USD per token dalam 18 decimals.

Contoh:

```text
PAXG price = $2,700 per token
priceWad = 2,700 * 1e18
```

### 8.3 Asset Value Formula

```text
assetValueWad = tokenBalance * priceWad / 10 ** tokenDecimals
```

### 8.4 Total Vault Value

```text
totalVaultValueWad = sum(assetValueWad for all enabled assets)
```

### 8.5 NAV Per Share dengan Virtual Shares

```text
virtualShares = totalJagadSupply + 10 ** DECIMALS_OFFSET
virtualAssets = totalVaultValueWad + 1
navPerShareWad = virtualAssets * WAD / virtualShares
```

Jika `totalJagadSupply == 0`, maka:

```text
navPerShareWad = WAD
```

artinya 1 $JGAD = 1 USD equivalent saat vault kosong.

### 8.6 Operating Reserve

```text
operatingReserveWad = totalVaultValueWad * operatingReserveBps / BPS_BASE
```

Default `operatingReserveBps = 2000` (20%).

---

## 9. Core Flows

### 9.1 Deposit Flow

```mermaid
sequenceDiagram
    participant User
    participant dApp
    participant Vault as JagadVault
    participant Token as JagadToken
    participant Registry as AssetRegistry
    participant Oracle as OracleReader
    participant DEX as DEX Router
    participant Treasury

    User->>dApp: Enter USDC amount
    User->>Vault: approve USDC
    User->>Vault: deposit(usdcAmount)
    Vault->>Vault: validate minimum deposit
    Vault->>Vault: transfer USDC from user
    Vault->>Treasury: send deposit fee
    Vault->>Oracle: get NAV prices
    Vault->>Registry: get target weights
    Vault->>Vault: calculate shares to mint (virtual shares)
    Vault->>Token: mint(user, shares)
    Vault->>DEX: allocate net USDC to basket
    Vault-->>User: emit Deposited, SharesMinted, Allocated
```

Acceptance criteria:

- User menerima $JGAD.
- Vault memegang kombinasi aset sesuai target dalam toleransi.
- Fee tercatat.
- Event teremit.
- Jika swap gagal, deposit harus revert atau memiliki mekanisme refund yang aman.

Recommended MVP behavior:

- Deposit dan allocation atomic.
- Jika allocation gagal, seluruh transaksi revert.
- Tidak ada partial deposit yang tertinggal tanpa share.

---

### 9.2 Redeem Flow

```mermaid
sequenceDiagram
    participant User
    participant dApp
    participant Vault as JagadVault
    participant Token as JagadToken
    participant Oracle as OracleReader
    participant DEX as DEX Router
    participant Queue as RedemptionQueue

    User->>dApp: Enter $JGAD amount
    User->>Token: approve $JGAD if needed
    User->>Vault: redeem(jagadAmount)
    Vault->>Oracle: get prices
    Vault->>Vault: calculate USDC value
    Vault->>Vault: check liquidity
    alt liquidity sufficient
        Vault->>Token: burn(user, jagadAmount)
        Vault->>DEX: sell proportional assets to USDC
        Vault->>User: transfer net USDC
        Vault-->>User: emit Redeemed, SharesBurned
    else liquidity insufficient
        Vault->>Token: burn(user, partialJagadAmount)
        Vault->>DEX: sell partial assets to USDC
        Vault->>User: transfer partial USDC
        Vault->>Queue: enqueue(user, remainingJagadAmount)
        Vault-->>User: emit PartialRedemption, RedemptionQueued
    end
```

Acceptance criteria:

- $JGAD dibakar.
- Aset dijual proporsional.
- User menerima USDC setelah fee.
- Vault tetap solvent.
- Jika likuiditas tidak cukup, partial redemption + queue.
- User tidak pernah kehilangan aset karena redeem gagal.

---

### 9.3 Emergency Proportional Redemption Flow

```mermaid
sequenceDiagram
    participant User
    participant dApp
    participant Vault as JagadVault
    participant Token as JagadToken
    participant Registry as AssetRegistry

    User->>dApp: Enter $JGAD amount
    User->>Vault: emergencyRedeem(jagadAmount)
    Note over Vault: Only callable when paused
    Vault->>Token: burn(user, jagadAmount)
    Vault->>Registry: get all enabled assets
    loop for each asset
        Vault->>Vault: calculate user's proportional share
        Vault->>User: transfer proportional asset amount
    end
    Vault-->>User: emit EmergencyRedeemed
```

Acceptance criteria:

- Hanya bisa dipanggil saat vault paused.
- User menerima aset underlying langsung tanpa swap.
- Tidak ada slippage karena tidak ada swap.
- Vault tetap solvent setelah emergency redeem.

---

### 9.4 Rebalancing Flow

```mermaid
sequenceDiagram
    participant Keeper
    participant Rebalancer
    participant Vault
    participant Oracle
    participant Registry
    participant DEX

    Keeper->>Rebalancer: checkAndRebalance()
    Rebalancer->>Vault: get asset balances
    Rebalancer->>Oracle: get normalized prices
    Rebalancer->>Registry: get target weights
    Rebalancer->>Rebalancer: calculate drift
    alt max drift > threshold
        Rebalancer->>DEX: batch sell overweight assets to USDC
        Rebalancer->>DEX: batch buy underweight assets from USDC
        Rebalancer->>Vault: update allocation
        Rebalancer-->>Keeper: emit Rebalanced
    else drift <= threshold
        Rebalancer-->>Keeper: no action
    end
```

Trigger condition:

```solidity
if (
    !paused &&
    block.timestamp >= lastRebalanceTimestamp + cooldown &&
    maxAbsDriftBps > driftThresholdBps &&
    oraclePricesValid
) {
    executeRebalance();
}
```

Post-condition:

```text
setelah rebalance sukses, maxAbsDriftBps <= driftThresholdBps + allowedSlippageTolerance
```

---

### 9.5 Yield Sweep Flow

```mermaid
sequenceDiagram
    participant Keeper
    participant Sweeper as YieldSweeper
    participant Vault
    participant Oracle
    participant DEX

    Keeper->>Sweeper: canSweep()
    Sweeper->>Vault: get idle USDC balance
    Sweeper->>Sweeper: compare with min sweep threshold
    alt idle balance >= threshold
        Keeper->>Sweeper: sweepYield()
        Sweeper->>DEX: swap idle USDC to target assets
        Sweeper->>Vault: record sweep
        Sweeper-->>Keeper: emit YieldSwept
    else below threshold
        Sweeper-->>Keeper: no action
    end
```

Purpose:

- Yield/revenue tidak menganggur.
- NAV vault meningkat secara organik.
- Gas fee tidak dimakan oleh sweep recehan.

---

## 10. Asset Adapter Pattern

Beberapa aset mungkin tidak bisa diperlakukan sama seperti ERC-20 biasa.

Contoh:

- tokenized stock mungkin whitelist-only;
- synthetic asset mungkin punya mint/burn khusus;
- REIT token mungkin punya transfer restriction;
- some RWA tokens mungkin tidak listing di DEX publik.

Maka arsitektur mendukung `IAssetAdapter`.

```solidity
interface IAssetAdapter {
    function balanceOf(address assetOwner, address token) external view returns (uint256);
    function swapToNumeraire(address token, uint256 amount, uint256 minOut) external returns (uint256);
    function swapFromNumeraire(address token, uint256 usdcAmount, uint256 minOut) external returns (uint256);
    function isTransferRestricted(address from, address to) external view returns (bool);
}
```

Untuk MVP crypto-native:

- gunakan `StandardERC20Adapter`.

Untuk RWA terbatas:

- gunakan `WhitelistedRWAAdapter`.
- vault hanya boleh hold jika address vault sudah whitelist.
- redeem mungkin perlu delay atau partial liquidity.

Keputusan MVP:

- Tier 1 dan Tier 2 memakai standard adapter.
- Tier 3 memakai adapter yang tergantung ketersediaan aset:
  - jika synthetic/liquid: standard adapter;
  - jika RWA whitelist: restricted adapter;
  - jika tidak cukup likuid: bobot diturunkan atau asset disabled.

---

## 11. Access Control Model

### Roles

| Role | Holder | Permission |
|---|---|---|
| DEFAULT_ADMIN_ROLE | TimelockController | Ultimate admin. |
| PAUSER_ROLE | Security council / multisig | Pause/unpause vault. |
| KEEPER_ROLE | Chainlink Automation / Gelato | Call rebalance/sweep/processQueue. |
| PARAM_MANAGER_ROLE | TimelockController | Update weights, fees, thresholds. |
| TREASURY_ROLE | Treasury contract / multisig | Withdraw protocol fees. |
| ASSET_MANAGER_ROLE | TimelockController | Register/update assets. |
| EMERGENCY_ROLE | Security council | Emergency pause + emergency redeem. |

### Admin Structure

```text
Multisig Safe
    └── TimelockController
            └── Contract roles
```

Tidak ada single EOA yang bisa:

- upgrade contract;
- mengubah target weight;
- menarik treasury;
- pause/unpause tanpa kontrol.

Emergency pause bisa diberikan ke security council dengan role terpisah, tapi harus ada event dan time-bound review.

---

## 12. Upgradeability Design

### Recommended Pattern

UUPS Upgradeable untuk `JagadVault`.

Reason:

- Gas efficient dibanding Transparent Proxy.
- kompatibel dengan OpenZeppelin.
- bisa dikombinasikan dengan AccessControl dan Timelock.

Rules:

- Constructor tidak boleh initalize state.
- Gunakan `initializer` modifier.
- Storage layout harus reserved gap.
- Upgrade hanya lewat timelock.
- Setiap upgrade emit event.
- Upgrade harus di-test di testnet terlebih dahulu.

Storage gap example:

```solidity
uint256[50] private __gap;
```

### Immutable Components

- `JagadToken` sebaiknya immutable.
- `AssetRegistry` bisa upgradeable jika perlu menambah fitur adapter.
- `OracleReader` bisa upgradeable karena integrasi oracle bisa berubah.

---

## 13. Security Invariants

Invariant adalah kondisi yang harus selalu benar.

### INV-1: Solvency

```text
totalVaultValue >= totalLiabilities
```

Untuk MVP tanpa borrowing:

```text
totalVaultValue >= 0
```

dan semua share mewakili klaim atas aset yang ada.

Lebih ketat:

```text
sum(asset balances) dapat dicairkan ke USDC >= redeem obligations pada NAV saat ini
```

### INV-2: Weight Sum

```text
sum(enabled asset targetWeightBps) == 10_000
```

### INV-3: No Unauthorized Mint/Burn

```text
only JagadVault can mint/burn JagadToken
```

### INV-4: Pause Blocks Economic Actions

Saat paused:

- deposit revert;
- redeem revert;
- rebalance revert;
- sweep revert;
- treasury withdrawal revert kecuali emergency function.
- emergency redeem ALLOWED.

### INV-5: Oracle Freshness

Tidak ada operasi harga yang memakai feed dengan:

```text
timestamp < block.timestamp - maxStalenessSeconds
```

### INV-6: Slippage Protection

Setiap swap harus memiliki batas minimum output atau maksimum input.

```text
amountOut >= minAmountOut
```

atau:

```text
amountIn <= maxAmountIn
```

`minAmountOut` harus dihitung dari TWAP, bukan spot price.

### INV-7: Rebalance Cooldown

```text
block.timestamp >= lastRebalanceTimestamp + rebalanceCooldown
```

### INV-8: Sweep Threshold

```text
idleUsdc >= minSweepAmount
```

### INV-9: Anti-Inflation Attack

```text
navPerShareWad = (totalAssets + 1) * WAD / (totalSupply + 10**DECIMALS_OFFSET)
```

Virtual shares harus selalu digunakan. Tidak boleh ada perhitungan NAV tanpa virtual shares.

### INV-10: Rounding Favors Vault

Semua pembagian harus rounding ke arah yang menguntungkan vault, bukan user.

### INV-11: Minimum Deposit

```text
usdcAmount >= minDepositAmount
```

Default `minDepositAmount = 10 USDC`.

### INV-12: Operating Reserve

```text
usdcBalance >= operatingReserveWad
```

Operating reserve tidak boleh dipakai untuk rebalance atau sweep.

---

## 14. Threat Model

### 14.1 Oracle Manipulation

Threat:

- Hacker memanipulasi harga spot untuk membuat vault salah hitung NAV.

Mitigation:

- Gunakan Chainlink sebagai primary.
- Cross-check dengan Pyth.
- Reject stale price.
- Reject deviation terlalu besar.
- Gunakan TWAP untuk operasi besar jika tersedia.
- Rebalance tidak boleh dijalankan jika oracle invalid.

### 14.2 Sandwich Attack

Threat:

- MEV bot melihat rebalance/swap besar dan menggeser harga.

Mitigation:

- Gunakan DEX aggregator.
- Enforce max slippage dari TWAP.
- Pecah order besar jika memungkinkan.
- Jalankan rebalance saat likuiditas cukup.
- Consider private transaction / Flashbots Protect untuk keeper.

### 14.3 Low Liquidity Redeem

Threat:

- User redeem besar saat aset Tier 3 tidak likuid.

Mitigation:

- Min liquidity check per asset.
- Partial redemption + queue.
- Batasi max redeem per window.
- Tier 3 bobot kecil.
- Fallback ke synthetic/proxy yang lebih likuid.

### 14.4 Smart Contract Exploit

Threat:

- Bug di rebalancing, fee, mint/burn, atau upgrade logic.

Mitigation:

- OpenZeppelin standards.
- ReentrancyGuard.
- Checks-Effects-Interactions.
- Foundry fuzz/invariant tests.
- Internal audit.
- External audit sebelum TVL besar.
- Multisig + timelock.
- Pause mechanism.

### 14.5 Admin Key Compromise

Threat:

- Private key admin bocor.

Mitigation:

- Admin harus multisig.
- Privileged actions lewat timelock.
- Role separation.
- Emergency pause oleh council berbeda.

### 14.6 RWA Legal/Transfer Restriction

Threat:

- Tokenized stock/REIT tidak bisa ditransfer bebas ke vault atau user.

Mitigation:

- Asset adapter whitelist.
- Legal review sebelum enable asset.
- MVP prioritaskan aset crypto-native/synthetic.
- Pisahkan institutional KYC vault jika diperlukan.

### 14.7 Inflation/Donation Attack

Threat:

- Hacker deposit 1 wei, lalu donate aset langsung ke vault untuk memanipulasi NAV per share.

Mitigation:

- Virtual shares dengan decimals offset.
- Minimum initial deposit.
- Rounding favors vault.
- Unit test spesifik untuk attack vector ini.

### 14.8 Front-Running Deposit/Redeem

Threat:

- Attacker melihat deposit besar di mempool dan front-run untuk mendapatkan NAV yang lebih menguntungkan.

Mitigation:

- Virtual shares mengurangi dampak manipulasi NAV.
- Deposit fee mengurangi profitabilitas front-running.
- Consider commit-reveal scheme untuk deposit besar jika diperlukan.

---

## 15. Testing Strategy

### 15.1 Unit Tests

Target:

- Setiap fungsi kontrak diuji terisolasi.

Cases:

- deposit success;
- deposit fail when paused;
- deposit fail insufficient allowance;
- deposit fail below minimum;
- redeem success;
- redeem fail insufficient balance;
- partial redemption when liquidity insufficient;
- emergency redeem success when paused;
- emergency redeem fail when not paused;
- mint only vault;
- burn only vault;
- fee calculation;
- NAV calculation with virtual shares;
- asset registry validation;
- oracle freshness rejection;
- oracle deviation rejection.

### 15.2 Integration Tests

Target:

- Kontrak saling berbicara dengan benar.

Cases:

- deposit -> allocation -> NAV update;
- rebalance trigger -> swap -> weight restored;
- yield sweep -> asset purchase -> NAV increase;
- redeem -> liquidation -> USDC transfer;
- partial redemption -> queue -> process queue;
- emergency redeem -> proportional asset transfer;
- pause -> all economic actions blocked except emergency redeem;
- upgrade -> storage preserved.

### 15.3 Fuzz Tests

Target:

- Cari edge case acak.

Parameters:

- random deposit amounts;
- random price movements;
- random oracle timestamps;
- random slippage;
- random asset weights;
- random keeper call timing.

Scenarios:

- BTC crash 50%;
- gold spike 30%;
- silver oracle deviation;
- multiple deposits/redeems in one block;
- rebalance during low liquidity;
- sweep with zero idle balance;
- inflation attack with 1 wei deposit;
- donation attack with direct asset transfer.

### 15.4 Invariant Tests

Target:

- Pastikan kondisi fundamental tidak pernah violation.

Invariants:

```text
sum(targetWeights) == 10_000
totalSupply == 0 => navPerShare == WAD
paused => no deposit/redeem/rebalance/sweep (except emergency redeem)
oracle stale => no price-dependent action
after successful rebalance => drift within tolerance
treasury withdrawal <= allowed cap
virtual shares always used in NAV calculation
operating reserve maintained
```

### 15.5 Static Analysis

Tools:

- Slither.
- Foundry `forge build --sizes`.
- Custom lint.

Checks:

- unchecked external calls;
- reentrancy patterns;
- integer overflow impossible due to Solidity 0.8, but unsafe casting checked;
- unused state variables;
- visibility issues.

### 15.6 CI Pipeline

GitHub Actions:

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: foundry-rs/foundry-toolchain@v1
      - run: forge submodule update --init --recursive
      - run: forge build
      - run: forge test
      - run: forge test --fuzz-runs 10000
      - run: forge fmt --check
```

---

## 16. Deployment Architecture

### 16.1 Local / Anvil

Used for:

- rapid iteration;
- mock assets;
- mock oracles;
- mock DEX.

### 16.2 Base Sepolia

Used for:

- end-to-end testnet deployment;
- frontend integration;
- keeper dry run;
- oracle configuration;
- user acceptance testing.

Deployment order:

1. Deploy mock/real ERC20 assets if available.
2. Deploy `JagadToken`.
3. Deploy `AssetRegistry`.
4. Deploy `OracleReader`.
5. Deploy `Treasury`.
6. Deploy `Rebalancer`.
7. Deploy `YieldSweeper`.
8. Deploy `RedemptionQueue`.
9. Deploy `JagadVault` implementation.
10. Deploy proxy and initialize vault.
11. Grant roles.
12. Register assets.
13. Configure fees and thresholds.
14. Fund gas reserve.
15. Activate keeper.
16. Run smoke tests.

### 16.3 Base Mainnet Soft Launch

Constraints:

- TVL cap awal: $250,000.
- Whitelist user opsional.
- Redemption cap: $50,000 per 10 menit.
- Keeper aktif tapi dengan parameter konservatif.
- Yield sweep bisa ditunda sampai stabil.
- Monitoring ketat.

Soft launch checklist:

- multisig configured;
- timelock configured;
- contracts verified;
- oracle feeds live;
- DEX liquidity available;
- frontend connected to mainnet;
- alerting configured;
- runbook ready;
- backtest published;
- legal opinion obtained.

---

## 17. Monitoring and Observability

### On-chain Events to Monitor

- `Deposited`
- `Redeemed`
- `PartialRedemption`
- `RedemptionQueued`
- `EmergencyRedeemed`
- `Rebalanced`
- `YieldSwept`
- `Paused`
- `Unpaused`
- `ParameterUpdated`
- `Upgraded`

### Dashboard Metrics

| Metric | Source |
|---|---|
| Total TVL | Vault balances * oracle prices |
| NAV per $JGAD | Vault view function |
| Current allocation | Asset balances |
| Drift per asset | Rebalancer math |
| Last rebalance time | Vault storage/event |
| Idle yield balance | Treasury/vault accounting |
| Fee revenue | Treasury events |
| Oracle freshness | OracleReader events/view |
| Redemption queue size | RedemptionQueue contract |
| Operating reserve | Vault view function |

### Alert Conditions

Alert jika:

- oracle stale > threshold;
- deviation antar oracle > threshold;
- rebalance gagal berulang;
- sweep gagal berulang;
- TVL drop tajam;
- redeem queue/backlog tinggi;
- admin role changed;
- contract upgraded;
- pause activated;
- operating reserve < 15%;
- redemption cap reached.

---

## 18. Frontend Architecture

### Pages

| Page | Purpose |
|---|---|
| Landing | Explain JAGAD, disclaimer, CTA. |
| Dashboard | NAV, allocation, history. |
| Deposit | Connect wallet, approve USDC, deposit. |
| Redeem | Enter $JGAD amount, preview USDC, redeem. |
| Vault Details | Asset breakdown, fees, rebalance history. |
| Risk Center | Disclaimer, oracle status, pause status. |
| Backtest | Historical performance, drawdown, comparison. |

### State Management

- Wallet state: RainbowKit/ConnectKit.
- Contract state: Wagmi hooks.
- UI state: React state / Zustand if needed.

### Critical UX Requirements

- Tampilkan estimasi fee sebelum transaksi.
- Tampilkan warning bahwa $JGAD bukan stablecoin USD.
- Tampilkan oracle status.
- Tampilkan apakah vault paused.
- Tampilkan projected allocation setelah deposit.
- Tampilkan estimated slippage jika tersedia.
- Tampilkan historical backtest dengan max drawdown.
- Tampilkan redemption queue status jika applicable.

### Geo-blocking

- Gunakan Cloudflare atau Vercel middleware untuk geo-block US di MVP.
- Tampilkan pesan yang jelas jika user dari jurisdiction yang di-block.
- Ini bukan solusi hukum sempurna, tapi menunjukkan good faith.

---

## 19. Indexer / Subgraph Design

Untuk MVP, direct RPC bisa cukup. Tapi struktur event harus siap di-index.

Entities:

```text
Vault
Asset
Deposit
Redeem
PartialRedemption
EmergencyRedemption
Rebalance
YieldSweep
ParameterUpdate
PauseEvent
RedemptionQueueEntry
```

Example `Rebalance` entity:

```text
id
timestamp
txHash
assetSold
amountSold
assetBought
amountBought
preDriftBps
postDriftBps
gasUsed
slippageBps
```

This enables dashboard history tanpa recomputing semua transaksi dari awal.

---

## 20. Fee Architecture

### Fee Types

| Fee | Default | Collection Point | Destination |
|---|---:|---|---|
| Deposit fee | 0.4% | Saat deposit | Treasury / gas reserve |
| Redeem fee | 0.4% | Saat redeem | Treasury / gas reserve |
| Management fee | 0.5%/tahun | Accrued dari yield | Treasury |
| Rebalancing reserve | dari yield/fee | Keeper gas payment | Gas reserve |

### Fee Safety

- Fee tidak boleh membuat vault insolvent.
- Fee withdrawal harus capped.
- Fee parameter change harus lewat timelock.
- Saat paused, fee withdrawal diblokir kecuali emergency.

---

## 21. Configuration Parameters

All parameters should be stored on-chain and updatable by governance/timelock.

| Parameter | Default | Description |
|---|---:|---|
| `depositFeeBps` | 40 | 0.4% |
| `redeemFeeBps` | 40 | 0.4% |
| `managementFeeBps` | 50 | 0.5% per tahun |
| `driftThresholdBps` | 500 | 5% |
| `rebalanceCooldown` | 1 days | Minimum time between rebalances |
| `maxSlippageBps` | 100 | 1% |
| `maxOracleDeviationBps` | 200 | 2% |
| `maxStalenessSeconds` | 3600 | 1 hour |
| `minSweepAmount` | 1000e6 | $1,000 USDC equivalent |
| `operatingReserveBps` | 2000 | 20% USDC reserve |
| `minDepositAmount` | 10e6 | 10 USDC |
| `redemptionCapPerWindow` | 50000e6 | $50,000 per window |
| `redemptionWindowSeconds` | 600 | 10 minutes |
| `tvlCap` | 250000e6 | $250,000 soft launch cap |
| `decimalsOffset` | 3 | Virtual shares offset |

---

## 22. MVP Scope Boundary in Architecture

### Included

- Base deployment.
- USDC entry/exit.
- ERC-20 basket assets.
- OracleReader dengan multi-source validation.
- Rebalancer dengan batch swap.
- YieldSweeper.
- Treasury.
- AssetRegistry dengan liquidity gate.
- RedemptionQueue.
- Virtual shares anti-inflation attack.
- Partial redemption.
- Emergency proportional redemption.
- Multisig + timelock.
- Foundry tests.
- Minimal dashboard.
- Geo-blocking di frontend.

### Excluded

- Multi-chain.
- Fiat on-ramp.
- CEX listing.
- Lending/borrowing.
- Leverage.
- Full DAO governance.
- Insurance module.
- Native mobile app.
- Advanced tax reporting.
- Permissionless tokenized stocks with unrestricted transfer.
- Physical commodity custody.
- Istilah "dividend" dalam produk dan marketing.
- Tokenized stock US-domiciled di MVP.

---

## 23. Implementation Phases

### Phase 1: Scaffold

- Init Foundry repo.
- Install OpenZeppelin.
- Create interfaces.
- Create mock contracts.
- Set CI.

Deliverable:

```text
forge build passes
forge test passes with empty/mock tests
```

### Phase 2: Token and Vault Core

- Implement `JagadToken`.
- Implement `JagadVault` deposit/redeem.
- Implement NAV view dengan virtual shares.
- Implement fee basic.
- Implement minimum deposit.

Deliverable:

- User can deposit USDC and receive $JGAD.
- User can redeem $JGAD and receive USDC.
- Virtual shares calculation correct.
- Unit tests pass.

### Phase 3: Asset Registry and Oracle

- Implement `AssetRegistry`.
- Implement `OracleReader`.
- Add mock Chainlink/Pyth.
- Normalize decimals.
- Implement liquidity gate.

Deliverable:

- Vault can value multi-asset basket.
- Stale price rejected.
- Oracle deviation detected.

### Phase 4: Allocation and Rebalancing

- Implement initial allocation.
- Implement `RebalancerMath`.
- Implement `Rebalancer` dengan batch swap.
- Integrate mock DEX router.

Deliverable:

- Deposit allocates to target basket.
- Rebalance triggers at >5% drift.
- Slippage protection works.
- Batch swap reduces gas cost.

### Phase 5: Yield Sweeper

- Implement idle balance detection.
- Implement sweep threshold.
- Implement reinvestment split.

Deliverable:

- Sweep executes only above threshold.
- NAV increases after sweep.

### Phase 6: Redemption Safety

- Implement `RedemptionQueue`.
- Implement partial redemption.
- Implement emergency proportional redemption.
- Implement redemption cap.

Deliverable:

- Partial redemption works when liquidity insufficient.
- Emergency redeem works when paused.
- Redemption cap enforced.

### Phase 7: Security Hardening

- Add Pausable.
- Add ReentrancyGuard.
- Add AccessControl.
- Add Timelock integration.
- Run fuzz/invariant tests.
- Fix findings.

Deliverable:

- No critical/high unresolved issues.
- All invariants pass.

### Phase 8: Testnet Deployment

- Deploy to Base Sepolia.
- Configure mock/test assets.
- Run smoke tests.
- Connect frontend.

Deliverable:

- End-to-end testnet demo.

### Phase 9: Mainnet Soft Launch

- Deploy to Base.
- Set TVL cap.
- Set redemption cap.
- Enable monitoring.
- Gradually open access.

Deliverable:

- Live MVP with limited risk exposure.

---

## 24. Kilo Code Execution Notes

When giving tasks to Kilo Code, use this order:

1. Baca `PRD.md`.
2. Baca `ARCHITECTURE.md`.
3. Buat `IMPLEMENTATION_PLAN.md`.
4. Implement interfaces first.
5. Implement mocks.
6. Implement contracts module by module.
7. Write tests alongside each module.
8. Run `forge test` after each module.
9. Do not add features outside MVP scope.
10. If ambiguity exists, stop and ask.

Suggested Kilo Code prompt:

```text
Read PRD.md and ARCHITECTURE.md.

Implement JAGAD Vault MVP exactly according to these documents.

Rules:
1. Use Foundry, Solidity ^0.8.26, OpenZeppelin.
2. Start with interfaces and mock contracts.
3. Implement modules in this order:
   - JagadToken
   - AssetRegistry
   - OracleReader
   - Treasury
   - JagadVault
   - Rebalancer
   - YieldSweeper
   - RedemptionQueue
4. Write unit tests for every function.
5. Write integration tests for deposit, redeem, rebalance, sweep, partial redemption, and emergency redemption.
6. Write fuzz and invariant tests for solvency, oracle freshness, pause, weight sum, virtual shares, and anti-inflation attack.
7. Do not implement multi-chain, lending, leverage, governance token, CEX listing, or fiat on-ramp.
8. If any requirement conflicts with PRD or ARCHITECTURE, stop and ask before coding.
9. Keep code modular and documented with NatSpec.
10. Ensure all external token transfers use SafeERC20.
11. Ensure all privileged functions use AccessControl and timelock-compatible roles.
12. Ensure all swaps have slippage protection using TWAP.
13. Ensure oracle reads validate freshness and deviation.
14. Ensure NAV calculation uses virtual shares.
15. Ensure minimum deposit is enforced.
16. Ensure partial redemption and emergency proportional redemption work correctly.

First, produce IMPLEMENTATION_PLAN.md with file-by-file breakdown and test matrix. Wait for approval before writing contracts.
```

---

## 25. Open Technical Questions

| ID | Question | Impact | Recommendation |
|---|---|---|---|
| AQ-1 | Apakah Tier 3 MVP memakai synthetic proxy atau RWA token asli? | Menentukan adapter dan regulasi. | Mulai dari synthetic/liquid proxy jika tersedia. |
| AQ-2 | Apakah vault menggunakan ERC-4626 penuh atau custom share accounting? | Kompleksitas integrasi DeFi. | Custom ERC-4626-inspired lebih fleksibel untuk multi-aset. |
| AQ-3 | Apakah `JagadVault` upgradeable sejak awal? | Risiko upgrade vs kebutuhan bug fix. | Ya, UUPS + timelock. |
| AQ-4 | Bagaimana menghitung idle yield secara on-chain? | Accuracy yield sweep. | Gunakan operating reserve heuristic untuk MVP. |
| AQ-5 | Apakah redeem perlu queue jika likuiditas rendah? | UX dan solvency. | MVP: partial redemption + queue. |
| AQ-6 | Apakah keeper boleh trigger rebalance otomatis penuh? | Gas dan risiko. | Ya, tapi dengan cooldown, cap, dan pause. |
| AQ-7 | Apakah dashboard perlu subgraph sejak MVP? | Dev effort. | Tidak wajib, direct RPC cukup. |
| AQ-8 | Siapa anggota multisig awal? | Security. | Minimal 3-of-5 atau 2-of-3 trusted signers. |
| AQ-9 | Bagaimana implementasi TWAP yang optimal? | Slippage protection. | Gunakan Chainlink TWAP jika tersedia, fallback ke custom. |
| AQ-10 | Apakah geo-blocking di frontend cukup untuk compliance? | Legal risk. | Tidak cukup sempurna, tapi good faith. Perlu legal opinion. |

---

## 26. Definition of Architectural Done

Arsitektur JAGAD MVP dianggap selesai jika:

1. Semua kontrak inti memiliki interface jelas.
2. Deposit/redeem flow dapat dijelaskan end-to-end.
3. Rebalancing algorithm deterministic dan bisa dites.
4. Yield sweep memiliki threshold dan reinvestment split.
5. Oracle reader punya freshness dan deviation check.
6. Access control memakai multisig + timelock.
7. Testing strategy mencakup unit, integration, fuzz, invariant.
8. Repo structure siap dipakai Kilo Code.
9. MVP scope dan out-of-scope jelas.
10. Open questions terdokumentasi sebelum coding dimulai.
11. Virtual shares anti-inflation attack terimplementasi.
12. Partial redemption dan emergency proportional redemption terdesain.
13. Liquidity gate per aset terdefinisi.
14. Batch swap untuk efisiensi gas terdesain.
15. TWAP untuk slippage protection terdesain.

---

## Changelog

| Tanggal | Versi | Perubahan |
|---|---|---|
| 2026-10-15 | 0.1.0 | Draft awal ARCHITECTURE.md |
| 2026-10-16 | 0.2.0 | Update bobot basket: Tier 1 naik ke 55%, Tier 3 turun ke 20% |
| 2026-10-16 | 0.2.0 | Tambah virtual shares anti-inflation attack di NAV calculation |
| 2026-10-16 | 0.2.0 | Tambah minimum deposit 10 USDC |
| 2026-10-16 | 0.2.0 | Tambah RedemptionQueue module untuk partial redemption |
| 2026-10-16 | 0.2.0 | Tambah emergency proportional redemption |
| 2026-10-16 | 0.2.0 | Tambah redemption cap per window |
| 2026-10-16 | 0.2.0 | Tambah operating reserve 20% USDC |
| 2026-10-16 | 0.2.0 | Tambah liquidity gate per asset di AssetRegistry |
| 2026-10-16 | 0.2.0 | Ganti DividendSweeper jadi YieldSweeper (hindari istilah dividend) |
| 2026-10-16 | 0.2.0 | Tambah batch swap logic di Rebalancer |
| 2026-10-16 | 0.2.0 | Tambah TWAP untuk slippage protection |
| 2026-10-16 | 0.2.0 | Tambah multi-source oracle validation |
| 2026-10-16 | 0.2.0 | Tambah geo-blocking di frontend architecture |
| 2026-10-16 | 0.2.0 | Tambah backtest requirement di deployment checklist |
| 2026-10-16 | 0.2.0 | Tambah TVL cap $250k dan redemption cap $50k/10min di soft launch |