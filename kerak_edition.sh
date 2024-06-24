#!/bin/bash
export LC_NUMERIC="en_US.UTF-8"
url="$HOME/solana_bot"
source "$url/my_settings.sh"
echo -e
date

get_balance() {
    local public_key=$1
    local api_url=${2:-"$API_URL"}
    local balance_temp
    local final_balance
    local retry_count=0
    local max_retries=3

    while [ $retry_count -lt $max_retries ]; do
        balance_temp=$(curl --silent -X POST "$api_url" -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0", "id":1, "method":"getBalance", "params":["'"$public_key"'"]}' | jq '.result.value')

        if [ -n "$balance_temp" ]; then
            break
        fi

        ((retry_count++))
        sleep 1
    done

    final_balance=$(echo "scale=2; $balance_temp/1000000000" | bc)

    if [[ $final_balance == .* ]]; then
        final_balance="0$final_balance"
    fi
    echo "$final_balance"
}

send_telegram_message() {
    local message_text=$1
    local is_alarm=${2:-0}
    local chat_id="$CHAT_ID_LOG"

    if [[ $is_alarm -ne 0 ]]; then
        chat_id="$CHAT_ID_ALARM"
    fi

    curl --silent --header 'Content-Type: application/json' \
        --request 'POST' \
        --data '{"chat_id":"'"$chat_id"'","text":"'"$message_text"'","parse_mode":"HTML"}' \
        "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" >/dev/null
}

send_telegram_allert_message() {
    send_telegram_message "$1" 1
}

halt_on_hangup() {
   ( sleep 90 && if ps -p $$ > /dev/null; then send_telegram "$ALERT_MESSAGE"; kill -SIGINT $$; fi ) &
    TIMER_PID=$!
    trap 'kill $TIMER_PID; exit' INT
}

halt_on_hangup

if [[ $CLUSTER == m ]]; then
    cluster_name="Mainnet"
else
    cluster_name="Testnet"
fi

"$SOLANA_PATH" validators -u "$CLUSTER" --output json-compact >"$url/delinq_$CLUSTER.txt"

check_ping_deliquent() {
    report="Общий отчет \n"
    for index in ${!PUB_KEY[*]}; do
        public_key=${PUB_KEY[$index]}
        warn=0
        ping_output=$(ping -c 4 "${IP[$index]}" | grep transmitted | awk '{print $4}')

        delinquent=$(cat "$url/delinq_$CLUSTER.txt" | jq ".validators[] | select(.identityPubkey == \"${public_key}\" ) | .delinquent ")
        message="${NODE_NAME[$index]}"

        if [[ $ping_output -eq 0 ]]; then
            message+="\n 🔴🔴🔴 Ping не проходит!!\n"
            warn=1
        fi

        if [[ $delinquent == true ]]; then
            message+="\n 🔴🔴🔴 Нода отмечена как неактивная (delinquent)!!\n"
            warn=1
        fi

        if [[ $warn -eq 1 ]]; then
            send_telegram_allert_message "${message}"
        else
            message="🟢 ${message} OK\n"
        fi
        report+=$message
    done
    echo -e "$report"
    send_telegram_message "$report"
}

generate_node_report() {
    warn=0
    additional_message=""
    epoch_percent_done=$(awk '/Epoch Completed Percent/ {print $4+0}' "$url/temp_$CLUSTER.txt" | xargs printf "%.2f%%")
    end_epoch=$(awk '/Epoch Completed Time/ {$1=$2=""; print $0}' "$url/temp_$CLUSTER.txt" | tr -d '()')

    epoch_credits=$(cat $url/delinq_$CLUSTER.txt | jq ".validators[] | select(.identityPubkey == \"$public_key\" ) | .epochCredits ")
    position_by_credits=$(cat $url/validtors_by_credits_$CLUSTER.txt | grep $public_key | awk '{print $1}' | grep -oE "[0-9]*|[0-9]*.[0-9]")
    credits_percent=$(bc <<<"scale=2; $epoch_credits*100/$lider2")

    all_block=$(curl --silent -X POST ${API_URL} -H 'Content-Type: application/json' -d '{ "jsonrpc":"2.0","id":1, "method":"getLeaderSchedule", "params": [ null, { "identity": "'${public_key}'" }] }' | jq '.result."'${public_key}'"' | wc -l)
    all_block=$(echo "${all_block} -2" | bc)
    if (($(bc <<<"$all_block < 0"))); then
        all_block=0
    fi
    blocks_production_json=$(curl --silent -X POST ${API_URL} -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":1, "method":"getBlockProduction", "params": [{ "identity": "'${public_key}'" } ]}')
    blocks_counter=$(echo ${blocks_production_json} | jq '.result.value.byIdentity."'${public_key}'"[0]')
    if (($(bc <<<"$blocks_counter == null"))); then
        blocks_counter=0
    fi
    blocks_success=$(echo ${blocks_production_json} | jq '.result.value.byIdentity."'${public_key}'"[1]')
    if [[ -z "$blocks_success" ]]; then
        blocks_success=0
    fi
    skipped=$(bc <<<"$blocks_counter - $blocks_success")
    if [[ $blocks_counter -eq 0 ]]; then
        skip_percent=0
    else
        skip_percent=$(bc <<<"scale=2; $skipped*100/$blocks_counter")
    fi

    if [[ -z "$skip_percent" ]]; then
        skip_percent=0
    fi

    if (($(bc <<<"$skip_percent <= $skip_average"))); then
        skip_percent="🟢$skip_percent"
    else
        skip_percent="🔴$skip_percent"
    fi
    balance=$(get_balance ${public_key} "$API_URL")
    if (($(bc <<<"$balance < ${BALANCEWARN[$index]}"))); then
        additional_message+="🔴🔴🔴Недостаточно средств. Необходимо пополнить\n"
        warn=1
    fi
    vote_balance=$(get_balance ${VOTE_KEY[$index]} "$API_URL")

    response_stakes=$($SOLANA_PATH stakes ${VOTE_KEY[$index]} -u$CLUSTER --output json-compact)
    active=$(echo "scale=2; $(echo $response_stakes | jq -c '.[] | .activeStake' | paste -sd+ | bc)/1000000000" | bc)
    activating=$(echo "scale=2; $(echo $response_stakes | jq -c '.[] | .activatingStake' | paste -sd+ | bc)/1000000000" | bc)
    if (($(echo "$activating > 0" | bc -l))); then
        activating="$activating🟢"
    fi
    deactivating=$(echo "scale=2; $(echo $response_stakes | jq -c '.[] | .deactivatingStake' | paste -sd+ | bc)/1000000000" | bc)
    if (($(echo "$deactivating > 0" | bc -l))); then
        deactivating="$deactivating⚠️"
    fi

    ver=$(cat $url/delinq_$CLUSTER.txt | jq '.validators[] | select(.identityPubkey == "'"${public_key}"'" ) | .version ' | sed 's/\"//g')
    if [[ $CLUSTER == t ]]; then
        onboard=$(curl -s -X GET 'https://kyc-api.vercel.app/api/validators/list?search_term='"${public_key}"'&limit=40&order_by=name&order=asc' | jq '.data[0].onboardingnumber')
        if [[ -n $onboard && $onboard != "null" ]]; then
            additional_message+="<b>Onboard nr:</b> ${onboard}\n"
        fi
    fi

    echo = "<b>${NODE_NAME[$index]} ${cluster_name} nr ${index}</b>. Version:<b>$ver</b>:
<code>${public_key}</code>
${additional_message}
<b>Blocks</b> All: $all_block Done: $blocks_counter Skipped: $skipped ($skip_percent%)
Average skip by cluster: $skip_average%
<b>Credits:</b> $epoch_credits ($credits_percent%) 
<b>Position:</b> $position_by_credits 
<b>Stake</b>: Current $active. Next: +$activating,  -$deactivating
<b>Balance:</b> Identity $balance. Vote: $vote_balance
---
Epoch: ${epoch} (${epoch_percent_done}).\n${end_epoch}
"

}

check_ping_deliquent

CURRENT_MIN=$(date +%M)
if ((10#$CURRENT_MIN < 2)); then

    $($SOLANA_PATH validators -u$CLUSTER --sort=credits -r -n >"$url/validtors_by_credits_$CLUSTER.txt")
    lider=$(cat $url/validtors_by_credits_$CLUSTER.txt | sed -n 2,1p | awk '{print $3}')
    lider2=$(cat $url/delinq_$CLUSTER.txt | jq '.validators[] | select(.identityPubkey == "'"$lider"'") | .epochCredits ')
    skip_average=$(jq '.averageStakeWeightedSkipRate' "$url/delinq_$CLUSTER.txt" | xargs printf "%.2f")
    skip_average=${skip_average:-0}

    $($SOLANA_PATH epoch-info -u$CLUSTER >"$url/temp_$CLUSTER.txt")
    epoch=$(awk '/Epoch:/ {print $2}' "$url/temp_$CLUSTER.txt")
    prew_epoch=$epoch-1

    for index in ${!PUB_KEY[*]}; do
        public_key=${PUB_KEY[$index]}
        echo "207 ${public_key}"
        node_report=$(generate_node_report)
        echo "${node_report}"

        // node_report=$(generate_node_report)
        echo 209
        echo "${node_report}"
        send_telegram_message "${node_report}" ${WARN}

        # Один раз  в сутки только проверяем Данные с SFDP за прошлую эпоху
        if [ "$1" -eq 1 ] || [ $(date +%H) -eq "$TIME_Info2" ]; then

            $(curl -s -X GET 'https://kyc-api.vercel.app/api/validators/details?pk='"${public_key}"'&epoch='"$prew_epoch"'' | jq '.stats' >$url/info2$CLUSTER.txt)
            echo 216
            state_action=$(cat $url/info2$CLUSTER.txt | jq '.state_action' | sed 's/\"//g')
            asn=$(cat $url/info2$CLUSTER.txt | jq '.epoch_data_center.asn')
            location=$(cat $url/info2$CLUSTER.txt | jq '.epoch_data_center.location' | sed 's/\"//g')
            data_center_percent_temp=$(cat $url/info2$CLUSTER.txt | grep "data_center_stake_percent" | awk '{print $2}' | sed 's/\,//g')
            data_center_percent=$(printf "%.2f" $data_center_percent_temp)
            reported_metrics_summar=$(cat $url/info2$CLUSTER.txt | jq '.self_reported_metrics_summary.reason' | sed 's/\"//g')
            echo 223
            info2='"
<b>'"${NODE_NAME[$index]} epoch $prew_epoch"'</b>['"$public_key"'] <code>
*'$state_action' 
*'"$asn"' '"$location"' '"$data_center_percent"'%
*'"$reported_metrics_summar"'</code>"'
            if [[ $reported_metrics_summar != null ]]; then
                sendTelegramMessage "$info2"
                echo -e "\n"
            else
                echo "'"${TEXT_NODE2[$index]}"' Stake-o-matic еще не отработал. Информации нет"
                # sendTelegramMessage "${TEXT_NODE2[$index]} Stake-o-matic еще не отработал. Информации нет"
            fi
        fi
    done
fi

kill $TIMER_PID
