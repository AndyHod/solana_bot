#!/bin/bash
export LC_NUMERIC="en_US.UTF-8"
SOLANA_PATH="$HOME/.local/share/solana/install/active_release/bin/solana" #Обрати вниманеи что путь со словом "solana" его не удалять!!!
#Cluster: m-mainnet-beta and t-testnet
CLUSTER=t
#если хочешь 1 ноду то в скобках указывается только один pub,vote,ip,TEXT и т.д. Добавить можно сколько угодно нод, но каждый новый параметр через пробел!  
PUB_KEY=(pub1 pub2) #Identity
VOTE=(vote1 vote2)
IP=(ip1 ip2) #ip сервера в формате 142.133.144.100
# telegram bot token, chat id, chat id log, balancewarn, skip_dop
BOT_TOKEN=1111555555:AAAAAdd1fftggLhhHjPkmluvq!vashbottoken!
CHAT_ID_ALARM=-111111111 #чат №1 для тревожных сообщений не забудь -
CHAT_ID_LOG=-111111112 #чат №2 для  Info о ноде , в котором віключені уведомления
BALANCEWARN=(1 1) # если меньше этого числа на балансе то будет тревожное сообщение!
skip_dop=15     #число  которое + к среднему скипу по кластеру, чтоб вывести красн. кружок  возле скипа при его  превышении
#text,alarm text...
TEXT_ALARM=("delinquent Noda1!" "delinquent Noda2!")
INET_ALARM=("Пропал inet Noda1!" "Пропал inet Noda2!")
BALANCE_ALARM=("Пополни Identity Noda1!" "Пополни Identity Noda2!" )
TEXT_NODE=("Info Noda1" "Info Noda2")
TEXT_INFO_EPOCH="Info Epoch Testnet" # заголовок для инфо, или  Testnet или Mainnet
