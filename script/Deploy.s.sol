// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {JagadToken} from "../src/JagadToken.sol";
import {AssetRegistry} from "../src/AssetRegistry.sol";
import {OracleReader} from "../src/OracleReader.sol";
import {Treasury} from "../src/Treasury.sol";
import {RedemptionQueue} from "../src/RedemptionQueue.sol";
import {Rebalancer} from "../src/Rebalancer.sol";
import {YieldSweeper} from "../src/YieldSweeper.sol";
import {JagadVault} from "../src/JagadVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDexRouter} from "../src/interfaces/IDexRouter.sol";
import {IRebalancer} from "../src/interfaces/IRebalancer.sol";
import {IYieldSweeper} from "../src/interfaces/IYieldSweeper.sol";
import {IRedemptionQueue} from "../src/interfaces/IRedemptionQueue.sol";
import {MockDEXRouter} from "../src/mocks/MockDEXRouter.sol";

contract Deploy is Script {
    // Network configuration
    address public constant USDC_ADDRESS = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // Base Sepolia USDC
    
    // Oracle configuration
    uint256 public constant MAX_STALENESS = 3600; // 1 hour
    uint256 public constant MAX_DEVIATION_BPS = 500; // 5%
    
    // Redemption configuration
    uint256 public constant REDEMPTION_CAP_PER_WINDOW = 50000 * 10**6; // $50k
    uint256 public constant REDEMPTION_WINDOW_SECONDS = 600; // 10 minutes

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Starting JAGAD Vault Deployment ===");
        
        // 1. Deploy JagadToken (placeholder vault address, will update later)
        console.log("1. Deploying JagadToken...");
        JagadToken jagadToken = new JagadToken("JAGAD", "JAGAD", address(0));
        console.log("   JagadToken deployed at:", address(jagadToken));

        // 2. Deploy AssetRegistry
        console.log("2. Deploying AssetRegistry...");
        AssetRegistry assetRegistry = new AssetRegistry();
        console.log("   AssetRegistry deployed at:", address(assetRegistry));

        // 3. Deploy OracleReader
        console.log("3. Deploying OracleReader...");
        OracleReader oracleReader = new OracleReader(MAX_STALENESS, MAX_DEVIATION_BPS);
        console.log("   OracleReader deployed at:", address(oracleReader));

        // 4. Deploy Treasury
        console.log("4. Deploying Treasury...");
        Treasury treasury = new Treasury();
        console.log("   Treasury deployed at:", address(treasury));

        // 5. Deploy RedemptionQueue (placeholder vault address)
        console.log("5. Deploying RedemptionQueue...");
        RedemptionQueue redemptionQueue = new RedemptionQueue(
            address(0), // vault placeholder
            address(oracleReader),
            address(assetRegistry)
        );
        console.log("   RedemptionQueue deployed at:", address(redemptionQueue));

        // 6. Deploy Rebalancer (placeholder vault address)
        console.log("6. Deploying Rebalancer...");
        // Use a mock DEX router for testnet or real one for mainnet
        IDexRouter dexRouter = _getDexRouter();
        Rebalancer rebalancer = new Rebalancer(
            address(0), // vault placeholder
            address(assetRegistry),
            address(oracleReader),
            address(dexRouter)
        );
        console.log("   Rebalancer deployed at:", address(rebalancer));

        // 7. Deploy YieldSweeper (placeholder vault address)
        console.log("7. Deploying YieldSweeper...");
        YieldSweeper yieldSweeper = new YieldSweeper(
            address(0), // vault placeholder
            address(assetRegistry),
            address(oracleReader),
            address(dexRouter)
        );
        console.log("   YieldSweeper deployed at:", address(yieldSweeper));

        // 8. Deploy JagadVault Implementation
        console.log("8. Deploying JagadVault Implementation...");
        JagadVault vaultImpl = new JagadVault(
            USDC_ADDRESS,
            address(oracleReader),
            address(assetRegistry),
            address(treasury)
        );
        console.log("   JagadVault Implementation deployed at:", address(vaultImpl));

        // 9. Deploy ERC1967Proxy pointing to JagadVault Implementation
        console.log("9. Deploying ERC1967Proxy...");
        // Encode initialize calldata
        bytes memory initCalldata = abi.encodeWithSelector(
            JagadVault.initialize.selector,
            USDC_ADDRESS,
            address(oracleReader),
            address(assetRegistry),
            address(treasury)
        );
        
        ERC1967Proxy vaultProxy = new ERC1967Proxy(
            address(vaultImpl),
            initCalldata
        );
        console.log("   ERC1967Proxy (Vault) deployed at:", address(vaultProxy));

        // 10. Initialize contracts with correct vault address
        console.log("10. Initializing contracts with vault proxy address...");
        
        // Initialize JagadToken with vault proxy address
        jagadToken.initialize(address(vaultProxy));
        console.log("    JagadToken initialized with vault:", address(vaultProxy));

        // Update RedemptionQueue with vault proxy address
        redemptionQueue.setVaultAddress(address(vaultProxy));
        console.log("    RedemptionQueue updated with vault:", address(vaultProxy));

        // Update Rebalancer with vault proxy address
        rebalancer.setVaultAddress(address(vaultProxy));
        console.log("    Rebalancer updated with vault:", address(vaultProxy));

        // Update YieldSweeper with vault proxy address
        yieldSweeper.setVaultAddress(address(vaultProxy));
        console.log("    YieldSweeper updated with vault:", address(vaultProxy));

        // 11. Initialize Vault through proxy
        console.log("11. Initializing Vault through proxy...");
        JagadVault vault = JagadVault(address(vaultProxy));
        vault.setJagadToken(jagadToken);
        vault.setRebalancer(IRebalancer(address(rebalancer)));
        vault.setYieldSweeper(IYieldSweeper(address(yieldSweeper)));
        vault.setRedemptionQueue(IRedemptionQueue(address(redemptionQueue)));
        vault.setDexRouter(IDexRouter(address(dexRouter)));
        console.log("    Vault initialized with all components");

        // Save deployment addresses to JSON
        _saveDeploymentAddresses(
            address(jagadToken),
            address(assetRegistry),
            address(oracleReader),
            address(treasury),
            address(redemptionQueue),
            address(rebalancer),
            address(yieldSweeper),
            address(vaultImpl),
            address(vaultProxy),
            address(dexRouter)
        );

        vm.stopBroadcast();
        
        console.log("=== Deployment Complete ===");
    }

    function _getDexRouter() internal returns (IDexRouter) {
        // Check if we're on a testnet or local network
        // For testnet, deploy a mock; for mainnet, use a real DEX router
        string memory useMockDex = vm.envString("USE_MOCK_DEX");
        if (block.chainid == 31337 || keccak256(abi.encodePacked(useMockDex)) == keccak256(abi.encodePacked("true"))) {
            MockDEXRouter mockDex = new MockDEXRouter();
            // Set default rates (can be configured in Configure.s.sol)
            mockDex.setRate(USDC_ADDRESS, 0x1234567890123456789012345678901234567890, 1e18);
            mockDex.setRate(0x1234567890123456789012345678901234567890, USDC_ADDRESS, 1e18);
            return IDexRouter(address(mockDex));
        }
        // For mainnet, use a real DEX router (e.g., Aerodrome, Uniswap V3)
        // This would need to be configured per network
        return IDexRouter(vm.envAddress("DEX_ROUTER"));
    }

    function _saveDeploymentAddresses(
        address jagadToken,
        address assetRegistry,
        address oracleReader,
        address treasury,
        address redemptionQueue,
        address rebalancer,
        address yieldSweeper,
        address vaultImpl,
        address vaultProxy,
        address dexRouter
    ) internal {
        string memory chainId = vm.toString(block.chainid);
        string memory network = _getNetworkName(chainId);
        string memory filename = string.concat("deployments/", network, ".json");
        
        string memory json = _generateDeploymentJson(
            jagadToken,
            assetRegistry,
            oracleReader,
            treasury,
            redemptionQueue,
            rebalancer,
            yieldSweeper,
            vaultImpl,
            vaultProxy,
            dexRouter
        );
        
        vm.writeFile(filename, json);
        console.log("Deployment addresses saved to:", filename);
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

    function _generateDeploymentJson(
        address jagadToken,
        address assetRegistry,
        address oracleReader,
        address treasury,
        address redemptionQueue,
        address rebalancer,
        address yieldSweeper,
        address vaultImpl,
        address vaultProxy,
        address dexRouter
    ) internal view returns (string memory) {
        return string.concat(
            '{\n',
            '  "chainId": ', vm.toString(block.chainid), ',\n',
            '  "deployedAt": ', vm.toString(block.timestamp), ',\n',
            '  "jagadToken": "', vm.toString(jagadToken), '",\n',
            '  "assetRegistry": "', vm.toString(assetRegistry), '",\n',
            '  "oracleReader": "', vm.toString(oracleReader), '",\n',
            '  "treasury": "', vm.toString(treasury), '",\n',
            '  "redemptionQueue": "', vm.toString(redemptionQueue), '",\n',
            '  "rebalancer": "', vm.toString(rebalancer), '",\n',
            '  "yieldSweeper": "', vm.toString(yieldSweeper), '",\n',
            '  "vaultImplementation": "', vm.toString(vaultImpl), '",\n',
            '  "vaultProxy": "', vm.toString(vaultProxy), '",\n',
            '  "dexRouter": "', vm.toString(dexRouter), '",\n',
            '  "usdc": "', vm.toString(USDC_ADDRESS), '"\n',
            '}\n'
        );
    }
}