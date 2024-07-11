// (c) 2023, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

package utils

import (
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io/fs"
	"log"
	"math/big"
	"os"

	"github.com/ava-labs/subnet-evm/core/types"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/rlp"
	"github.com/pkg/errors"
)

const (
	// Roughly 3,010,000 gas needed to deploy contract. Padded to account for possible additions
	defaultContractCreationGasLimit = uint64(4000000)

	// R and S values to use in a keyless transaction signature.
	// The values do not technically need to be the same when using Nick's method, but the AvalancheGo
	// APIs by default only allow legacy transactions to be broadcast if they have the same R and S values,
	// which is used as a heuristic to identify (and allow) Nick's method transactions.
	rsValueHex                       = "3333333333333333333333333333333333333333333333333333333333333333"
	contractCreationTxFileName       = "UniversalTeleporterDeployerTransaction.txt"
	contractCreationAddrFileName     = "UniversalTeleporterDeployerAddress.txt"
	universalContractAddressFileName = "UniversalTeleporterMessengerContractAddress.txt"
)

var (
	vValue = big.NewInt(
		27,
	) // Must be less than 35 to be considered non-EIP155
	defaultContractCreationGasPrice = big.NewInt(2500e9) // 2500 nAVAX/gas
)

type byteCodeObj struct {
	Object string `json:"object"`
}

type byteCodeFile struct {
	ByteCode byteCodeObj `json:"bytecode"`
}

func DeriveEVMContractAddress(sender common.Address, nonce uint64) (common.Address, error) {
	type AddressNonce struct {
		Address common.Address
		Nonce   uint64
	}
	addressNonce := AddressNonce{sender, nonce}
	rlpEncoded, err := rlp.EncodeToBytes(addressNonce)
	if err != nil {
		return common.Address{}, errors.Wrap(err, "Failed to RLP encode address and nonce value.")
	}
	hash := crypto.Keccak256Hash(rlpEncoded)
	return common.HexToAddress(fmt.Sprintf("0x%x", hash.Bytes()[12:])), nil
}

func ExtractByteCode(byteCodeFileName string) ([]byte, error) {
	log.Println("Using bytecode file at", byteCodeFileName)
	byteCodeFileContents, err := os.ReadFile(byteCodeFileName)
	if err != nil {
		return nil, errors.Wrap(err, "Failed to read bytecode file contents")
	}
	var byteCodeJSON byteCodeFile
	err = json.Unmarshal(byteCodeFileContents, &byteCodeJSON)
	if err != nil {
		return nil, errors.Wrap(err, "Failed to unmarshal bytecode file contents as JSON")
	}
	byteCodeString := byteCodeJSON.ByteCode.Object
	if len(byteCodeString) < 2 {
		return nil, errors.New("Invalid byte code length.")
	}
	// Strip off leading 0x if present
	if byteCodeString[:2] == "0x" || byteCodeString[:2] == "0X" {
		byteCodeString = byteCodeString[2:]
	}
	byteCode, err := hex.DecodeString(byteCodeString)
	if err != nil {
		return nil, errors.Wrap(err, "Failed to decode bytecode string as hexadecimal.")
	}
	return byteCode, nil
}

// Constructs a keyless transaction using Nick's method
// Optionally writes the transaction, deployer address, and contract address to file
// Returns the transaction bytes, deployer address, and contract address
func ConstructKeylessTransaction(
	byteCodeFileName string,
	writeFile bool,
	contractCreationGasPrice *big.Int,
) ([]byte, common.Address, common.Address, error) {
	// Convert the R and S values (which must be the same) from hex.
	rsValue, ok := new(big.Int).SetString(rsValueHex, 16)
	if !ok {
		return nil, common.Address{}, common.Address{}, errors.New(
			"Failed to convert R and S value to big.Int.",
		)
	}

	byteCode, err := ExtractByteCode(byteCodeFileName)
	if err != nil {
		return nil, common.Address{}, common.Address{}, err
	}

	// Construct the legacy transaction with pre-determined signature values.
	contractCreationTx := types.NewTx(&types.LegacyTx{
		Nonce:    0,
		Gas:      defaultContractCreationGasLimit,
		GasPrice: contractCreationGasPrice,
		To:       nil, // Contract creation transaction
		Value:    big.NewInt(0),
		Data:     byteCode,
		V:        vValue,
		R:        rsValue,
		S:        rsValue,
	})

	// Recover the "sender" address of the transaction.
	senderAddress, err := types.HomesteadSigner{}.Sender(contractCreationTx)
	if err != nil {
		return nil, common.Address{}, common.Address{}, errors.Wrap(
			err,
			"Failed to recover the sender address of transaction",
		)
	}

	// Serialize the raw transaction and sender address.
	contractCreationTxBytes, err := contractCreationTx.MarshalBinary()
	if err != nil {
		return nil, common.Address{}, common.Address{}, errors.Wrap(
			err,
			"Failed to serialize raw transaction",
		)
	}
	contractCreationTxString := "0x" + hex.EncodeToString(contractCreationTxBytes)
	senderAddressString := senderAddress.Hex() // "0x" prepended by Hex() already.

	// Derive the resulting contract address given that it will be deployed from the sender address using the nonce of 0.
	contractAddress, err := DeriveEVMContractAddress(senderAddress, 0)
	if err != nil {
		return nil, common.Address{}, common.Address{}, errors.Wrap(
			err,
			"Failed to derive contract address",
		)
	}
	contractAddressString := contractAddress.Hex() // "0x" prepended by Hex() already.

	log.Println("Raw Teleporter Contract Creation Transaction:")
	log.Println(contractCreationTxString)
	log.Println("Teleporter Contract Keyless Deployer Address: ", senderAddressString)
	log.Println("Teleporter Messenger Universal Contract Address: ", contractAddressString)

	if writeFile {
		err = os.WriteFile(
			contractCreationTxFileName,
			[]byte(contractCreationTxString),
			fs.ModePerm,
		)
		if err != nil {
			return nil, common.Address{}, common.Address{}, errors.Wrap(
				err,
				"Failed to write to contract creation tx file",
			)
		}

		err = os.WriteFile(contractCreationAddrFileName, []byte(senderAddressString), fs.ModePerm)
		if err != nil {
			return nil, common.Address{}, common.Address{}, errors.Wrap(
				err,
				"Failed to write to deployer address file",
			)
		}

		err = os.WriteFile(
			universalContractAddressFileName,
			[]byte(contractAddressString),
			fs.ModePerm,
		)
		if err != nil {
			return nil, common.Address{}, common.Address{}, errors.Wrap(
				err,
				"Failed to write to contract address",
			)
		}
	}
	return contractCreationTxBytes, senderAddress, contractAddress, nil
}

func GetDefaultContractCreationGasPrice() *big.Int {
	gasPrice := big.NewInt(0)
	gasPrice.Set(defaultContractCreationGasPrice)
	return gasPrice
}
