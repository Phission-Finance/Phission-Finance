#!/bin/bash

RPC_URL=""
ETHERSCAN_KEY=""

[ -n "$1" ] && RPC_URL="$1" || { echo "enter rpc url for forking"; exit 1; }
[ -n "$2" ] && ETHERSCAN_KEY="$2" || ETHERSCAN_KEY="_"

# random sender so token0 and token1 in uniswap can end up reversed
SENDER="0x$(openssl rand -hex 20)"

TEST="[1] (without rpc) before merge"

echo "testing: $TEST" && forge test --chain-id 1 --block-difficulty 1 --no-match-test "_pos|_pow" --no-match-contract "_fork" --sender $SENDER -vvv

TEST="[2] (without rpc) after merge on pos"

echo "testing: $TEST" && forge test --chain-id 1 --block-difficulty 18446744073709551615  --match-test "_pos" --no-match-contract "_fork" --sender $SENDER -vvv

TEST="[3] (without rpc) after merge on pow"

echo "testing: $TEST" && forge test --chain-id 1337 --block-difficulty 1  --match-test "_pow" --no-match-contract "_fork" --sender $SENDER -vvv

TEST="[4] before merge"

echo "testing: $TEST" && forge test --fork-url $RPC_URL  --etherscan-api-key $ETHERSCAN_KEY --chain-id 1 --no-match-test "_pos|_pow" --match-contract "_fork" --sender $SENDER -vvvvvv

TEST="[5] after merge on pos"

echo "testing: $TEST" && forge test --fork-url $RPC_URL  --etherscan-api-key $ETHERSCAN_KEY --chain-id 1 --block-difficulty 18446744073709551615  --match-test "_pos" --match-contract "_fork" --sender $SENDER -vvvvvv

TEST="[6] after merge on pow"

echo "testing: $TEST" && forge test --fork-url $RPC_URL  --etherscan-api-key $ETHERSCAN_KEY --chain-id 1337  --match-test "_pow" --match-contract "_fork" --sender $SENDER -vvvvvv
