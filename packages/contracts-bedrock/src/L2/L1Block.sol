// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { ISemver } from "src/universal/ISemver.sol";

/// @custom:proxied
/// @custom:predeploy 0x4200000000000000000000000000000000000015
/// @title L1Block
/// @notice The L1Block predeploy gives users access to information about the last known L1 block.
///         Values within this contract are updated once per epoch (every L1 block) and can only be
///         set by the "depositor" account, a special system address. Depositor account transactions
///         are created by the protocol whenever we move to a new epoch.
contract L1Block is ISemver {
    /// @notice Address of the special depositor account.
    address public constant DEPOSITOR_ACCOUNT = 0xDeaDDEaDDeAdDeAdDEAdDEaddeAddEAdDEAd0001;

    /// @notice The latest L1 block number known by the L2 system.
    uint64 public number;

    /// @notice The latest L1 timestamp known by the L2 system.
    uint64 public timestamp;

    /// @notice The latest L1 basefee.
    uint256 public basefee;

    /// @notice The latest L1 blockhash.
    bytes32 public hash;

    /// @notice The number of L2 blocks in the same epoch.
    uint64 public sequenceNumber;

    /// @notice The versioned hash to authenticate the batcher by.
    bytes32 public batcherHash;

    /// @notice The overhead value applied to the L1 portion of the transaction fee.
    uint256 public l1FeeOverhead;

    /// @notice The scalar value applied to the L1 portion of the transaction fee.
    uint256 public l1FeeScalar;

    /// @notice Whether the Espresso Sequencer is enabled.
    bool public espresso;

    /// @notice Minimum confirmation depth for L1 origin blocks.
    uint64 public espressoL1ConfDepth;

    /// @custom:semver 1.1.0
    string public constant version = "1.1.0";

    struct L1BlockValues {
        // L1 blocknumber.
        uint64 number;
        // L1 timestamp.
        uint64 timestamp;
        // L1 basefee.
        uint256 basefee;
        // L1 blockhash.
        bytes32 hash;
        // Number of L2 blocks since epoch start.
        uint64 sequenceNumber;
        // Versioned hash to authenticate batcher by.
        bytes32 batcherHash;
        // L1 fee overhead.
        uint256 l1FeeOverhead;
        // L1 fee scalar.
        uint256 l1FeeScalar;
        // Whether the Espresso Sequencer is enabled.
        bool espresso;
        // Minimum confirmation depth for L1 origin blocks.
        uint64 espressoL1ConfDepth;
        // The RLP-encoded L2 batch justification.
        bytes justification;
    }

    /// @notice Updates the L1 block values.
    function setL1BlockValues(L1BlockValues calldata v) external {
        require(msg.sender == DEPOSITOR_ACCOUNT, "L1Block: only the depositor account can set L1 block values");

        number = v.number;
        timestamp = v.timestamp;
        basefee = v.basefee;
        hash = v.hash;
        sequenceNumber = v.sequenceNumber;
        batcherHash = v.batcherHash;
        l1FeeOverhead = v.l1FeeOverhead;
        l1FeeScalar = v.l1FeeScalar;
        espresso = v.espresso;
        espressoL1ConfDepth = v.espressoL1ConfDepth;
    }
}
