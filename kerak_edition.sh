#!/bin/bash
export LC_NUMERIC="en_US.UTF-8"
URL=$HOME/solana_bot
source $URL/my_settings.sh
echo -e
date

getBalance() {
    local publicKey=$1
    local apiUrl=${2:-"$API_URL"}
    local balanceTemp
    local finalBalance
    local retryCount=0

    # Пытаемся получить баланс. Если баланс нулевой - повторяем еще раз.
    while true; do
        balanceTemp=$(curl --silent -X POST "$apiUrl" -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0", "id":1, "method":"getBalance", "params":["'"$publicKey"'"]}' | jq '.result.value')

        # Если значение баланса более 0 или превысили количество попыток, выходим из цикла.
        if [[ $balanceTemp -gt 0 || $retryCount -ge 1 ]]; then
            break
        fi
        ((retryCount++))
        sleep 1
    done

    # Округляем баланс до двух знаков после запятой и преобразовываем в SOL (деление на 10^9)
    finalBalance=$(echo "scale=2; $balanceTemp/1000000000" | bc)

    # Добавляем ведущий ноль, если результат начинается с точки.
    if [[ $finalBalance == .* ]]; then
        finalBalance="0$finalBalance"
    fi
    echo "$finalBalance"
}

sendTelegramMessage() {
    local messageText=$1
    local isAlarm=${2:-0}       # По умолчанию считаем, что сообщение не тревожное.
    local chatId="$CHAT_ID_LOG" # По умолчанию отправляем в логирующий чат

    if [[ $isAlarm -ne 0 ]]; then
        chatId="$CHAT_ID_ALARM" # Если передан флаг тревоги, отправляем в соответствующий чат
    fi

    # Делаем запрос к Telegram API для отправки сообщения.
    # Убедитесь, что переменная BOT_TOKEN содержит ваш токен бота.
    curl --silent --header 'Content-Type: application/json' \
        --request 'POST' \
        --data '{"chat_id":"'"$chatId"'","text":"'"$messageText"'","parse_mode":"HTML"}' \
        "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" >/dev/null
}

SendTelegramAllertMessage() {
    sendTelegramMessage "$1" 1
}

HaltOnHangUP() {
    # Фоновый процесс, проверяет, завершился ли основной процесс  вовремя
    (sleep 90 && if ps -p $$ >/dev/null; then
        SendTelegramAllertMessage "Скрипт мониторинга подвис. Останавливаю принудительно"
        kill -SIGINT $$
    fi) &
    TIMER_PID=$!
    trap 'kill $TIMER_PID; exit' INT

}

HaltOnHangUP

if [[ $CLUSTER == m ]]; then
    CLUSTER_NAME="Mainnet"

else
    CLUSTER_NAME="Testnet"
fi

$SOLANA_PATH validators -u$CLUSTER --output json-compact >$URL/delinq$CLUSTER.txt

checkPingDeliquent() {
    REPORT="Общий отчет \n"
    for index in ${!PUB_KEY[*]}; do
        WARN=0
        PING=$(ping -c 4 ${IP[$index]} | grep transmitted | awk '{print $4}')
        DELINQUENT=$(cat $URL/delinq$CLUSTER.txt | jq '.validators[] | select(.identityPubkey == "'"${PUB_KEY[$index]}"'" ) | .delinquent ')
        MESSAGE="${NODE_NAME[$index]}"

        if [[ $PING -eq 0 ]]; then
            MESSAGE+="\n 🔴🔴🔴 Ping не проходит!!"
            WARN=1
        fi

        if [[ $DELINQUENT == true ]]; then
            MESSAGE+="\n 🔴🔴🔴 Нода отмечена как неактивная (delinquent)!!"
            WARN=1
        fi

        if [[ WARN -eq 1 ]]; then
            SendTelegramAllertMessage "${MESSAGE}"
        else
            MESSAGE="🟢 ${MESSAGE} OK\n"
        fi
        REPORT+=$MESSAGE
    done
    # Отправка сообщения
    echo -e "$REPORT"
    sendTelegramMessage "$REPORT"
}

generate_node_report() {
    WARN=0
    ADDITIONAL_MESSAGE=""

    EPOCH_PERCENT_DONE=$(awk '/Epoch Completed Percent/ {print $4+0}' "$URL/temp$CLUSTER.txt" | xargs printf "%.2f%%")
    END_EPOCH=$(awk '/Epoch Completed Time/ {$1=$2=""; print $0}' "$URL/temp$CLUSTER.txt" | tr -d '()')
    EPOCH_MESSAGE="Epoch:${EPOCH} (${EPOCH_PERCENT_DONE}).\n${END_EPOCH}"

    epochCredits=$(cat $URL/delinq$CLUSTER.txt | jq '.validators[] | select(.identityPubkey == "'"${PUBLIC_KEY}"'" ) | .epochCredits ')
    mesto_top=$(cat $URL/mesto_top$CLUSTER.txt | grep ${PUBLIC_KEY} | awk '{print $1}' | grep -oE "[0-9]*|[0-9]*.[0-9]")
    proc=$(bc <<<"scale=2; $epochCredits*100/$lider2")
    #dali blokov
    All_block=$(curl --silent -X POST ${API_URL} -H 'Content-Type: application/json' -d '{ "jsonrpc":"2.0","id":1, "method":"getLeaderSchedule", "params": [ null, { "identity": "'${PUB_KEY[$index]}'" }] }' | jq '.result."'${PUB_KEY[$index]}'"' | wc -l)
    All_block=$(echo "${All_block} -2" | bc)
    if (($(bc <<<"$All_block < 0"))); then
        All_block=0
    fi
    #done,sdelal,skipnul, skyp%
    BLOCKS_PRODUCTION_JSON=$(curl --silent -X POST ${API_URL} -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":1, "method":"getBlockProduction", "params": [{ "identity": "'${PUB_KEY[$index]}'" } ]}')
    Done=$(echo ${BLOCKS_PRODUCTION_JSON} | jq '.result.value.byIdentity."'${PUBLIC_KEY}'"[0]')
    if (($(bc <<<"$Done == null"))); then
        Done=0
    fi
    sdelal_blokov=$(echo ${BLOCKS_PRODUCTION_JSON} | jq '.result.value.byIdentity."'${PUBLIC_KEY}'"[1]')
    if [[ -z "$sdelal_blokov" ]]; then
        sdelal_blokov=0
    fi
    skipped=$(bc <<<"$Done - $sdelal_blokov")

    if [[ $Done -eq 0 ]]; then
        skip=0
    else
        skip=$(bc <<<"scale=2; $skipped*100/$Done")
    fi

    if [[ -z "$skip" ]]; then
        skip=0
    fi

    if (($(bc <<<"$skip <= $Average + $skip_dop"))); then
        skip=🟢$skip
    else
        skip=🔴$skip
    fi

    BALANCE=$(getBalance ${PUBLIC_KEY} "$API_URL")

    if (($(bc <<<"$BALANCE < ${BALANCEWARN[$index]}"))); then
        ADDITIONAL_MESSAGE+="🔴🔴🔴Недостаточно средств. Необходимо пополнить\n"
        WARN=1
    fi

    VOTE_BALANCE=$(getBalance ${VOTE[$index]} "$API_URL")

    RESPONSE_STAKES=$($SOLANA_PATH stakes ${VOTE[$index]} -u$CLUSTER --output json-compact)
    ACTIVE=$(echo "scale=2; $(echo $RESPONSE_STAKES | jq -c '.[] | .activeStake' | paste -sd+ | bc)/1000000000" | bc)
    ACTIVATING=$(echo "scale=2; $(echo $RESPONSE_STAKES | jq -c '.[] | .activatingStake' | paste -sd+ | bc)/1000000000" | bc)
    if (($(echo "$ACTIVATING > 0" | bc -l))); then
        ACTIVATING=$ACTIVATING🟢
    fi
    DEACTIVATING=$(echo "scale=2; $(echo $RESPONSE_STAKES | jq -c '.[] | .deactivatingStake' | paste -sd+ | bc)/1000000000" | bc)
    if (($(echo "$DEACTIVATING > 0" | bc -l))); then
        DEACTIVATING=$DEACTIVATING⚠️
    fi

    VER=$(cat $URL/delinq$CLUSTER.txt | jq '.validators[] | select(.identityPubkey == "'"${PUBLIC_KEY}"'" ) | .version ' | sed 's/\"//g')

    if [[ $CLUSTER == t ]]; then
        onboard=$(curl -s -X GET 'https://kyc-api.vercel.app/api/validators/list?search_term='"${PUBLIC_KEY}"'&limit=40&order_by=name&order=asc' | jq '.data[0].onboardingnumber')
        if [[ -n $onboard && $onboard != "null" ]]; then
        ADDITIONAL_MESSAGE+="<b>Onboard nr :</b> ${onboard}\n"
        fi
    fi

    echo "<b>${NODE_NAME[$index]} ${CLUSTER_NAME} nr ${index}</b>. Version:<b>$VER</b>:
<code>${PUBLIC_KEY}</code>
${ADDITIONAL_MESSAGE}

<b>Blocks</b> All: $All_block Done: $Done Skipped: $skipped
<b>Skip:</b> $skip% <b>Average:</b> $Average%
<b>Credits:</b> $epochCredits ($proc%) <b>Position:</b> $mesto_top 
<b>Stake</b> Current: $ACTIVE. Next Epoch Cahnge: +$ACTIVATING,  -$DEACTIVATING
<b>Balance:</b> Identity $BALANCE. Vote: $VOTE_BALANCE
---
${EPOCH_MESSAGE}
"
}

checkPingDeliquent

CURRENT_MIN=$(date +%M)
if ((10#$CURRENT_MIN < 2)); then

    mesto_top_temp=$($SOLANA_PATH validators -u$CLUSTER --sort=credits -r -n >"$URL/mesto_top$CLUSTER.txt")
    lider=$(cat $URL/mesto_top$CLUSTER.txt | sed -n 2,1p | awk '{print $3}')
    lider2=$(cat $URL/delinq$CLUSTER.txt | jq '.validators[] | select(.identityPubkey == "'"$lider"'") | .epochCredits ')
    Average=$(jq '.averageStakeWeightedSkipRate' "$URL/delinq$CLUSTER.txt" | xargs printf "%.2f")
    Average=${Average:-0}

    $($SOLANA_PATH epoch-info -u$CLUSTER >"$URL/temp$CLUSTER.txt")
    EPOCH=$(awk '/Epoch:/ {print $2}' "$URL/temp$CLUSTER.txt")
    PREW_EPOCH=$EPOCH-1

    for index in ${!PUB_KEY[*]}; do
        PUBLIC_KEY=${PUB_KEY[$index]}
        node_report=$(generate_node_report)

        echo "${node_report}"
        sendTelegramMessage "${node_report}" ${WARN}

        # Один раз  в сутки только проверяем Данные с SFDP за прошлую эпоху
        if (($(echo "$(date +%H) == $TIME_Info2" | bc -l))); then

            $(curl -s -X GET 'https://kyc-api.vercel.app/api/validators/details?pk='"${PUBLIC_KEY}"'&epoch='"$PREW_EPOCH"'' | jq '.stats' >$URL/info2$CLUSTER.txt)

            state_action=$(cat $URL/info2$CLUSTER.txt | jq '.state_action' | sed 's/\"//g')
            asn=$(cat $URL/info2$CLUSTER.txt | jq '.epoch_data_center.asn')
            location=$(cat $URL/info2$CLUSTER.txt | jq '.epoch_data_center.location' | sed 's/\"//g')
            data_center_percent_temp=$(cat $URL/info2$CLUSTER.txt | grep "data_center_stake_percent" | awk '{print $2}' | sed 's/\,//g')
            data_center_percent=$(printf "%.2f" $data_center_percent_temp)
            reported_metrics_summar=$(cat $URL/info2$CLUSTER.txt | jq '.self_reported_metrics_summary.reason' | sed 's/\"//g')

            info2='"
<b>'"${NODE_NAME[$index]} epoch $PREW_EPOCH"'</b>['"$PUBLIC_KEY"'] <code>
*'$state_action' 
*'"$asn"' '"$location"' '"$data_center_percent"'%
*'"$reported_metrics_summar"'</code>"'
            if [[ $reported_metrics_summar != null ]]; then
                sendTelegramMessage "$info2"
                echo -e "\n"
            else
                echo "'"${TEXT_NODE2[$index]}"' Stake-o-matic еще не отработал. Информации нет"
                // sendTelegramMessage "${TEXT_NODE2[$index]} Stake-o-matic еще не отработал. Информации нет"
            fi
        fi
    done
fi

kill $TIMER_PID
