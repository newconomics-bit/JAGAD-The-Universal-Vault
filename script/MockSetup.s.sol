// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockDEXRouter} from "../src/mocks/MockDEXRouter.sol";
import {MockChainlinkAggregator} from "../src/mocks/MockChainlinkAggregator.sol";
import {MockPythPrice} from "../src/mocks/MockPythPrice.sol";

contract MockSetup is Script {
    // Token addresses
    address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public constant PAXG = 0x1234567890123456789012345678901234567890;
    address public constant WBTC = 0x0987654321098765432109876543210987654321;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Setting up Mock Contracts for Testnet ===");
        
        // 1. Deploy Mock USDC (if not using real USDC)
        console.log("1. Deploying Mock USDC...");
        MockERC20 mockUsdc = new MockERC20("USD Coin", "USDC", 6);
        console.log("   Mock USDC deployed at:", address(mockUsdc));
        
        // Mint to deployer
mockUsdc.mint(msg.sender, 1000000 * 10**6); // 1M USDC
        console.log("   Minted 1M USDC to deployer");
        
        // 2. Deploy Mock PAXG
        console.log("2. Deploying Mock PAXG...");
        MockERC20 mockPaxg = new MockERC20("PAX Gold", "PAXG", 18);
        console.log("   Mock PAXG deployed at:", address(mockPaxg));
        
        // Mint to deployer
        mockPaxg.mint(msg.sender, 10000 * 10**18); // 10K PAXG
        console.log("   Minted 10K PAXG to deployer");
        
        // 3. Deploy Mock WBTC
        console.log("3. Deploying Mock WBTC...");
        MockERC20 mockWbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        console.log("   Mock WBTC deployed at:", address(mockWbtc));
        
        // Mint to deployer
        mockWbtc.mint(msg.sender, 1000 * 10**8); // 1000 WBTC
        console.log("   Minted 1000 WBTC to deployer");

        // 4. Deploy Mock Chainlink Aggregators
        console.log("4. Deploying Mock Chainlink Aggregators...");
        
        MockChainlinkAggregator usdcFeed = new MockChainlinkAggregator();
        usdcFeed.setLatestAnswer(1 * 10**8); // 1 USD = 1 USDC
        usdcFeed.setLatestTimestamp(block.timestamp);
        usdcFeed.setDecimals(8);
        console.log("   USDC Feed deployed at:", address(usdcFeed));
        
        MockChainlinkAggregator paxgFeed = new MockChainlinkAggregator();
        paxgFeed.setLatestAnswer(2000 * 10**8); // 2000 USD = 1 PAXG
        paxgFeed.setLatestTimestamp(block.timestamp);
        paxgFeed.setDecimals(8);
        console.log("   PAXG Feed deployed at:", address(paxgFeed));
        
        MockChainlinkAggregator wbtcFeed = new MockChainlinkAggregator();
        wbtcFeed.setLatestAnswer(50000 * 10**8); // 50000 USD = 1 WBTC
        wbtcFeed.setLatestTimestamp(block.timestamp);
        wbtcFeed.setDecimals(8);
        console.log("   WBTC Feed deployed at:", address(wbtcFeed));

        // 5. Deploy Mock Pyth Prices
        console.log("5. Deploying Mock Pyth Prices...");
        
        MockPythPrice pythPaxg = new MockPythPrice();
        pythPaxg.setPrice(2000 * 10**18);
        pythPaxg.setPublishTime(block.timestamp);
        console.log("   PAXG Pyth Price deployed at:", address(pythPaxg));
        
        MockPythPrice pythWbtc = new MockPythPrice();
        pythWbtc.setPrice(50000 * 10**18);
        pythWbtc.setPublishTime(block.timestamp);
        console.log("   WBTC Pyth Price deployed at:", address(pythWbtc));

        // 6. Deploy Mock DEX Router
        console.log("6. Deploying Mock DEX Router...");
        MockDEXRouter mockDex = new MockDEXRouter();
        
        // Set rates:
        // USDC -> PAXG: 1 USDC = 0.0005 PAXG
        // rate = 0.0005 * 1e18 = 5e14 (but adjusted for decimals)
        // amountOut = amountIn * rate / 1e18
        // 1e6 USDC * rate / 1e18 = 5e14 PAXG -> rate = 5e14 * 1e18 / 1e6 = 5e26
        mockDex.setRate(address(mockUsdc), address(mockPaxg), 500_000_000_000_000_000_000_000_000); // 5e26
        mockDex.setRate(address(mockPaxg), address(mockUsdc), 2_000_000_000); // 1 PAXG = 2000 USDC
        
        // USDC -> WBTC: 1 USDC = 0.00002 WBTC
        // 1e6 USDC * rate / 1e18 = 2e3 WBTC -> rate = 2e3 * 1e18 / 1e6 = 2e15
        mockDex.setRate(address(mockUsdc), address(mockWbtc), 2_000_000_000_000_000); // 2e15
        mockDex.setRate(address(mockWbtc), address(mockUsdc), 500_000_000_000_000_000_000); // 5e20
        
        console.log("   Mock DEX Router deployed at:", address(mockDex));
        console.log("   Rates configured:");
        console.log("     USDC -> PAXG: 1 USDC = 0.0005 PAXG");
        console.log("     PAXG -> USDC: 1 PAXG = 2000 USDC");
        console.log("     USDC -> WBTC: 1 USDC = 0.00002 WBTC");
        console.log("     WBTC -> USDC: 1 WBTC = 50000 USDC");

        // 7. Fund DEX Router with liquidity
        console.log("7. Funding DEX Router with liquidity...");
        mockPaxg.mint(address(mockDex), 10000 * 10**18); // 10K PAXG
        mockWbtc.mint(address(mockDex), 10000 * 10**8);  // 10K WBTC
        mockUsdc.mint(address(mockDex), 1000000 * 10**6); // 1M USDC
        console.log("   DEX Router funded with 10K PAXG, 10K WBTC, 1M USDC");

        // Save mock addresses to JSON
        _saveMockAddresses(
            address(mockUsdc),
            address(mockPaxg),
            address(mockWbtc),
            address(usdcFeed),
            address(paxgFeed),
            address(wbtcFeed),
            address(pythPaxg),
            address(pythWbtc),
            address(mockDex)
        );

        vm.stopBroadcast();
        
        console.log("=== Mock Setup Complete ===");
    }

    function _saveMockAddresses(
        address mockUsdc,
        address mockPaxg,
        address mockWbtc,
        address usdcFeed,
        address paxgFeed,
        address wbtcFeed,
        address pythPaxg,
        address pythWbtc,
        address mockDex
    ) internal {
        string memory chainId = vm.toString(block.chainid);
        string memory network = _getNetworkName(chainId);
        string memory filename = string.concat("deployments/", network, "-mocks.json");
        
        string memory json = string.concat(
            '{\n',
            '  "chainId": ', vm.toString(block.chainid), ',\n',
            '  "deployedAt": ', vm.toString(block.timestamp), ',\n',
            '  "mockUsdc": "', vm.toString(mockUsdc), '",\n',
            '  "mockPaxg": "', vm.toString(mockPaxg), '",\n',
            '  "mockWbtc": "', vm.toString(mockWbtc), '",\n',
            '  "usdcFeed": "', vm.toString(usdcFeed), '",\n',
            '  "paxgFeed": "', vm.toString(paxgFeed), '",\n',
            '  "wbtcFeed": "', vm.toString(wbtcFeed), '",\n',
            '  "pythPaxg": "', vm.toString(pythPaxg), '",\n',
            '  "pythWbtc": "', vm.toString(pythWbtc), '",\n',
            '  "mockDexRouter": "', vm.toString(mockDex), '"\n',
            '}\n'
        );
        
        vm.writeFile(filename, json);
        console.log("Mock addresses saved to:", filename);
    }

    function _getNetworkName(string memory chainId) internal pure returns (string memory) {
        if (keccak256(abi.encode(chainId)) == keccak256(abi.encode("84532"))) {
            return "base-sepolia";
        } else if (keccak256(abi.encode(chainId)) == keccak256(abi.encode("8453"))) {
            return "base-mainnet";
        } else if (keccak256(abi.encode(chainId)) == keccak256(abi.encode("31337"))) {
            return "anvil";
        }
        return "unknown";
    }
}