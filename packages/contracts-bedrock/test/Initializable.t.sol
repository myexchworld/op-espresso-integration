// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { ERC721Bridge_Initializer } from "test/CommonTest.t.sol";
import { console } from "forge-std/console.sol";
import { CrossDomainMessenger } from "src/universal/CrossDomainMessenger.sol";
import { L2OutputOracle } from "src/L1/L2OutputOracle.sol";
import { SystemConfig } from "src/L1/SystemConfig.sol";
import { ResourceMetering } from "src/L1/ResourceMetering.sol";
import { OptimismPortal } from "src/L1/OptimismPortal.sol";

/// @title Initializer_Test
/// @dev Ensures that the `initialize()` function on contracts cannot be called more than
///      once. This contract inherits from `ERC721Bridge_Initializer` because it is the
///      deepest contract in the inheritance chain for setting up the system contracts.
contract Initializer_Test is ERC721Bridge_Initializer {
    function test_cannotReinitializeL1_succeeds() public {
        vm.expectRevert("Initializable: contract is already initialized");
        L1Messenger.initialize(OptimismPortal(payable(address(0))));

        vm.expectRevert("Initializable: contract is already initialized");
        L1Bridge.initialize(CrossDomainMessenger(address(0)));

        vm.expectRevert("Initializable: contract is already initialized");
        oracle.initialize(0, 0, address(0), address(0));

        vm.expectRevert("Initializable: contract is already initialized");
        op.initialize(L2OutputOracle(address(0)), address(0), SystemConfig(address(0)), false);

        vm.expectRevert("Initializable: contract is already initialized");
        systemConfig.initialize(
            SystemConfig.Initialize({
                owner: address(0xdEaD),
                overhead: 0,
                scalar: 0,
                batcherHash: bytes32(0),
                gasLimit: 1,
                espresso: false,
                espressoL1ConfDepth: 0,
                unsafeBlockSigner: address(0),
                config: ResourceMetering.ResourceConfig({
                    maxResourceLimit: 1,
                    elasticityMultiplier: 1,
                    baseFeeMaxChangeDenominator: 2,
                    minimumBaseFee: 0,
                    systemTxMaxGas: 0,
                    maximumBaseFee: 0
                }),
                startBlock: type(uint256).max,
                batchInbox: address(0),
                addresses: SystemConfig.Addresses({
                    l1CrossDomainMessenger: address(0),
                    l1ERC721Bridge: address(0),
                    l1StandardBridge: address(0),
                    l2OutputOracle: address(0),
                    optimismPortal: address(0),
                    optimismMintableERC20Factory: address(0)
                })
            })
        );

        vm.expectRevert("Initializable: contract is already initialized");
        L1NFTBridge.initialize(CrossDomainMessenger(address(0)));
    }
}
