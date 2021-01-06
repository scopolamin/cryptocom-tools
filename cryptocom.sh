#!/usr/bin/env bash

usage() {
   cat << EOT
Usage: $0 [option] command
Options:
   --action             action      status, redelegate
   --path               path        chain-maind configuration folder path
   --binary             path        chain-maind binary path
   --node               node        node address
   --chain-id           chain       chain id
   --keystore           name        keystore name
   --delegator-address  address     keystore name
   --passphrase         passphrase  passphrase used to unlock the keystore
   --help                           print this help section
EOT
}

while [ $# -gt 0 ]
do
  case $1 in
  --action) action="${2}" ; shift;;
  --path) chaind_path="${2%/}" ; shift;;
  --binary) chaind_binary_path="${2%/}" ; shift;;
  --node) node="${2}" ; shift;;
  --chain-id) chain_id="${2}" ; shift;;
  --keystore) keystore="${2}" ; shift;;
  --passphrase) passphrase="${2//$/\\$}" ; shift;;
  --delegator-address) delegator_address="${2}" ; shift;;
  -h|--help) usage; exit 1;;
  (--) shift; break;;
  (-*) usage; exit 1;;
  (*) break;;
  esac
  shift
done

set_default_values() {
  if [ -z "$action" ]; then
    action="status"
  fi

  if [ -z "$chaind_path" ]; then
    chaind_path="${HOME}/.chain-maind"
  fi

  if [ -z "$chaind_binary_path" ]; then
    chaind_binary_path="${HOME}/crypto_com/croeseid-2/chain-maind"
  fi

  if [ -z "$node" ]; then
    node="http://127.0.0.1:26657"
  fi

  if [ -z "$chain_id" ]; then
    chain_id="testnet-croeseid-2"
  fi

  if [ -z "$keystore" ]; then
    keystore="Default"
  fi

  if [ ! -z "$delegator_address" ]; then
    validator[initial_delegator_address]=${delegator_address}
  fi

  gas_price="0.1"

  declare -AG validator
}

set_validator_values() {
  validator[public_key_bech32]=$(${chaind_binary_path} tendermint show-validator)
  validator[public_key_base64]=$(cat ${chaind_path}/config/priv_validator_key.json | jq -r '.pub_key.value')
  get_validator_base64_address
  get_initial_delegator_address
  get_validator_data
}

initialize() {
  set_default_values
  set_validator_values
}

get_validator_base64_address() {
  page=1
  while true; do
    url="${node}/validators?per_page=100&page=${page}"
    error=$(curl -sSL ${url} | jq -r .error)
    if [[ $error == "null" ]]; then 
      local validator_base64_address=$(curl --max-time 10 -sSL ${url} | jq -r --arg PUBKEY "${validator[public_key_base64]}" '.result.validators[] | select(.pub_key.value == $PUBKEY) | .address')
      if [[ ! -z "${validator_base64_address}" ]]; then
        validator[address_base64]=${validator_base64_address}
        break;
      fi
    else 
      break;
    fi
    ((page=page+1))
  done
}

get_validator_data() {
  if [ ! -z "${validator[initial_delegator_address]}" ]; then
    page=1
    while true; do
      url="https://chain.crypto.com/explorer/api/v1/validators?pagination=offset&limit=100&order=power.desc&page=${page}"
      json=$(curl --max-time 10 -sSL ${url})
      total_page=$(echo "${json}" | jq '.pagination.total_page' | tr -d '"' | jq 'tonumber')

      if (( page > total_page )); then
        break;
      fi

      validator_data=$(echo "${json}" | jq -r --arg INITIAL_DELEGATOR_ADDRESS "${validator[initial_delegator_address]}" '.result[] | select(.initialDelegatorAddress == $INITIAL_DELEGATOR_ADDRESS)')
      if [[ ! -z "${validator_data}" ]]; then
        break;
      fi

      ((page=page+1))
    done

    if [ ! -z "$validator_data" ]; then
      parse_validator_data
    fi
  else
    echo "Initial delegator address hasn't been set - please supply it using --delegator-address or supply a passphrase using --passphrase to let the script retrieve it."
  fi
}

parse_validator_data() {
  validator[operator_address]=$(echo "${validator_data}" | jq ".operatorAddress" | tr -d '"')
  validator[consensus_node_address]=$(echo "${validator_data}" | jq ".consensusNodeAddress" | tr -d '"')
  validator[initial_delegator_address]=$(echo "${validator_data}" | jq ".initialDelegatorAddress" | tr -d '"')
  validator[status]=$(echo "${validator_data}" | jq ".status" | tr -d '"')
  validator[jailed]=$(echo "${validator_data}" | jq ".jailed" | tr -d '"')
  validator[joined_at_block_height]=$(echo "${validator_data}" | jq ".joinedAtBlockHeight" | tr -d '"' | jq 'tonumber')
  validator[power]=$(echo "${validator_data}" | jq ".power" | tr -d '"' | jq 'tonumber')
  validator[unbonding_height]=$(echo "${validator_data}" | jq ".unbondingHeight" | tr -d '"')
  validator[unbonding_completion_time]=$(echo "${validator_data}" | jq ".unbondingCompletionTime" | tr -d '"')
  validator[moniker]=$(echo "${validator_data}" | jq ".moniker" | tr -d '"')
  validator[identity]=$(echo "${validator_data}" | jq ".identity" | tr -d '"')
  validator[website]=$(echo "${validator_data}" | jq ".website" | tr -d '"')
  validator[security_contact]=$(echo "${validator_data}" | jq ".securityContact" | tr -d '"')
  validator[details]=$(echo "${validator_data}" | jq ".details" | tr -d '"')
  validator[commission_rate]=$(echo "${validator_data}" | jq ".commissionRate" | tr -d '"')
  validator[commission_max_rate]=$(echo "${validator_data}" | jq ".commissionMaxRate" | tr -d '"')
  validator[commission_max_change_rate]=$(echo "${validator_data}" | jq ".commissionMaxChangeRate" | tr -d '"')
  validator[min_self_delegation]=$(echo "${validator_data}" | jq ".minSelfDelegation" | tr -d '"' | jq 'tonumber')
  validator[power_percentage]=$(echo "${validator_data}" | jq ".powerPercentage" | tr -d '"')
  validator[cumulative_power_percentage]=$(echo "${validator_data}" | jq ".cumulativePowerPercentage" | tr -d '"')
}

get_initial_delegator_address() {
  if [ ! -z "$passphrase" ] && [ -z "${validator[initial_delegator_address]}" ]; then
    validator[initial_delegator_address]=$(printf "${passphrase//\\$/$}\n" | ${chaind_binary_path} keys list --output json | jq -r --arg NAME "${keystore}" '.[] | select(.name == $NAME) | .address')
  fi
}

get_wallet_balance() {
  balance=$(${chaind_binary_path} query bank balances ${validator[initial_delegator_address]} --chain-id ${chain_id} --node ${node} --output json --denom basetcro | jq '.amount | tonumber')
}

redelegate() {
  withdraw_rewards
  if [ "$success" = true ]; then
    delegate
  fi
}

withdraw_rewards() {
  if [ ! -z "${validator[operator_address]}" ]; then
    perform_transaction "tx distribution withdraw-rewards ${validator[operator_address]} --commission"
    if [ "$success" = true ]; then
      echo "Successfully performed withdraw-rewards - tx hash: ${tx_hash}"
    else
      echo "Failed to withdraw-rewards!"
    fi
  fi
}

delegate() {
  if [ ! -z "${validator[operator_address]}" ]; then
    get_wallet_balance
    echo "Current wallet balance is: ${balance} basetcro"
    delegatable="$(($balance-1000))"
    echo "Can delegate a total of ${delegatable} basetcro"

    if (( delegatable > 0 )); then
      perform_transaction "tx staking delegate ${validator[operator_address]} ${delegatable}basetcro"
      if [ "$success" = true ]; then
        echo "Successfully performed delegation to ${validator[operator_address]} - tx hash: ${tx_hash}"
      else
        echo "Failed to delegate to ${validator[operator_address]} !"
      fi
    else
      echo "We don't have sufficient basetcro to delegate"
    fi
  fi
}

perform_transaction() {
  local partial_cmd="$1"
  local cmd="${chaind_binary_path} ${partial_cmd} --from ${keystore} --chain-id ${chain_id} --node ${node} --gas-prices ${gas_price}basetcro --yes"
  local retries=3
  success=false

  while (( retries > 0 )); do
    tx_hash=$(printf "${passphrase//\\$/$}\n" | ${cmd} | jq '.txhash' | tr -d '"')
    if [ $? -eq 0 ] && [ ! -z "$tx_hash" ]; then
      success=true
      break;
    else
      ((retries=retries-1))
      echo "Failed to perform tx: '${partial_cmd}'. Waiting a couple of seconds and then retrying again. Retries remaining: ${retries}."
      sleep 10s
    fi
  done
}

status() {
  echo ""

  for key in "${!validator[@]}"; do
    value="${validator[$key]}"
    echo "Validator -> ${key}: ${value}"
  done

  echo ""
}

run() {
  initialize

  if [ "$action" = "status" ]; then
    status
  elif [ "$action" = "redelegate" ]; then
    redelegate
  fi
}

run
