package espresso

import (
	"encoding/json"
	"fmt"
	"math/big"
)

type Header struct {
	Timestamp        uint64      `json:"timestamp"`
	L1Block          L1BlockInfo `json:"l1_block"`
	TransactionsRoot NmtRoot     `json:"transactions_root"`
}

func (self *Header) Commit() Commitment {
	return NewRawCommitmentBuilder("BLOCK").
		Uint64Field("timestamp", self.Timestamp).
		Field("l1_block", self.L1Block.Commit()).
		Field("transactions_root", self.TransactionsRoot.Commit()).
		Finalize()

}

type L1BlockInfo struct {
	Number    uint64 `json:"number"`
	Timestamp U256   `json:"timestamp"`
}

func (self *L1BlockInfo) Commit() Commitment {
	return NewRawCommitmentBuilder("L1BLOCK").
		Uint64Field("number", self.Number).
		Uint256Field("timestamp", &self.Timestamp).
		Finalize()
}

type NmtRoot struct {
	Root Bytes `json:"root"`
}

func (self *NmtRoot) Commit() Commitment {
	return NewRawCommitmentBuilder("NMTROOT").
		VarSizeField("root", self.Root).
		Finalize()
}

type BatchMerkleProof = Bytes
type NmtProof = Bytes

// A bytes type which serializes to JSON as an array, rather than a base64 string. This ensures
// compatibility with the Espresso APIs.
type Bytes []byte

func (b Bytes) MarshalJSON() ([]byte, error) {
	// Convert to `int` array, which serializes the way we want.
	ints := make([]int, len(b))
	for i := range b {
		ints[i] = int(b[i])
	}

	return json.Marshal(ints)
}

func (b *Bytes) UnmarshalJSON(in []byte) error {
	// Parse as `int` array, which deserializes the way we want.
	var ints []int
	if err := json.Unmarshal(in, &ints); err != nil {
		return err
	}

	// Convert back to `byte` array.
	*b = make([]byte, len(ints))
	for i := range ints {
		if ints[i] < 0 || 255 < ints[i] {
			return fmt.Errorf("byte out of range: %d", ints[i])
		}
		(*b)[i] = byte(ints[i])
	}

	return nil
}

// A BigInt type which serializes to JSON a a hex string. This ensures compatibility with the
// Espresso APIs.
type U256 struct {
	big.Int
}

func NewU256() *U256 {
	return new(U256)
}

func (i *U256) SetUint64(n uint64) *U256 {
	i.Int.SetUint64(n)
	return i
}

func (i U256) MarshalJSON() ([]byte, error) {
	return json.Marshal(fmt.Sprintf("0x%s", i.Text(16)))
}

func (i *U256) UnmarshalJSON(in []byte) error {
	var s string
	if err := json.Unmarshal(in, &s); err != nil {
		return err
	}
	if _, err := fmt.Sscanf(s, "0x%x", &i.Int); err != nil {
		return err
	}
	return nil
}
