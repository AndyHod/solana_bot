#!/bin/bash
export LC_NUMERIC="en_US.UTF-8"
URL=$HOME/solana_bot
source $URL/my_settings.sh
declare -a BALANCE_BY_INDEX

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

echo -e
date
$SOLANA_PATH validators -u$CLUSTER --output json-compact >$URL/delinq$CLUSTER.txt

checkBalancePingDeliquent() {
    MESSAGE=""
    for index in ${!PUB_KEY[*]}; do
        PING=$(ping -c 4 ${IP[$index]} | grep transmitted | awk '{print $4}')
        DELINQUENT=$(cat $URL/delinq$CLUSTER.txt | jq '.validators[] | select(.identityPubkey == "'"${PUB_KEY[$index]}"'" ) | .delinquent ')
        BALANCE=$(getBalance ${PUB_KEY[$index]} "$API_URL")
        BALANCE_BY_INDEX[$index]=$BALANCE

        MESSAGE+="Отчёт по ноде ${NODE_NAME[$index]}, баланс: ${BALANCE},"

        if (($(bc <<<"$BALANCE < ${BALANCEWARN[$index]}"))); then
            MESSAGE+="Недостаточно средств. Необходимо пополнить \n${PUB_KEY[$index]}\n"
            WARN=1
        fi

        if [[ $PING -eq 0 ]]; then
            MESSAGE+=" Ping не проходит!! "
            WARN=1
        fi

        if [[ $DELINQUENT == true ]]; then
            MESSAGE+=" Нода отмечена как неактивная (delinquent). \n"
            WARN=1
        fi

        if [[ $PING -ne 0 && $DELINQUENT != true && $(bc <<<"$BALANCE >= ${BALANCEWARN[$index]}") -eq 1 ]]; then
            MESSAGE+="Всё в порядке"
        fi
    done
    # Отправка сообщения
    echo -e "$MESSAGE \n\n"
    sendTelegramMessage "$MESSAGE" "$WARN"
}

generate_info() {
    local onboard_part=""
    if [[ -n $onboard && $onboard != "null" ]]; then
        onboard_part="<b>Onboard:</b> $onboard"
    fi

    local cluster_part=""
    if [[ $CLUSTER == m ]]; then
        cluster_name="Mainnet"
        cluster_part="MainNet <b>$PUB</b> <b>$VER</b>"
    else
        cluster_name="Testnet"
        cluster_part="<b>$PUB</b> $VER"
    fi

    echo "<b>${NODE_NAME[$index]} ${cluster_name} nr ${index}</b>:
${PUB_KEY[$index]}
<code>
<b>Blocks</b> All: $All_block Done: $Done Skipped: $skipped
<b>Skip:</b> $skip% <b>Average:</b> $Average%
<b>Credits:</b> $epochCredits ($proc%)
<b>Position:</b> $mesto_top $onboard_part
<b>Stake</b> Active: $ACTIVE
Activating: $ACTIVATING
Deactivating: $DEACTIVATING
<b>Balance:</b> $BALANCE
<b>Vote Balance:</b> $VOTE_BALANCE
</code>"
}

checkBalancePingDeliquent

CURRENT_MIN=$(date +%M)
if ((10#$CURRENT_MIN < 5)); then

    mesto_top_temp=$($SOLANA_PATH validators -u$CLUSTER --sort=credits -r -n >"$URL/mesto_top$CLUSTER.txt")
    lider=$(cat $URL/mesto_top$CLUSTER.txt | sed -n 2,1p | awk '{print $3}')
    lider2=$(cat $URL/delinq$CLUSTER.txt | jq '.validators[] | select(.identityPubkey == "'"$lider"'") | .epochCredits ')
    Average=$(jq '.averageStakeWeightedSkipRate' "$URL/delinq$CLUSTER.txt" | xargs printf "%.2f")
    Average=${Average:-0}

    RESPONSE_EPOCH=$($SOLANA_PATH epoch-info -u$CLUSTER >"$URL/temp$CLUSTER.txt")
    EPOCH=$(awk '/Epoch:/ {print $2}' "$URL/temp$CLUSTER.txt")
    EPOCH_PERCENT=$(awk '/Epoch Completed Percent/ {print $4+0}' "$URL/temp$CLUSTER.txt" | xargs printf "%.2f%%")
    END_EPOCH=$(awk '/Epoch Completed Time/ {$1=$2=""; print $0}' "$URL/temp$CLUSTER.txt" | tr -d '()')
    echo 140
    for index in ${!PUB_KEY[*]}; do
        epochCredits=$(cat $URL/delinq$CLUSTER.txt | jq '.validators[] | select(.identityPubkey == "'"${PUB_KEY[$index]}"'" ) | .epochCredits ')
        mesto_top=$(cat $URL/mesto_top$CLUSTER.txt | grep ${PUB_KEY[$index]} | awk '{print $1}' | grep -oE "[0-9]*|[0-9]*.[0-9]")
        proc=$(bc <<<"scale=2; $epochCredits*100/$lider2")
        onboard=$(curl -s -X GET 'https://kyc-api.vercel.app/api/validators/list?search_term='"${PUB_KEY[$index]}"'&limit=40&order_by=name&order=asc' | jq '.data[0].onboardingnumber')
        #dali blokov
        All_block=$(curl --silent -X POST ${API_URL} -H 'Content-Type: application/json' -d '{ "jsonrpc":"2.0","id":1, "method":"getLeaderSchedule", "params": [ null, { "identity": "'${PUB_KEY[$index]}'" }] }' | jq '.result."'${PUB_KEY[$index]}'"' | wc -l)
        All_block=$(echo "${All_block} -2" | bc)
        if (($(bc <<<"$All_block < 0"))); then
            All_block=0
        fi
        #done,sdelal,skipnul, skyp%
        BLOCKS_PRODUCTION_JSON=$(curl --silent -X POST ${API_URL} -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":1, "method":"getBlockProduction", "params": [{ "identity": "'${PUB_KEY[$index]}'" } ]}')
        Done=$(echo ${BLOCKS_PRODUCTION_JSON} | jq '.result.value.byIdentity."'${PUB_KEY[$index]}'"[0]')
        if (($(bc <<<"$Done == null"))); then
            Done=0
        fi
        sdelal_blokov=$(echo ${BLOCKS_PRODUCTION_JSON} | jq '.result.value.byIdentity."'${PUB_KEY[$index]}'"[1]')
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
        BALANCE=${BALANCE_BY_INDEX[$index]}

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

        VER=$(cat $URL/delinq$CLUSTER.txt | jq '.validators[] | select(.identityPubkey == "'"${PUB_KEY[$index]}"'" ) | .version ' | sed 's/\"//g')

        PUB=$(echo ${PUB_KEY[$index]:0:10})
        info=$(generate_info)
        echo "Нода в порядке ${info} "
        sendTelegramMessage "$info"
    done

    if (($(echo "$(date +%H) == $TIME_Info2" | bc -l))) && (($(echo "$(date +%M) < 5" | bc -l))); then
        let EPOCH=$EPOCH-1

        for index in ${!PUB_KEY[*]}; do

            info2=$(curl -s -X GET 'https://kyc-api.vercel.app/api/validators/details?pk='"${PUB_KEY[$index]}"'&epoch='"$EPOCH"'' | jq '.stats' >$URL/info2$CLUSTER.txt)

            state_action=$(cat $URL/info2$CLUSTER.txt | jq '.state_action' | sed 's/\"//g')
            asn=$(cat $URL/info2$CLUSTER.txt | jq '.epoch_data_center.asn')
            location=$(cat $URL/info2$CLUSTER.txt | jq '.epoch_data_center.location' | sed 's/\"//g')
            data_center_percent_temp=$(cat $URL/info2$CLUSTER.txt | grep "data_center_stake_percent" | awk '{print $2}' | sed 's/\,//g')
            data_center_percent=$(printf "%.2f" $data_center_percent_temp)
            reported_metrics_summar=$(cat $URL/info2$CLUSTER.txt | jq '.self_reported_metrics_summary.reason' | sed 's/\"//g')

            PUB=$(echo ${PUB_KEY[$index]:0:8})
            info2='"
<b>'"${TEXT_NODE2[$index]} epoch $EPOCH"'</b>['"$PUB"'] <code>
*'$state_action' 
*'"$asn"' '"$location"' '"$data_center_percent"'%
*'"$reported_metrics_summar"'</code>"'
            if [[ $reported_metrics_summar != null ]]; then
                sendTelegramMessage "$info2"
                echo -e "\n"
            else
                echo "'"${TEXT_NODE2[$index]}"' Stake-o-matic еще не отработал. Информации нет"
                sendTelegramMessage "${TEXT_NODE2[$index]} Stake-o-matic еще не отработал. Информации нет"
            fi
        done
    fi
    EPOCH=$(cat $URL/temp$CLUSTER.txt | grep "Epoch:" | awk '{print $2}')
    echo "$TEXT_INFO_EPOCH"

fi
