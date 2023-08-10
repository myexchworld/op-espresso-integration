package espresso

import (
	"math/big"
)

type Header struct {
	L1Block          L1BlockInfo `json:"l1_block"`
	Timestamp        uint64      `json:"timestamp"`
	TransactionsRoot NmtRoot     `json:"transactions_root"`
}

type L1BlockInfo struct {
	Number    uint64  `json:"number"`
	Timestamp big.Int `json:"timestamp"`
}

type BatchMerkleProof = []byte
type NmtRoot = []byte
type NmtProof = []byte
