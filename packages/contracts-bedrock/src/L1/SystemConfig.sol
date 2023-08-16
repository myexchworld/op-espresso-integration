// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Semver } from "../universal/Semver.sol";
import { ResourceMetering } from "./ResourceMetering.sol";

/// @title SystemConfig
/// @notice The SystemConfig contract is used to manage configuration of an Optimism network.
///         All configuration is stored on L1 and picked up by L2 as part of the derviation of
///         the L2 chain.
contract SystemConfig is OwnableUpgradeable, Semver {
    /// @notice Enum representing different types of updates.
    /// @custom:value BATCHER              Represents an update to the batcher hash.
    /// @custom:value GAS_CONFIG           Represents an update to txn fee config on L2.
    /// @custom:value GAS_LIMIT            Represents an update to gas limit on L2.
    /// @custom:value UNSAFE_BLOCK_SIGNER  Represents an update to the signer key for unsafe
    ///                                    block distrubution.
    enum UpdateType {
        BATCHER,
        GAS_CONFIG,
        GAS_LIMIT,
        UNSAFE_BLOCK_SIGNER
    }

    /// @notice Struct representing the addresses of L1 system contracts. These should be the
    ///         proxies and will differ for each OP Stack chain.
    struct Addresses {
        address l1CrossDomainMessenger;
        address l1ERC721Bridge;
        address l1StandardBridge;
        address l2OutputOracle;
        address optimismPortal;
        address optimismMintableERC20Factory;
    }

    /// @notice Version identifier, used for upgrades.
    uint256 public constant VERSION = 0;

    /// @notice Storage slot that the unsafe block signer is stored at.
    ///         Storing it at this deterministic storage slot allows for decoupling the storage
    ///         layout from the way that `solc` lays out storage. The `op-node` uses a storage
    ///         proof to fetch this value.
    /// @dev    NOTE: this value will be migrated to another storage slot in a future version.
    ///         User input should not be placed in storage in this contract until this migration
    ///         happens. It is unlikely that keccak second preimage resistance will be broken,
    ///         but it is better to be safe than sorry.
    bytes32 public constant UNSAFE_BLOCK_SIGNER_SLOT = keccak256("systemconfig.unsafeblocksigner");

    /// @notice Storage slot that the L1CrossDomainMessenger address is stored at.
    bytes32 public constant L1_CROSS_DOMAIN_MESSENGER_SLOT =
        bytes32(uint256(keccak256("systemconfig.l1crossdomainmessenger")) - 1);

    /// @notice Storage slot that the L1ERC721Bridge address is stored at.
    bytes32 public constant L1_ERC_721_BRIDGE_SLOT = bytes32(uint256(keccak256("systemconfig.l1erc721bridge")) - 1);

    /// @notice Storage slot that the L1StandardBridge address is stored at.
    bytes32 public constant L1_STANDARD_BRIDGE_SLOT = bytes32(uint256(keccak256("systemconfig.l1standardbridge")) - 1);

    /// @notice Storage slot that the L2OutputOracle address is stored at.
    bytes32 public constant L2_OUTPUT_ORACLE_SLOT = bytes32(uint256(keccak256("systemconfig.l2outputoracle")) - 1);

    /// @notice Storage slot that the OptimismPortal address is stored at.
    bytes32 public constant OPTIMISM_PORTAL_SLOT = bytes32(uint256(keccak256("systemconfig.optimismportal")) - 1);

    /// @notice Storage slot that the OptimismMintableERC20Factory address is stored at.
    bytes32 public constant OPTIMISM_MINTABLE_ERC20_FACTORY_SLOT =
        bytes32(uint256(keccak256("systemconfig.optimismmintableerc20factory")) - 1);

    /// @notice Storage slot that the batch inbox address is stored at.
    bytes32 public constant BATCH_INBOX_SLOT = bytes32(uint256(keccak256("systemconfig.batchinbox")) - 1);

    /// @notice Fixed L2 gas overhead. Used as part of the L2 fee calculation.
    uint256 public overhead;

    /// @notice Dynamic L2 gas overhead. Used as part of the L2 fee calculation.
    uint256 public scalar;

    /// @notice Identifier for the batcher.
    ///         For version 1 of this configuration, this is represented as an address left-padded
    ///         with zeros to 32 bytes.
    bytes32 public batcherHash;

    /// @notice L2 block gas limit.
    uint64 public gasLimit;

    /// @notice Whether the Espresso Sequencer is enabled.
    bool public espresso;

    /// @notice The configuration for the deposit fee market.
    ///         Used by the OptimismPortal to meter the cost of buying L2 gas on L1.
    ///         Set as internal with a getter so that the struct is returned instead of a tuple.
    ResourceMetering.ResourceConfig internal _resourceConfig;

    /// @notice Emitted when configuration is updated.
    /// @param version    SystemConfig version.
    /// @param updateType Type of update.
    /// @param data       Encoded update data.
    event ConfigUpdate(uint256 indexed version, UpdateType indexed updateType, bytes data);

    /// @notice The block at which the op-node can start searching for logs from.
    uint256 public startBlock;

    /// @custom:semver 1.5.0
    /// @notice Constructs the SystemConfig contract. Cannot set
    ///         the owner to `address(0)` due to the Ownable contract's
    ///         implementation, so set it to `address(0xdEaD)`
    constructor() Semver(1, 5, 0) {
        initialize({
            _owner: address(0xdEaD),
            _overhead: 0,
            _scalar: 0,
            _batcherHash: bytes32(0),
            _gasLimit: 1,
            _espresso: false,
            _unsafeBlockSigner: address(0),
            _config: ResourceMetering.ResourceConfig({
                maxResourceLimit: 1,
                elasticityMultiplier: 1,
                baseFeeMaxChangeDenominator: 2,
                minimumBaseFee: 0,
                systemTxMaxGas: 0,
                maximumBaseFee: 0
            }),
            _startBlock: type(uint256).max,
            _batchInbox: address(0),
            _addresses: SystemConfig.Addresses({
                l1CrossDomainMessenger: address(0),
                l1ERC721Bridge: address(0),
                l1StandardBridge: address(0),
                l2OutputOracle: address(0),
                optimismPortal: address(0),
                optimismMintableERC20Factory: address(0)
            })
        });
    }

    /// @notice Initializer.
    ///         The resource config must be set before the require check.
    /// @param _owner             Initial owner of the contract.
    /// @param _overhead          Initial overhead value.
    /// @param _scalar            Initial scalar value.
    /// @param _batcherHash       Initial batcher hash.
    /// @param _gasLimit          Initial gas limit.
    /// @param _unsafeBlockSigner Initial unsafe block signer address.
    /// @param _config            Initial ResourceConfig.
    /// @param _startBlock        Starting block for the op-node to search for logs from.
    ///                           Contracts that were deployed before this field existed
    ///                           need to have this field set manually via an override.
    ///                           Newly deployed contracts should set this value to uint256(0).
    /// @param _batchInbox        Batch inbox address. An identifier for the op-node to find
    ///                           canonical data.
    /// @param _addresses         Set of L1 contract addresses. These should be the proxies.
    function initialize(
        address _owner,
        uint256 _overhead,
        uint256 _scalar,
        bytes32 _batcherHash,
        uint64 _gasLimit,
        bool _espresso,
        address _unsafeBlockSigner,
        ResourceMetering.ResourceConfig memory _config,
        uint256 _startBlock,
        address _batchInbox,
        SystemConfig.Addresses memory _addresses
    )
        public
        reinitializer(2)
    {
        __Ownable_init();
        transferOwnership(_owner);

        overhead = _overhead;
        scalar = _scalar;
        batcherHash = _batcherHash;
        gasLimit = _gasLimit;
        espresso = _espresso;

        _setAddress(_unsafeBlockSigner, UNSAFE_BLOCK_SIGNER_SLOT);
        _setAddress(_batchInbox, BATCH_INBOX_SLOT);
        _setAddress(_addresses.l1CrossDomainMessenger, L1_CROSS_DOMAIN_MESSENGER_SLOT);
        _setAddress(_addresses.l1ERC721Bridge, L1_ERC_721_BRIDGE_SLOT);
        _setAddress(_addresses.l1StandardBridge, L1_STANDARD_BRIDGE_SLOT);
        _setAddress(_addresses.l2OutputOracle, L2_OUTPUT_ORACLE_SLOT);
        _setAddress(_addresses.optimismPortal, OPTIMISM_PORTAL_SLOT);
        _setAddress(_addresses.optimismMintableERC20Factory, OPTIMISM_MINTABLE_ERC20_FACTORY_SLOT);

        _setStartBlock(_startBlock);

        _setResourceConfig(_config);
        require(_gasLimit >= minimumGasLimit(), "SystemConfig: gas limit too low");
    }

    /// @notice Returns the minimum L2 gas limit that can be safely set for the system to
    ///         operate. The L2 gas limit must be larger than or equal to the amount of
    ///         gas that is allocated for deposits per block plus the amount of gas that
    ///         is allocated for the system transaction.
    ///         This function is used to determine if changes to parameters are safe.
    /// @return uint64 Minimum gas limit.
    function minimumGasLimit() public view returns (uint64) {
        return uint64(_resourceConfig.maxResourceLimit) + uint64(_resourceConfig.systemTxMaxGas);
    }

    /// @notice High level getter for the unsafe block signer address.
    ///         Unsafe blocks can be propagated across the p2p network if they are signed by the
    ///         key corresponding to this address.
    /// @return addr_ Address of the unsafe block signer.
    // solhint-disable-next-line ordering
    function unsafeBlockSigner() external view returns (address addr_) {
        addr_ = _getAddress(UNSAFE_BLOCK_SIGNER_SLOT);
    }

    /// @notice Stores an address in an arbitrary storage slot, `_slot`.
    /// @param _addr The address to store
    /// @param _slot The storage slot to store the address in.
    /// @dev WARNING! This function must be used cautiously, as it allows for overwriting values
    ///      in arbitrary storage slots. Solc will add checks that the data passed as `_addr`
    ///      is 20 bytes or less.
    function _setAddress(address _addr, bytes32 _slot) internal {
        assembly {
            sstore(_slot, _addr)
        }
    }

    /// @notice Returns an address stored in an arbitrary storage slot.
    ///         These storage slots decouple the storage layout from
    ///         solc's automation.
    /// @param _slot The storage slot to retrieve the address from.
    function _getAddress(bytes32 _slot) internal view returns (address addr_) {
        assembly {
            addr_ := sload(_slot)
        }
    }

    /// @notice Getter for the L1CrossDomainMessenger address.
    function l1CrossDomainMessenger() external view returns (address addr_) {
        addr_ = _getAddress(L1_CROSS_DOMAIN_MESSENGER_SLOT);
    }

    /// @notice Getter for the L1ERC721Bridge address.
    function l1ERC721Bridge() external view returns (address addr_) {
        addr_ = _getAddress(L1_ERC_721_BRIDGE_SLOT);
    }

    /// @notice Getter for the L1StandardBridge address.
    function l1StandardBridge() external view returns (address addr_) {
        addr_ = _getAddress(L1_STANDARD_BRIDGE_SLOT);
    }

    /// @notice Getter for the L2OutputOracle address.
    function l2OutputOracle() external view returns (address addr_) {
        addr_ = _getAddress(L2_OUTPUT_ORACLE_SLOT);
    }

    /// @notice Getter for the OptimismPortal address.
    function optimismPortal() external view returns (address addr_) {
        addr_ = _getAddress(OPTIMISM_PORTAL_SLOT);
    }

    /// @notice Getter for the OptimismMintableERC20Factory address.
    function optimismMintableERC20Factory() external view returns (address addr_) {
        addr_ = _getAddress(OPTIMISM_MINTABLE_ERC20_FACTORY_SLOT);
    }

    /// @notice Getter for the BatchInbox address.
    function batchInbox() external view returns (address addr_) {
        addr_ = _getAddress(BATCH_INBOX_SLOT);
    }

    /// @notice Sets the start block in a backwards compatible way. Proxies
    ///         that were initialized before the startBlock existed in storage
    ///         can have their start block set by a user provided override.
    ///         A start block of 0 indicates that there is no override and the
    ///         start block will be set by `block.number`.
    /// @dev    This logic is used to patch legacy with new storage values. In the
    ///         next version, it should remove the override and set the start block
    ///         to `block.number` if the value in storage is 0. This will allow it
    ///         to be reinitialized again and also work for fresh deployments.
    /// @param  _startBlock The start block override to set in storage.
    function _setStartBlock(uint256 _startBlock) internal {
        require(startBlock == 0, "SystemConfig: cannot override an already set start block");
        if (_startBlock != 0) {
            // There is an override, it cannot already be set.
            startBlock = _startBlock;
        } else {
            // There is no override and it is not set in storage. Set it to the block number.
            startBlock = block.number;
        }
    }

    /// @notice Updates the unsafe block signer address.
    /// @param _unsafeBlockSigner New unsafe block signer address.
    function setUnsafeBlockSigner(address _unsafeBlockSigner) external onlyOwner {
        _setAddress(_unsafeBlockSigner, UNSAFE_BLOCK_SIGNER_SLOT);

        bytes memory data = abi.encode(_unsafeBlockSigner);
        emit ConfigUpdate(VERSION, UpdateType.UNSAFE_BLOCK_SIGNER, data);
    }

    /// @notice Updates the batcher hash.
    /// @param _batcherHash New batcher hash.
    function setBatcherHash(bytes32 _batcherHash) external onlyOwner {
        batcherHash = _batcherHash;

        bytes memory data = abi.encode(_batcherHash);
        emit ConfigUpdate(VERSION, UpdateType.BATCHER, data);
    }

    /// @notice Updates gas config.
    /// @param _overhead New overhead value.
    /// @param _scalar   New scalar value.
    function setGasConfig(uint256 _overhead, uint256 _scalar) external onlyOwner {
        overhead = _overhead;
        scalar = _scalar;

        bytes memory data = abi.encode(_overhead, _scalar);
        emit ConfigUpdate(VERSION, UpdateType.GAS_CONFIG, data);
    }

    /// @notice Updates the L2 gas limit.
    /// @param _gasLimit New gas limit.
    function setGasLimit(uint64 _gasLimit) external onlyOwner {
        require(_gasLimit >= minimumGasLimit(), "SystemConfig: gas limit too low");
        gasLimit = _gasLimit;

        bytes memory data = abi.encode(_gasLimit);
        emit ConfigUpdate(VERSION, UpdateType.GAS_LIMIT, data);
    }

    /// @notice A getter for the resource config.
    ///         Ensures that the struct is returned instead of a tuple.
    /// @return ResourceConfig
    function resourceConfig() external view returns (ResourceMetering.ResourceConfig memory) {
        return _resourceConfig;
    }

    /// @notice An external setter for the resource config.
    ///         In the future, this method may emit an event that the `op-node` picks up
    ///         for when the resource config is changed.
    /// @param _config The new resource config values.
    function setResourceConfig(ResourceMetering.ResourceConfig memory _config) external onlyOwner {
        _setResourceConfig(_config);
    }

    /// @notice An internal setter for the resource config.
    ///         Ensures that the config is sane before storing it by checking for invariants.
    /// @param _config The new resource config.
    function _setResourceConfig(ResourceMetering.ResourceConfig memory _config) internal {
        // Min base fee must be less than or equal to max base fee.
        require(
            _config.minimumBaseFee <= _config.maximumBaseFee, "SystemConfig: min base fee must be less than max base"
        );
        // Base fee change denominator must be greater than 1.
        require(_config.baseFeeMaxChangeDenominator > 1, "SystemConfig: denominator must be larger than 1");
        // Max resource limit plus system tx gas must be less than or equal to the L2 gas limit.
        // The gas limit must be increased before these values can be increased.
        require(_config.maxResourceLimit + _config.systemTxMaxGas <= gasLimit, "SystemConfig: gas limit too low");
        // Elasticity multiplier must be greater than 0.
        require(_config.elasticityMultiplier > 0, "SystemConfig: elasticity multiplier cannot be 0");
        // No precision loss when computing target resource limit.
        require(
            ((_config.maxResourceLimit / _config.elasticityMultiplier) * _config.elasticityMultiplier)
                == _config.maxResourceLimit,
            "SystemConfig: precision loss with target resource limit"
        );

        _resourceConfig = _config;
    }
}
