#!/bin/bash
export LC_NUMERIC="en_US.UTF-8"
source $HOME/solana_bot/my_settings.sh

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
    local isAlarm=${2:-0}  # По умолчанию считаем, что сообщение не тревожное.
    local chatId="$CHAT_ID_LOG"  # По умолчанию отправляем в логирующий чат

    if [[ $isAlarm -ne 0 ]]; then
        chatId="$CHAT_ID_ALARM"  # Если передан флаг тревоги, отправляем в соответствующий чат
    fi

    # Делаем запрос к Telegram API для отправки сообщения.
    # Убедитесь, что переменная BOT_TOKEN содержит ваш токен бота.
    curl --silent --header 'Content-Type: application/json' 
         --request 'POST' 
         --data '{"chat_id":"'"$chatId"'","text":"'"$messageText"'"}' 
         "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" > /dev/null
}

SendTelegramAllertMessage() {
    sendTelegramMessage "$1" 1
}



echo -e
date
$SOLANA_PATH validators -u$CLUSTER --output json-compact >$HOME/solana_bot/delinq$CLUSTER.txt

for index in ${!PUB_KEY[*]}; do
    PING=$(ping -c 4 ${IP[$index]} | grep transmitted | awk '{print $4}')
    DELINQUEENT=$(cat $HOME/solana_bot/delinq$CLUSTER.txt | jq '.validators[] | select(.identityPubkey == "'"${PUB_KEY[$index]}"'" ) | .delinquent ')

    BALANCE=$(getBalance ${PUB_KEY[$index]} "$API_URL")

    if (($(bc <<<"$BALANCE < ${BALANCEWARN[$index]}"))); then
        local message="На ноде "${NODE_NAME[$index]}" баланс всего"  $BALANCE "надо пополнить" ${TEXT_NODE[$index]} "адрес" ${PUB_KEY[$index]}
        echo $message
        SendTelegramAllertMessage $message
    fi
    if [[ $PING == 0 ]] && [[ $DELINQUEENT == true ]]; then
        echo ${INET_ALARM[$index]} ${TEXT_ALARM[$index]}
        curl --header 'Content-Type: application/json' --request 'POST' --data '{"chat_id":"'"$CHAT_ID_ALARM"'","text":"'"${INET_ALARM[$index]}"' '"${TEXT_ALARM[$index]}"' '"${PUB_KEY[$index]}"'"}' "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
        echo -e "\n"
    elif [[ $PING == 0 ]]; then
        echo ${INET_ALARM[$index]}
        curl --header 'Content-Type: application/json' --request 'POST' --data '{"chat_id":"'"$CHAT_ID_ALARM"'","text":"'"${INET_ALARM[$index]}"' '"${PUB_KEY[$index]}"'"}' "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
        echo -e "\n"
    elif [[ $DELINQUEENT == true ]]; then
        echo ${TEXT_ALARM[$index]}
        curl --header 'Content-Type: application/json' --request 'POST' --data '{"chat_id":"'"$CHAT_ID_ALARM"'","text":"'"${TEXT_ALARM[$index]}"' '"${PUB_KEY[$index]}"'"}' "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
    else
        echo "Все ok" ${PUB_KEY[$index]}
    fi
done

if (($(echo "$(date +%M) < 5" | bc -l))); then # Первые 5 минут каждого часа

    mesto_top_temp=$($SOLANA_PATH validators -u$CLUSTER --sort=credits -r -n >$HOME/solana_bot/mesto_top$CLUSTER.txt)
    lider=$(cat $HOME/solana_bot/mesto_top$CLUSTER.txt | sed -n 2,1p | awk '{print $3}')
    lider2=$(cat $HOME/solana_bot/delinq$CLUSTER.txt | jq '.validators[] | select(.identityPubkey == "'"$lider"'") | .epochCredits ')
    Average_temp=$(cat $HOME/solana_bot/delinq$CLUSTER.txt | jq '.averageStakeWeightedSkipRate')
    Average=$(printf "%.2f" $Average_temp)
    if [[ -z "$Average" ]]; then
        Average=0
    fi

    RESPONSE_EPOCH=$($SOLANA_PATH epoch-info -u$CLUSTER >$HOME/solana_bot/temp$CLUSTER.txt)
    EPOCH=$(cat $HOME/solana_bot/temp$CLUSTER.txt | grep "Epoch:" | awk '{print $2}')
    EPOCH_PERCENT=$(printf "%.2f" $(cat $HOME/solana_bot/temp$CLUSTER.txt | grep "Epoch Completed Percent" | awk '{print $4}' | grep -oE "[0-9]*|[0-9]*.[0-9]*" | awk 'NR==1 {print; exit}'))"%"
    END_EPOCH=$(echo $(cat $HOME/solana_bot/temp$CLUSTER.txt | grep "Epoch Completed Time" | grep -o '(.*)' | sed "s/^(//" | awk '{$NF="";sub(/[ \t]+$/,"")}1'))

    for index in ${!PUB_KEY[*]}; do
        epochCredits=$(cat $HOME/solana_bot/delinq$CLUSTER.txt | jq '.validators[] | select(.identityPubkey == "'"${PUB_KEY[$index]}"'" ) | .epochCredits ')
        mesto_top=$(cat $HOME/solana_bot/mesto_top$CLUSTER.txt | grep ${PUB_KEY[$index]} | awk '{print $1}' | grep -oE "[0-9]*|[0-9]*.[0-9]")
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

        skip=$(bc <<<"scale=2; $skipped*100/$Done")
        if [[ -z "$skip" ]]; then
            skip=0
        fi

        if (($(bc <<<"$skip <= $Average + $skip_dop"))); then
            skip=🟢$skip
        else
            skip=🔴$skip
        fi

        BALANCE_TEMP=$(curl --silent -X POST $API_URL -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0", "id":1, "method":"getBalance", "params":["'${PUB_KEY[$index]}'"]}' | jq '.result.value')
        BALANCE=$(echo "scale=2; $BALANCE_TEMP/1000000000" | bc)
        simvol1=${BALANCE:0:1}
        if [[ $simvol1 = . ]]; then
            BALANCE="0$BALANCE"
        else
            BALANCE=$BALANCE
        fi

        VOTE_BALANCE_TEMP=$(curl --silent -X POST $API_URL -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0", "id":1, "method":"getBalance", "params":["'${VOTE[$index]}'"]}' | jq '.result.value')
        VOTE_BALANCE=$(echo "scale=2; $VOTE_BALANCE_TEMP/1000000000" | bc)
        simvol1=${VOTE_BALANCE:0:1}
        if [[ $simvol1 = . ]]; then
            VOTE_BALANCE="0$VOTE_BALANCE"
        else
            VOTE_BALANCE=$VOTE_BALANCE
        fi

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

        VER=$(cat $HOME/solana_bot/delinq$CLUSTER.txt | jq '.validators[] | select(.identityPubkey == "'"${PUB_KEY[$index]}"'" ) | .version ' | sed 's/\"//g')

        comission=$(bc <<<"scale=3; (($epochCredits*5) - ($sdelal_blokov*3750))/1000000")
        minus=${comission:0:1}
        if [[ $minus = - ]]; then
            comission=$(bc <<<"scale=3; $comission * -1")
            simvol1=${comission:0:1}
            if [[ $simvol1 = . ]]; then
                comission="earn 0$comission"
            else
                comission="earn $comission"
            fi
        fi

        if [[ $minus = . ]]; then
            comission=0$comission
        else
            comission=$comission
        fi

        PUB=$(echo ${PUB_KEY[$index]:0:10})
        info='"
<b>'"${TEXT_NODE[$index]}"'</b> '"[$PUB]"' ['"$VER"']<code>
'"All:"$All_block" Done:"$Done" skipped:"$skipped""'
'"skip:"$skip%" Average:"$Average%""'
сredits >['"$epochCredits"'] ['"$proc"'%]
mesto>['"$mesto_top"'] onboard > ['"$onboard"']
active_stk >>>['"$ACTIVE"']
activating >>>['"$ACTIVATING"']
deactivating >['"$DEACTIVATING"']
balance>['"$BALANCE"']  
vote_balance>>['"$VOTE_BALANCE"']
comission>['"$comission"' sol]</code>"'

        if [[ $onboard == null ]]; then
            info='"
<b>'"${TEXT_NODE[$index]}"'</b> '"[$PUB]"' ['"$VER"']<code>
'"All:"$All_block" Done:"$Done" skipped:"$skipped""'
'"skip:"$skip%" Average:"$Average%""'
сredits >['"$epochCredits"'] ['"$proc"'%]
mesto>['"$mesto_top"'] 
active_stk >>>['"$ACTIVE"']
activating >>>['"$ACTIVATING"']
deactivating >['"$DEACTIVATING"']
balance>['"$BALANCE"']  
vote_balance>>['"$VOTE_BALANCE"']
comission>['"$comission"' sol]</code>"'
        fi

        if [[ $CLUSTER == m ]]; then
            info='"
<b>'"${TEXT_NODE[$index]}"'</b> ['"$PUB"'] ['"$VER"']<code>
'"All:"$All_block" Done:"$Done" skipped:"$skipped""'
'"skip:"$skip%" Average:"$Average%""'
сredits >['"$epochCredits"'] ['"$proc"'%]
mesto>['"$mesto_top"'] 
active_stk >>>['"$ACTIVE"']
activating >>>['"$ACTIVATING"']
deactivating >['"$DEACTIVATING"']
balance>['"$BALANCE"']  
vote_balance>>['"$VOTE_BALANCE"']
comission>['"$comission"' sol]</code>"'
        fi
        echo "Нода в порядке" ${TEXT_NODE[$index]}
        curl --header 'Content-Type: application/json' --request 'POST' --data '{"chat_id":"'"$CHAT_ID_LOG"'",
"text":'"$info"',  "parse_mode": "html"}' "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
        echo -e "\n"
    done

    if (($(echo "$(date +%H) == $TIME_Info2" | bc -l))) && (($(echo "$(date +%M) < 5" | bc -l))); then
        let EPOCH=$EPOCH-1
        for index in ${!PUB_KEY[*]}; do

            info2=$(curl -s -X GET 'https://kyc-api.vercel.app/api/validators/details?pk='"${PUB_KEY[$index]}"'&epoch='"$EPOCH"'' | jq '.stats' >$HOME/solana_bot/info2$CLUSTER.txt)

            state_action=$(cat $HOME/solana_bot/info2$CLUSTER.txt | jq '.state_action' | sed 's/\"//g')
            asn=$(cat $HOME/solana_bot/info2$CLUSTER.txt | jq '.epoch_data_center.asn')
            location=$(cat $HOME/solana_bot/info2$CLUSTER.txt | jq '.epoch_data_center.location' | sed 's/\"//g')
            data_center_percent_temp=$(cat $HOME/solana_bot/info2$CLUSTER.txt | grep "data_center_stake_percent" | awk '{print $2}' | sed 's/\,//g')
            data_center_percent=$(printf "%.2f" $data_center_percent_temp)
            reported_metrics_summar=$(cat $HOME/solana_bot/info2$CLUSTER.txt | jq '.self_reported_metrics_summary.reason' | sed 's/\"//g')

            PUB=$(echo ${PUB_KEY[$index]:0:8})
            info2='"
<b>'"${TEXT_NODE2[$index]} epoch $EPOCH"'</b>['"$PUB"'] <code>
*'$state_action' 
*'"$asn"' '"$location"' '"$data_center_percent"'%
*'"$reported_metrics_summar"'</code>"'
            if [[ $reported_metrics_summar != null ]]; then
                curl --header 'Content-Type: application/json' --request 'POST' --data '{"chat_id":"'"$CHAT_ID_LOG"'",
"text":'"$info2"',  "parse_mode": "html"}' "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
                echo -e "\n"
            else
                echo "'"${TEXT_NODE2[$index]}"' Stake-o-matic еще не отработал. Информации нет"
                curl --header 'Content-Type: application/json' --request 'POST' --data '{"chat_id":"'"$CHAT_ID_LOG"'",
"text":"'"${TEXT_NODE2[$index]}"' Stake-o-matic еще не отработал. Информации нет",  "parse_mode": "html"}' "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
            fi
        done
    fi
    EPOCH=$(cat $HOME/solana_bot/temp$CLUSTER.txt | grep "Epoch:" | awk '{print $2}')
    echo "$TEXT_INFO_EPOCH"
    curl --header 'Content-Type: application/json' --request 'POST' --data '{"chat_id":"'"$CHAT_ID_LOG"'","text":"<b>'"$TEXT_INFO_EPOCH"'</b> <code>
['"$EPOCH"'] | ['"$EPOCH_PERCENT"'] 
End_Epoch '"$END_EPOCH"'</code>", "parse_mode": "html"}' "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
fi
