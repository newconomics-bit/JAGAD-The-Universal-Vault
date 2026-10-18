# Product Requirements Document: JAGAD Vault

| Field | Value |
|---|---|
| Product Name | JAGAD |
| Token Ticker | $JGAD |
| Version | 0.2.0 |
| Status | Draft |
| Date | Oktober 2026 |
| Owner | Mufti zaka |
| Document Type | Product Requirements Document |

---

## Section 1: Problem Statement

### Masalah Utama

Banyak pengguna ingin menyimpan kekayaan secara digital, tetapi menghadapi dilema:

1. **Uang fiat tergerus inflasi.**
   - Dolar, rupiah, euro, dan mata uang fiat lainnya kehilangan daya beli seiring waktu.
   - Menyimpan uang di bank konvensional sering kali tidak cukup untuk menjaga nilai kekayaan jangka panjang.

2. **Kripto terlalu volatil.**
   - Bitcoin dan aset kripto lain memiliki potensi pertumbuhan tinggi, tetapi juga mengalami drawdown ekstrem.
   - Banyak pengguna tidak nyaman menyimpan seluruh kekayaan mereka hanya dalam BTC atau ETH.

3. **Aset keras sulit diakses dan kurang likuid.**
   - Emas, perak, properti, dan komoditas dunia nyata terbukti menjaga nilai dalam jangka panjang.
   - Tetapi aset-aset ini sulit diperdagangkan 24/7, membutuhkan kustodian fisik, dan tidak mudah diintegrasikan ke sistem keuangan digital.

4. **Eksposur global terfragmentasi.**
   - Untuk memiliki portofolio global, pengguna harus membuka banyak akun: exchange kripto, broker saham, platform properti, dan pasar komoditas.
   - Prosesnya lambat, mahal, dan penuh friksi.

5. **Rebalancing manual rentan emosi dan biaya.**
   - Investor sering gagal menjual aset yang sudah naik terlalu tinggi dan membeli aset yang sedang turun.
   - Rebalancing manual memakan waktu, biaya transaksi, dan keputusan emosional.

### Solusi yang Ada Saat Ini dan Celahnya

| Solusi Existing | Kelemahan |
|---|---|
| Stablecoin seperti USDC/USDT | Stabil terhadap USD, tetapi tetap tergerus inflasi USD. |
| Bitcoin saja | Potensi naik besar, tetapi volatilitas terlalu tinggi untuk penyimpan nilai konservatif. |
| Emas fisik / PAXG saja | Stabil, tetapi tidak memiliki upside pertumbuhan teknologi digital. |
| Reksadana / ETF tradisional | Terbatas jam bursa, KYC, custodian, dan tidak composability di DeFi. |
| Index token kripto biasa | Masih terlalu berkorelasi dengan pasar kripto. |

### Celah Produk

Belum ada produk on-chain yang menggabungkan:

- stablecoin berbunga,
- emas,
- perak,
- Bitcoin,
- dan proxy aset dunia nyata seperti energi, tambang, properti, serta agrikultur,

ke dalam satu token vault yang:

- bisa dibeli dengan USDC,
- otomatis terdiversifikasi,
- otomatis rebalance,
- otomatis mengompounding yield/revenue,
- dan tetap bisa dicairkan kembali ke USDC.

### Data Pendukung Awal

> Data berikut adalah asumsi awal yang perlu divalidasi dengan riset user, data on-chain, dan benchmark pasar sebelum launch.

- Bitcoin pernah mengalami drawdown lebih dari 50% dalam beberapa siklus pasar.
- Emas secara historis digunakan sebagai lindung nilai terhadap inflasi dan krisis moneter.
- Investor ritel dan institusi semakin tertarik pada aset dunia nyata yang ditokenisasi (RWA).
- Banyak pengguna DeFi mencari produk yang lebih stabil daripada kripto murni, tetapi tetap memberikan eksposur pertumbuhan.
- Rebalancing manual sering gagal dilakukan karena faktor emosi, biaya transaksi, dan kurangnya disiplin.

### Pernyataan Masalah

**Pengguna membutuhkan satu token on-chain yang dapat menjadi penyimpan nilai global, lebih stabil daripada kripto tunggal, tetapi tetap memiliki potensi pertumbuhan melalui Bitcoin dan aset produktif dunia nyata.**

JAGAD hadir sebagai vault indeks anti-inflasi yang mengelola keranjang aset global secara otomatis.

---

## Section 2: Goals

Produk JAGAD dianggap sukses jika mencapai tujuan terukur berikut.

| ID | Goal | Metrik Kesuksesan |
|---|---|---|
| G1 | Menyederhanakan eksposur aset global dalam satu token | Pengguna dapat deposit USDC dan menerima $JGAD dalam satu alur transaksi. |
| G2 | Mengurangi volatilitas dibandingkan holding BTC saja | Target awal: volatilitas 90 hari $JGAD tidak lebih dari 70% volatilitas BTC pada periode yang sama. |
| G3 | Menjaga alokasi portofolio tetap sesuai target | Rebalancing otomatis terjadi ketika bobot aset melenceng lebih dari 5% dari target. |
| G4 | Mengompounding yield/revenue secara otomatis | Minimal 95% idle yield yang melebihi threshold sweep berhasil di-reinvest. |
| G5 | Memberikan transparansi nilai aset kepada user | Dashboard menampilkan NAV, alokasi aset, riwayat rebalance, riwayat sweep, dan fee secara real-time atau near-real-time. |
| G6 | Menjaga keamanan vault | Tidak ada critical/high severity issue yang unresolved sebelum mainnet launch. |
| G7 | Menjaga biaya operasional tetap efisien | Rebalancing dan sweep tidak boleh dijalankan jika estimated cost lebih besar daripada expected benefit. |
| G8 | Membangun kepercayaan user | User dapat memahami bahwa $JGAD bukan stablecoin USD, melainkan index token dengan risiko fluktuasi. |
| G9 | Membatasi drawdown relatif terhadap BTC | Max drawdown vault tidak melebihi 70% drawdown BTC pada periode yang sama dalam backtest 2020-2026. |
| G10 | Memastikan keberlanjutan operasional | Proyek memiliki runway operasional minimal 12 bulan sebelum public launch. |
| G11 | Mempublikasikan backtest historis | Backtest 2020-2026 selesai dan dipublikasikan sebelum public launch, mencakup max drawdown, CAGR, Sharpe ratio, dan perbandingan dengan BTC/ETH/S&P 500. |

### Goal Utama MVP

MVP JAGAD sukses jika:

1. User bisa deposit USDC.
2. Vault otomatis mengalokasikan dana ke target basket.
3. User menerima token $JGAD.
4. Vault bisa melakukan rebalance ketika drift > 5%.
5. Vault bisa redeem $JGAD kembali ke USDC, dengan partial redemption jika likuiditas tidak cukup.
6. Dashboard minimal menampilkan NAV dan komposisi aset.
7. Semua fungsi inti lolos test lokal dan testnet.
8. Backtest historis dipublikasikan.

---

## Section 3: Target Users / Personas

### Persona 1: Crypto-Native Investor

| Attribute | Description |
|---|---|
| Usia | 25–45 tahun |
| Profil | Sudah paham DeFi, wallet, gas fee, DEX, dan stablecoin. |
| Kebutuhan | Ingin diversifikasi otomatis tanpa harus manage banyak posisi manual. |
| Pain Point | Capek rebalance manual, takut overexposure ke satu koin, ingin eksposur BTC tapi tidak mau volatilitas penuh. |
| Expected Behavior | Deposit USDC, hold $JGAD jangka menengah-panjang, pantau NAV dan rebalance history. |

### Persona 2: Inflation-Hedge Saver

| Attribute | Description |
|---|---|
| Usia | 30–55 tahun |
| Profil | Memiliki dana dingin, khawatir inflasi menggerus tabungan fiat. |
| Kebutuhan | Tempat menyimpan nilai yang lebih kuat dari uang tunai, tetapi tidak serumit trading kripto. |
| Pain Point | Takut crypto crash, tetapi merasa fiat tidak aman jangka panjang. |
| Expected Behavior | Alokasikan sebagian portofolio ke $JGAD sebagai digital hard asset basket. |

### Persona 3: DAO / Digital Treasury

| Attribute | Description |
|---|---|
| Profil | Organisasi on-chain yang menyimpan treasury dalam stablecoin atau aset kripto. |
| Kebutuhan | Instrumen treasury yang terdiversifikasi, programmable, dan transparan. |
| Pain Point | Treasury terlalu terkonsentrasi di USDC/ETH/BTC, ingin eksposur lebih luas tanpa operational burden. |
| Expected Behavior | Menggunakan multisig untuk deposit besar, memantau risiko melalui dashboard dan on-chain events. |

### Persona 4: Conservative DeFi User

| Attribute | Description |
|---|---|
| Profil | User DeFi yang sudah pengalaman tetapi lebih risk-averse. |
| Kebutuhan | Yield dan diversifikasi dengan risiko lebih rendah daripada leverage farming. |
| Pain Point | Takut smart contract exploit, takut impermanent loss, takut aset underlying tidak jelas. |
| Expected Behavior | Memilih vault dengan transparansi NAV, audit, pause mechanism, dan oracle protection. |

---

## Section 4: User Stories

Prioritas:

- **P1** = wajib untuk MVP launch.
- **P2** = penting, tetapi bisa menyusul setelah MVP stabil.
- **P3** = nice-to-have.

| ID | Priority | User Story |
|---|---:|---|
| US-1 | P1 | Sebagai investor kripto, saya ingin deposit USDC dan langsung menerima $JGAD supaya saya tidak perlu membeli banyak aset secara manual. |
| US-2 | P1 | Sebagai holder, saya ingin vault otomatis mengalokasikan deposit saya ke keranjang target supaya portofolio saya langsung terdiversifikasi. |
| US-3 | P1 | Sebagai pengguna, saya ingin $JGAD saya merepresentasikan kepemilikan atas seluruh isi vault supaya nilai token saya mengikuti NAV vault. |
| US-4 | P1 | Sebagai pengguna, saya ingin redeem $JGAD kembali menjadi USDC supaya saya bisa keluar dari posisi kapan saja. |
| US-5 | P1 | Sebagai pengguna, saya ingin vault melakukan rebalance otomatis ketika bobot aset melenceng lebih dari 5% supaya strategi buy low sell high dijalankan secara disiplin. |
| US-6 | P1 | Sebagai pengguna, saya ingin melihat NAV, alokasi aset, dan riwayat rebalance supaya saya percaya bahwa vault dikelola dengan transparan. |
| US-7 | P1 | Sebagai operator, saya ingin bisa pause vault jika oracle error atau ada anomali supaya dana user tidak dirugikan. |
| US-8 | P1 | Sebagai admin multisig, saya ingin mengatur parameter target weight, drift threshold, fee, dan address aset supaya vault bisa disesuaikan tanpa redeploy penuh jika memungkinkan. |
| US-9 | P1 | Sebagai pengguna, saya ingin partial redemption jika likuiditas tidak cukup supaya saya tetap bisa keluar sebagian tanpa harus menunggu atau gagal total. |
| US-10 | P1 | Sebagai pengguna, saya ingin emergency proportional redemption saat vault paused supaya saya tidak terjebak jika terjadi insiden. |
| US-11 | P1 | Sebagai pengguna baru, saya ingin penjelasan jelas bahwa $JGAD bukan stablecoin USD supaya saya tidak salah ekspektasi. |
| US-12 | P2 | Sebagai pengguna, saya ingin yield/revenue otomatis di-compound supaya kekayaan saya tumbuh tanpa harus klaim manual. |
| US-13 | P2 | Sebagai pengguna, saya ingin melihat estimasi biaya gas dan slippage sebelum deposit/redeem supaya saya tidak terkejut dengan biaya transaksi. |
| US-14 | P2 | Sebagai pengguna, saya ingin melihat historical drawdown dan backtest supaya saya bisa menilai risiko sebelum deposit. |
| US-15 | P2 | Sebagai DAO treasury, saya ingin akses dashboard khusus dan laporan on-chain supaya saya bisa mempertanggungjawabkan penggunaan treasury. |
| US-16 | P3 | Sebagai pengguna, saya ingin fiat on-ramp supaya bisa beli $JGAD langsung pakai kartu debit/kredit. |
| US-17 | P3 | Sebagai pengguna, saya ingin mobile app supaya bisa memantau portofolio dari ponsel. |
| US-18 | P3 | Sebagai community member, saya ingin governance ringan untuk mengusulkan perubahan parameter vault. |

---

## Section 5: Functional Requirements

### 5.1 Core Vault Functions

| ID | Priority | Functional Requirement | Acceptance Criteria |
|---|---:|---|---|
| FR-1 | P1 | Sistem harus memungkinkan user deposit USDC ke JAGAD Vault. | User dapat approve USDC dan memanggil deposit. Deposit gagal jika user tidak punya saldo cukup atau vault paused. |
| FR-2 | P1 | Sistem harus mencetak token $JGAD kepada user setelah deposit berhasil. | Jumlah $JGAD yang di-mint dihitung berdasarkan NAV vault saat deposit. |
| FR-3 | P1 | Sistem harus mengalokasikan deposit USDC ke target basket secara otomatis. | Setelah deposit, alokasi aktual mendekati target weight dalam toleransi yang ditentukan, misalnya ±1% setelah swap. |
| FR-4 | P1 | Sistem harus memungkinkan user redeem $JGAD kembali menjadi USDC. | $JGAD dibakar, aset vault dijual proporsional, dan USDC dikirim ke user. Jika likuiditas tidak cukup, sistem melakukan partial redemption dan memasukkan sisanya ke redemption queue. |
| FR-5 | P1 | Sistem harus menghitung NAV vault berdasarkan harga oracle aset underlying. | NAV dapat dibaca on-chain atau melalui view function. Harga stale harus ditolak. |
| FR-6 | P1 | Sistem harus menyimpan seluruh aset underlying di dalam vault contract, bukan di wallet pribadi admin. | Semua aset tercatat sebagai milik vault dan dapat diaudit on-chain. |
| FR-7 | P1 | Sistem harus menggunakan virtual shares dan decimals offset dalam perhitungan NAV untuk mencegah inflation/donation attack. | Formula: navPerShare = (totalAssets + 1) / (totalSupply + 10**decimalsOffset). Wajib ada unit test yang membuktikan deposit pertama dengan 1 wei tidak dapat dimanipulasi. |
| FR-8 | P1 | Sistem harus menetapkan minimum deposit untuk mencegah dust attack. | Deposit di bawah 10 USDC harus revert. |

### 5.2 Target Asset Basket

| ID | Priority | Functional Requirement | Acceptance Criteria |
|---|---:|---|---|
| FR-9 | P1 | Vault harus mendukung struktur basket bertier. | Tier 1, Tier 2, dan Tier 3 memiliki target weight yang dapat dikonfigurasi. |
| FR-10 | P1 | Target awal Tier 1 adalah 55%. | Terdiri dari 30% USDC/sDAI, 15% PAXG, dan 10% synthetic silver. |
| FR-11 | P1 | Target awal Tier 2 adalah 25%. | Terdiri dari 25% WBTC/Bitcoin exposure. |
| FR-12 | P1 | Target awal Tier 3 adalah 20%. | Terdiri dari proxy energi 7%, proxy tambang/logam 7%, proxy properti/REITs 3%, dan proxy agrikultur 3%. |
| FR-13 | P1 | Jika aset Tier 3 berupa tokenized stock/REIT yang terbatas KYC, sistem harus memiliki mekanisme whitelist atau fallback synthetic proxy. | Vault tidak boleh terjebak pada aset yang tidak bisa diperdagangkan/diredeem secara normal. |
| FR-14 | P1 | Setiap aset harus memiliki liquidity gate. | AssetRegistry menyimpan minLiquidityUsd dan maxSlippageBps per aset. Jika likuiditas aktual di bawah threshold, bobot aset otomatis di-cut dan dialihkan ke USDC. |
| FR-15 | P2 | Admin multisig dapat mengubah daftar aset dan target weight melalui parameter governance. | Perubahan harus tercatat on-chain dan memiliki timelock jika diperlukan. |

### 5.3 Rebalancing

| ID | Priority | Functional Requirement | Acceptance Criteria |
|---|---:|---|---|
| FR-16 | P1 | Sistem harus mengecek drift bobot aset terhadap target weight. | Drift dihitung dalam basis points atau percentage points. |
| FR-17 | P1 | Rebalancing harus dipicu ketika satu atau lebih aset melenceng lebih dari 5% dari target. | Jika deviation <= 5%, rebalance tidak dijalankan. |
| FR-18 | P1 | Rebalancing harus menjual aset overweight dan membeli aset underweight. | Setelah rebalance sukses, bobot kembali mendekati target. |
| FR-19 | P1 | Rebalancing harus memiliki slippage protection. | Swap gagal jika output kurang dari minAmountOut yang ditentukan. |
| FR-20 | P1 | Rebalancing tidak boleh dijalankan jika oracle stale, vault paused, atau liquidity tidak cukup. | Sistem harus revert dengan error yang jelas. |
| FR-21 | P2 | Sistem harus memperhitungkan estimated gas fee sebelum rebalance. | Jika estimated cost lebih besar dari benefit, rebalance dapat diskip atau dijadwalkan ulang. |
| FR-22 | P2 | Sistem harus memiliki cooldown minimal antar rebalance. | Mencegah rebalance berlebihan yang menguras gas. Default cooldown: 24 jam. |
| FR-23 | P2 | Rebalancing harus menggunakan batch swap: jual semua aset overweight menjadi USDC terlebih dahulu, lalu beli aset underweight. | Mengurangi jumlah swap dan gas cost. |

### 5.4 Yield / Revenue Compounding

| ID | Priority | Functional Requirement | Acceptance Criteria |
|---|---:|---|---|
| FR-24 | P1 | Sistem harus dapat mendeteksi idle yield/revenue yang masuk ke vault. | Idle balance dapat dibaca dan dibedakan dari principal assets. |
| FR-25 | P1 | Sistem harus dapat melakukan sweep terhadap idle yield/revenue. | Sweep hanya dijalankan jika balance melebihi minimum threshold. |
| FR-26 | P1 | Hasil sweep harus di-reinvest ke aset target yang dikonfigurasi. | Default reinvestment split dapat diatur oleh multisig. |
| FR-27 | P2 | Sistem harus mencatat riwayat yield sweep. | Event emits amount, timestamp, target assets, dan tx hash. |
| FR-28 | P2 | Sweep tidak boleh mengganggu solvabilitas vault. | Setelah sweep, vault tetap memenuhi invariant aset >= liabilitas. |
| FR-29 | P2 | Minimum sweep threshold default adalah $1,000 equivalent USDC. | Sweep tidak dijalankan jika idle balance di bawah threshold. |

### 5.5 Redemption Safety

| ID | Priority | Functional Requirement | Acceptance Criteria |
|---|---:|---|---|
| FR-30 | P1 | Sistem harus mendukung partial redemption jika likuiditas tidak cukup. | User menerima USDC sebagian, dan sisanya masuk redemption queue dengan estimasi waktu penyelesaian. |
| FR-31 | P1 | Sistem harus menyediakan emergency proportional redemption saat vault paused. | User dapat klaim aset underlying langsung sesuai porsi share tanpa harus lewat swap. Hanya aktif saat vault paused atau emergency mode. |
| FR-32 | P1 | Sistem harus mendukung redemption cap per window di soft launch. | Default cap: $50,000 per 10 menit. Cap dapat dikonfigurasi oleh multisig. |
| FR-33 | P1 | Sistem harus menjaga operating reserve USDC minimal 20% dari total vault value. | Reserve ini digunakan untuk redemption normal tanpa harus menjual aset lain. |

### 5.6 Fees and Treasury

| ID | Priority | Functional Requirement | Acceptance Criteria |
|---|---:|---|---|
| FR-34 | P1 | Sistem harus mendukung deposit fee. | Fee default 0.4%. |
| FR-35 | P1 | Sistem harus mendukung redeem fee. | Fee default 0.4%. |
| FR-36 | P1 | Sistem harus mendukung management fee atau yield reserve untuk operasional. | Fee tidak boleh diambil saat vault paused atau dalam kondisi darurat tanpa kontrol multisig. Default management fee: 0.5% per tahun, di-accrue dari yield. |
| FR-37 | P1 | Sebagian fee/yield harus dialokasikan ke gas reserve. | Gas reserve digunakan untuk membayar rebalance dan sweep. |
| FR-38 | P2 | Treasury harus dapat menarik fee secara terbatas dan transparan. | Withdrawal fee harus melalui multisig dan tercatat on-chain. |

### 5.7 Security and Admin Controls

| ID | Priority | Functional Requirement | Acceptance Criteria |
|---|---:|---|---|
| FR-39 | P1 | Sistem harus memiliki akses kontrol berbasis role. | Hanya address tertentu yang dapat pause, update parameter, atau withdraw treasury. |
| FR-40 | P1 | Owner admin harus berupa multisig, bukan wallet pribadi. | Semua fungsi privileged hanya dapat dijalankan oleh multisig. |
| FR-41 | P1 | Sistem harus memiliki fungsi pause dan unpause. | Saat paused, deposit/redeem/rebalance/sweep tidak dapat dijalankan kecuali fungsi darurat yang diizinkan. |
| FR-42 | P1 | Sistem harus melindungi diri dari reentrancy attack. | Fungsi eksternal call harus menggunakan reentrancy guard atau checks-effects-interactions pattern. |
| FR-43 | P1 | Sistem harus memvalidasi oracle price. | Harga ditolak jika timestamp terlalu lama, deviation terlalu besar, atau aggregator tidak valid. |
| FR-44 | P2 | Sistem harus memiliki emergency withdrawal mechanism untuk aset yang salah kirim. | Hanya multisig yang dapat menarik token tidak terdaftar, dengan catatan dan event. |
| FR-45 | P2 | Sistem harus mendukung timelock untuk semua perubahan parameter kritis. | Default timelock: 24-48 jam. |

### 5.8 Transparency and Dashboard

| ID | Priority | Functional Requirement | Acceptance Criteria |
|---|---:|---|---|
| FR-46 | P1 | Sistem harus memancarkan event untuk deposit, redeem, mint, burn, rebalance, sweep, pause, dan parameter update. | Event dapat di-index oleh frontend/dashboard. |
| FR-47 | P1 | Dashboard harus menampilkan total NAV vault. | NAV dihitung dari seluruh aset underlying dikurangi liabilitas/fee terutang. |
| FR-48 | P1 | Dashboard harus menampilkan alokasi aktual vs target. | User dapat melihat deviation tiap aset. |
| FR-49 | P1 | Dashboard harus menampilkan riwayat rebalance dan yield sweep. | Riwayat minimal mencakup timestamp, aset, amount, dan status. |
| FR-50 | P1 | Dashboard harus menampilkan disclaimer risiko yang jelas. | Pengguna diberi tahu bahwa $JGAD bukan stablecoin USD dan nilainya dapat naik/turun. |
| FR-51 | P1 | Dashboard harus menampilkan historical backtest sebelum public launch. | Backtest mencakup max drawdown, CAGR, Sharpe ratio, dan perbandingan dengan BTC/ETH/S&P 500. |
| FR-52 | P2 | Dashboard harus menampilkan fee yang dikenakan. | User dapat melihat deposit fee, redeem fee, dan management fee. |
| FR-53 | P2 | Dashboard harus menampilkan vault liquidity status. | User dapat melihat apakah vault dalam mode normal, capped, atau queue. |

### 5.9 Compliance and Education

| ID | Priority | Functional Requirement | Acceptance Criteria |
|---|---:|---|---|
| FR-54 | P1 | Frontend harus melakukan jurisdiction gating. | US users di-block di MVP. Geo-block bukan solusi hukum sempurna, tetapi menunjukkan good faith. |
| FR-55 | P1 | Produk tidak boleh menggunakan istilah "dividend" dalam smart contract, UI, atau marketing. | Gunakan istilah "yield", "revenue", atau "NAV appreciation". |
| FR-56 | P1 | Produk tidak boleh menggunakan tokenized stock US-domiciled di MVP. | Tier 3 harus memakai synthetic proxy atau aset on-chain yang tidak diklasifikasikan sebagai security. |
| FR-57 | P2 | Sistem harus mendukung geo-blocking yang dapat dikonfigurasi. | Daftar jurisdiction yang di-block dapat diubah oleh multisig. |

---

## Section 6: Non-Functional Requirements

| ID | Priority | Category | Requirement | Acceptance Criteria |
|---|---:|---|---|---|
| NFR-1 | P1 | Security | Smart contract harus lolos unit test, integration test, fuzz test, dan invariant test. | Tidak ada failing test kritis sebelum deploy. |
| NFR-2 | P1 | Security | Kontrak harus menggunakan pola keamanan standar: access control, pausable, reentrancy guard, dan safe transfer. | Kode diaudit internal dan tidak memiliki known critical vulnerability. |
| NFR-3 | P1 | Oracle Resilience | Sistem tidak boleh bergantung pada satu sumber harga spot tanpa validasi. | Harus ada freshness check, outlier check, dan fallback mechanism. |
| NFR-4 | P1 | Economic Safety | Vault tidak boleh membiarkan redeem yang membuat solvabilitas negatif. | Invariant total assets >= total liabilities harus selalu terjaga. |
| NFR-5 | P1 | Cost Efficiency | Operasi rebalance dan sweep harus hemat gas. | Sistem tidak menjalankan aksi jika estimated cost melebihi benefit atau threshold minimum. |
| NFR-6 | P1 | Performance | Deposit dan redeem harus dapat diselesaikan dalam satu transaksi atau alur yang jelas. | Tidak ada langkah tersembunyi yang membuat user gagal transaksi tanpa pesan error jelas. |
| NFR-7 | P1 | Availability | Smart contract harus dapat diakses 24/7 selama blockchain aktif. | Frontend dashboard target uptime 99.5% di luar maintenance. |
| NFR-8 | P1 | Auditability | Semua perubahan parameter dan aksi vault harus tercatat on-chain. | Event dan transaction history dapat direkonstruksi. |
| NFR-9 | P1 | User Clarity | Produk harus secara jelas dikomunikasikan sebagai index vault, bukan stablecoin 1:1 USD. | Disclaimer muncul di dApp, docs, dan marketing material. |
| NFR-10 | P1 | Anti-Inflation Attack | NAV accounting wajib menggunakan virtual shares dan decimals offset. | Formula: navPerShare = (totalAssets + 1) / (totalSupply + 10**decimalsOffset). Wajib ada unit test yang membuktikan deposit pertama dengan 1 wei tidak dapat dimanipulasi. |
| NFR-11 | P1 | Oracle Multi-Source | Sistem harus menggunakan minimal dua sumber oracle untuk aset kritis. | Chainlink sebagai primary, Pyth sebagai cross-check. Deviation antar oracle > 2% harus trigger alert atau pause. |
| NFR-12 | P1 | Slippage Protection | Setiap swap harus memiliki minAmountOut atau maxAmountIn. | Tidak ada swap yang dieksekusi tanpa slippage protection. |
| NFR-13 | P1 | Emergency Pause | Sistem harus dapat di-pause dalam satu transaksi oleh emergency role. | Pause harus menghentikan semua aksi ekonomi kecuali emergency redemption. |
| NFR-14 | P1 | Audit Requirement | External audit harus dilakukan sebelum TVL melebihi $1M. | Laporan audit dipublikasikan. |
| NFR-15 | P1 | Runway | Proyek harus memiliki runway operasional minimal 12 bulan sebelum public launch. | Budget mencakup gas, audit, legal, marketing, dan liquidity seeding. |
| NFR-16 | P1 | Backtest Transparency | Backtest historis 2020-2026 harus dipublikasikan sebelum public launch. | Backtest mencakup max drawdown, CAGR, Sharpe ratio, dan perbandingan dengan BTC/ETH/S&P 500. |
| NFR-17 | P2 | Upgradeability | Jika menggunakan upgradeable contract, harus ada timelock, storage safety, dan upgrade event. | Upgrade tidak dapat dilakukan oleh single EOA. |
| NFR-18 | P2 | Scalability | Arsitektur harus mampu menangani peningkatan TVL tanpa mengubah logika inti secara drastis. | Rebalancing tetap aman saat vault bertambah besar, dengan slippage control. |
| NFR-19 | P2 | Compliance Awareness | Produk tidak boleh mengklaim sebagai bank, e-money, atau sekuritas tanpa dasar hukum. | Legal disclaimer dan jurisdiction restriction diperlukan sebelum public launch. |
| NFR-20 | P2 | Liquidity Safety | Aset dalam vault harus memiliki likuiditas cukup untuk redeem normal. | Aset dengan likuiditas rendah hanya boleh diberi bobot kecil atau memakai whitelist/fallback. |
| NFR-21 | P3 | Accessibility | Dashboard harus dapat digunakan oleh user dengan keterbatasan visual dasar. | Kontras warna cukup dan informasi penting tidak hanya mengandalkan warna. |
| NFR-22 | P3 | Internationalization | Antarmuka minimal mendukung Bahasa Inggris, dan idealnya Bahasa Indonesia. | Teks tidak hard-coded di komponen utama. |

---

## Section 7: Scope

### In Scope for MVP v1.0

MVP JAGAD mencakup:

1. **Single-chain deployment**
   - Deploy di satu jaringan EVM Layer 2, target awal: Base.
   - Alternatif: Arbitrum One jika ekosistem RWA/oracle lebih cocok saat development.

2. **Token $JGAD**
   - ERC-20 token yang merepresentasikan share kepemilikan vault.
   - Mint saat deposit.
   - Burn saat redeem.

3. **Deposit dan redeem USDC**
   - User hanya perlu menyiapkan USDC sebagai aset masuk/keluar.
   - Deposit fee dan redeem fee dasar.
   - Partial redemption dan redemption queue jika likuiditas tidak cukup.
   - Emergency proportional redemption saat vault paused.

4. **Multi-asset vault basket**
   - Tier 1: 55% (USDC/sDAI 30%, PAXG 15%, synthetic silver 10%)
   - Tier 2: 25% (WBTC)
   - Tier 3: 20% (proxy energi 7%, proxy tambang/logam 7%, proxy properti/REITs 3%, proxy agrikultur 3%)
   - Tier 3 dapat memakai aset on-chain yang tersedia, synthetic exposure, atau approved RWA wrapper jika diperlukan.

5. **Automatic initial allocation**
   - Saat deposit, vault otomatis membagi USDC ke target basket.

6. **Threshold-based rebalancing**
   - Rebalance dipicu ketika deviation bobot aset > 5%.
   - Menjual aset overweight dan membeli aset underweight.
   - Slippage protection wajib.
   - Batch swap untuk efisiensi gas.

7. **Basic yield/revenue sweep**
   - Mendeteksi idle yield/revenue.
   - Sweep jika melebihi minimum threshold ($1,000 USDC).
   - Reinvest ke target yang dikonfigurasi.

8. **Oracle price reading**
   - Menggunakan oracle untuk menghitung NAV dan bobot aset.
   - Validasi freshness dan outlier.
   - Multi-source oracle (Chainlink + Pyth).

9. **Admin controls**
   - Multisig owner.
   - Pause/unpause.
   - Update target weight, threshold, fee, asset address, dan oracle parameter.
   - Timelock untuk perubahan kritis.

10. **Minimal dashboard**
    - Tampilkan NAV.
    - Tampilkan alokasi aktual vs target.
    - Tampilkan deposit/redeem history.
    - Tampilkan rebalance dan sweep history.
    - Tampilkan disclaimer risiko.
    - Tampilkan historical backtest.

11. **Testing dan security baseline**
    - Unit test.
    - Integration test.
    - Fuzz test.
    - Invariant test.
    - Testnet deployment.
    - Internal security review sebelum mainnet soft launch.

12. **Compliance dan edukasi**
    - Jurisdiction gating (geo-block US di MVP).
    - Tidak menggunakan istilah "dividend".
    - Tidak menggunakan tokenized stock US-domiciled di MVP.
    - Disclaimer jelas bahwa $JGAD bukan stablecoin USD.

13. **Backtest dan transparansi**
    - Historical backtest 2020-2026 dipublikasikan sebelum public launch.
    - Max drawdown, CAGR, Sharpe ratio, dan perbandingan dengan BTC/ETH/S&P 500.

14. **Soft launch dengan TVL cap**
    - TVL cap awal: $250,000.
    - Redemption cap per window: $50,000 per 10 menit.
    - Whitelist user opsional.

---

### Out of Scope for MVP v1.0

Berikut **tidak** termasuk MVP dan ditunda ke versi selanjutnya:

| Item | Alasan |
|---|---|
| Custody fiat langsung | Requires banking/license infrastructure. |
| Bank license / money transmitter license | Kompleks secara regulasi dan bukan kebutuhan MVP. |
| Listing di CEX | Butuh likuiditas, reputasi, compliance, dan audit matang. |
| Multi-chain deployment | Menambah kompleksitas bridge, oracle, dan liquidity management. |
| Fully permissionless tokenized stocks dengan dividen bebas | Banyak RWA equity memerlukan KYC/whitelist dan punya risiko regulasi. |
| Lending / borrowing / leverage | Menambah risiko likuidasi dan kompleksitas ekonomi. |
| NFT marketplace | Tidak relevan dengan core value proposition vault. |
| Governance token terpisah | MVP cukup memakai multisig dan parameter control. |
| Native mobile app | Web dApp cukup untuk MVP. |
| Fiat on-ramp kartu kredit | Bisa ditambahkan setelah produk stabil. |
| Insurance fund / cover protocol | Perlu actuarial model dan kapital tersendiri. |
| Performance fee | Bisa menimbulkan konflik kepentingan di awal. |
| Advanced tax reporting | Kompleks per yurisdiksi. |
| Auto hedging via perpetual futures | Menambah risiko counterparty, funding rate, dan liquidation. |
| Full DAO governance | Terlalu dini; MVP butuh kontrol cepat dan aman. |
| Real estate property satuan | Illiquid dan sulit rebalance; MVP lebih aman pakai REITs/proxy. |
| Komoditas fisik yang disimpan sendiri | Butuh gudang, audit fisik, dan logistik. |
| Istilah "dividend" dalam produk dan marketing | Dapat memicu klasifikasi security oleh regulator. Gunakan istilah "yield", "revenue", atau "NAV appreciation". |
| Tokenized stock US-domiciled di MVP | Risiko regulasi tinggi. Gunakan synthetic proxy atau aset on-chain non-security. |

---

### Future Scope Candidates

Setelah MVP stabil, kandidat pengembangan berikutnya:

1. Menambah aset Tier 3 yang lebih luas.
2. Integrasi RWA saham/REITs dengan whitelist compliance.
3. Deployment ke Arbitrum atau chain EVM lain.
4. Liquidity mining untuk pool $JGAD/USDC.
5. Governance parameter oleh holder $JGAD.
6. Institutional/KYC vault version.
7. Insurance module.
8. Auto tax report.
9. Mobile app.
10. Portfolio analytics lanjutan.

---

## Changelog

| Tanggal | Versi | Perubahan |
|---|---|---|
| 2026-10-15 | 0.1.0 | Draft awal PRD |
| 2026-10-16 | 0.2.0 | Update bobot basket: Tier 1 naik ke 55%, Tier 3 turun ke 20% |
| 2026-10-16 | 0.2.0 | Tambah FR-7 dan FR-8: virtual shares dan minimum deposit untuk anti-inflation attack |
| 2026-10-16 | 0.2.0 | Tambah FR-9 sampai FR-14: partial redemption, emergency proportional redemption, redemption cap, liquidity gate, operating reserve |
| 2026-10-16 | 0.2.0 | Tambah FR-54 sampai FR-56: jurisdiction gating, larangan istilah "dividend", larangan tokenized stock US-domiciled di MVP |
| 2026-10-16 | 0.2.0 | Tambah G9, G10, G11: max drawdown relatif terhadap BTC, runway 12 bulan, backtest historis |
| 2026-10-16 | 0.2.0 | Tambah NFR-10 sampai NFR-16: anti-inflation attack, oracle multi-source, slippage protection, emergency pause, audit requirement, runway, backtest transparency |
| 2026-10-16 | 0.2.0 | Update Tier 1: USDC/sDAI naik ke 30% |
| 2026-10-16 | 0.2.0 | Update Tier 3: bobot turun ke 20% dengan komposisi energi 7%, tambang 7%, properti 3%, agri 3% |