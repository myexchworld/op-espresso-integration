package e2eutils

import (
	"math/big"
	"os"
	"path"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/ethereum/go-ethereum/core"

	"github.com/stretchr/testify/require"

	"github.com/ethereum-optimism/optimism/op-chain-ops/genesis"
	"github.com/ethereum-optimism/optimism/op-e2e/config"
	"github.com/ethereum-optimism/optimism/op-node/rollup"
	"github.com/ethereum-optimism/optimism/op-service/eth"
)

var testingJWTSecret = [32]byte{123}

// WriteDefaultJWT writes a testing JWT to the temporary directory of the test and returns the path to the JWT file.
func WriteDefaultJWT(t TestingBase) string {
	// Sadly the geth node config cannot load JWT secret from memory, it has to be a file
	jwtPath := path.Join(t.TempDir(), "jwt_secret")
	if err := os.WriteFile(jwtPath, []byte(hexutil.Encode(testingJWTSecret[:])), 0600); err != nil {
		t.Fatalf("failed to prepare jwt file for geth: %v", err)
	}
	return jwtPath
}

// DeployParams bundles the deployment parameters to generate further testing inputs with.
type DeployParams struct {
	DeployConfig   *genesis.DeployConfig
	MnemonicConfig *MnemonicConfig
	Secrets        *Secrets
	Addresses      *Addresses
}

// TestParams parametrizes the most essential rollup configuration parameters
type TestParams struct {
	MaxSequencerDrift   uint64
	SequencerWindowSize uint64
	ChannelTimeout      uint64
	L1BlockTime         uint64
}

func MakeDeployParams(t require.TestingT, tp *TestParams) *DeployParams {
	mnemonicCfg := DefaultMnemonicConfig
	secrets, err := mnemonicCfg.Secrets()
	require.NoError(t, err)
	addresses := secrets.Addresses()

	deployConfig := config.DeployConfig.Copy()
	deployConfig.MaxSequencerDrift = tp.MaxSequencerDrift
	deployConfig.SequencerWindowSize = tp.SequencerWindowSize
	deployConfig.ChannelTimeout = tp.ChannelTimeout
	deployConfig.L1BlockTime = tp.L1BlockTime
	deployConfig.L2GenesisRegolithTimeOffset = nil
	deployConfig.L2GenesisCanyonTimeOffset = CanyonTimeOffset()
	deployConfig.L2GenesisSpanBatchTimeOffset = SpanBatchTimeOffset()

	require.NoError(t, deployConfig.Check())
	require.Equal(t, addresses.Batcher, deployConfig.BatchSenderAddress)
	require.Equal(t, addresses.Proposer, deployConfig.L2OutputOracleProposer)
	require.Equal(t, addresses.SequencerP2P, deployConfig.P2PSequencerAddress)

	return &DeployParams{
		DeployConfig:   deployConfig,
		MnemonicConfig: mnemonicCfg,
		Secrets:        secrets,
		Addresses:      addresses,
	}
}

// SetupData bundles the L1, L2, rollup and deployment configuration data: everything for a full test setup.
type SetupData struct {
	L1Cfg         *core.Genesis
	L2Cfg         *core.Genesis
	RollupCfg     *rollup.Config
	DeploymentsL1 *genesis.L1Deployments
}

// AllocParams defines genesis allocations to apply on top of the genesis generated by deploy parameters.
// These allocations override existing allocations per account,
// i.e. the allocations are merged with AllocParams having priority.
type AllocParams struct {
	L1Alloc          core.GenesisAlloc
	L2Alloc          core.GenesisAlloc
	PrefundTestUsers bool
}

var etherScalar = new(big.Int).Exp(big.NewInt(10), big.NewInt(18), nil)

// Ether converts a uint64 Ether amount into a *big.Int amount in wei units, for allocating test balances.
func Ether(v uint64) *big.Int {
	return new(big.Int).Mul(new(big.Int).SetUint64(v), etherScalar)
}

// Setup computes the testing setup configurations from deployment configuration and optional allocation parameters.
func Setup(t require.TestingT, deployParams *DeployParams, alloc *AllocParams) *SetupData {
	deployConf := deployParams.DeployConfig.Copy()
	deployConf.L1GenesisBlockTimestamp = hexutil.Uint64(time.Now().Unix())
	require.NoError(t, deployConf.Check())

	l1Deployments := config.L1Deployments.Copy()
	require.NoError(t, l1Deployments.Check())

	l1Genesis, err := genesis.BuildL1DeveloperGenesis(deployConf, config.L1Allocs, l1Deployments, true)
	require.NoError(t, err, "failed to create l1 genesis")
	if alloc.PrefundTestUsers {
		for _, addr := range deployParams.Addresses.All() {
			l1Genesis.Alloc[addr] = core.GenesisAccount{
				Balance: Ether(1e12),
			}
		}
	}
	for addr, val := range alloc.L1Alloc {
		l1Genesis.Alloc[addr] = val
	}

	l1Block := l1Genesis.ToBlock()

	l2Genesis, err := genesis.BuildL2Genesis(deployConf, l1Block)
	require.NoError(t, err, "failed to create l2 genesis")
	if alloc.PrefundTestUsers {
		for _, addr := range deployParams.Addresses.All() {
			l2Genesis.Alloc[addr] = core.GenesisAccount{
				Balance: Ether(1e12),
			}
		}
	}
	for addr, val := range alloc.L2Alloc {
		l2Genesis.Alloc[addr] = val
	}

	rollupCfg := &rollup.Config{
		Genesis: rollup.Genesis{
			L1: eth.BlockID{
				Hash:   l1Block.Hash(),
				Number: 0,
			},
			L2: eth.BlockID{
				Hash:   l2Genesis.ToBlock().Hash(),
				Number: 0,
			},
			L2Time:       uint64(deployConf.L1GenesisBlockTimestamp),
			SystemConfig: SystemConfigFromDeployConfig(deployConf),
		},
		BlockTime:              deployConf.L2BlockTime,
		MaxSequencerDrift:      deployConf.MaxSequencerDrift,
		SeqWindowSize:          deployConf.SequencerWindowSize,
		ChannelTimeout:         deployConf.ChannelTimeout,
		L1ChainID:              new(big.Int).SetUint64(deployConf.L1ChainID),
		L2ChainID:              new(big.Int).SetUint64(deployConf.L2ChainID),
		BatchInboxAddress:      deployConf.BatchInboxAddress,
		DepositContractAddress: deployConf.OptimismPortalProxy,
		L1SystemConfigAddress:  deployConf.SystemConfigProxy,
		RegolithTime:           deployConf.RegolithTime(uint64(deployConf.L1GenesisBlockTimestamp)),
		CanyonTime:             deployConf.CanyonTime(uint64(deployConf.L1GenesisBlockTimestamp)),
		SpanBatchTime:          deployConf.SpanBatchTime(uint64(deployConf.L1GenesisBlockTimestamp)),
	}

	require.NoError(t, rollupCfg.Check())

	// Sanity check that the config is correct
	require.Equal(t, deployParams.Secrets.Addresses().Batcher, deployParams.DeployConfig.BatchSenderAddress)
	require.Equal(t, deployParams.Secrets.Addresses().SequencerP2P, deployParams.DeployConfig.P2PSequencerAddress)
	require.Equal(t, deployParams.Secrets.Addresses().Proposer, deployParams.DeployConfig.L2OutputOracleProposer)

	return &SetupData{
		L1Cfg:         l1Genesis,
		L2Cfg:         l2Genesis,
		RollupCfg:     rollupCfg,
		DeploymentsL1: l1Deployments,
	}
}

func SystemConfigFromDeployConfig(deployConfig *genesis.DeployConfig) eth.SystemConfig {
	return eth.SystemConfig{
		BatcherAddr: deployConfig.BatchSenderAddress,
		Overhead:    eth.Bytes32(common.BigToHash(new(big.Int).SetUint64(deployConfig.GasPriceOracleOverhead))),
		Scalar:      eth.Bytes32(common.BigToHash(new(big.Int).SetUint64(deployConfig.GasPriceOracleScalar))),
		GasLimit:    uint64(deployConfig.L2GenesisBlockGasLimit),
		Espresso:    deployConfig.Espresso,
	}
}

func SpanBatchTimeOffset() *hexutil.Uint64 {
	if os.Getenv("OP_E2E_USE_SPAN_BATCH") == "true" {
		offset := hexutil.Uint64(0)
		return &offset
	}
	return nil
}

func CanyonTimeOffset() *hexutil.Uint64 {
	if os.Getenv("OP_E2E_USE_CANYON") == "true" {
		offset := hexutil.Uint64(0)
		return &offset
	}
	return nil
}
