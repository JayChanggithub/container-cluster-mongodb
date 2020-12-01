#!/bin/bash

CWD=$PWD
passwd='BACKPW'
back_server=10.99.104.243
file_regex='ares_back_[0-9]+|ares_PeerRev_[0-9]+|ares_RMS_[0-9]+|ares-et_[0-9]+|ares-pa_[0-9]+|sms-flask_[0-9]+'
mongo_cluster='rs0/mongo-0.mongo:27017,mongo-1.mongo:27017,mongo-2.mongo:27017'
tm=$(date +'%Y%m%d%T' | tr -s ':' ' ' | tr -d ' ')
__file__=$(basename $0)
log_name=$(basename $__file__ .sh).log

db_list=(chrysaetos
         PeerRev
         RMS
         ares-et
         ares-pa
         flask)

name_list=(ares_back
           ares_PeerRev
           ares_RMS
           ares-et
           ares-pa
           sms-flask)

function dumpdata
{
    local dbs_exists=$(mongo --host $mongo_cluster \
                             --quiet \
                             --eval 'db.adminCommand( { listDatabases: 1 , nameOnly : true} )["databases"]')
    for db_name in "${db_list[@]}"
    do
        case $db_name in
            chrysaetos)
                local back_name=ares_back
                ;;
            PeerRev)
                local back_name=ares_PeerRev
                ;;
            RMS)
                local back_name=ares_RMS
                ;;
            ares-et)
                local back_name=ares-et
                ;;
            ares-pa)
                local back_name=ares-pa
                ;;
            flask)
                local back_name=sms-flask
                ;;    
        esac
        
        if [ $(echo $dbs_exists | grep -ci "$db_name") -eq 1 ]; then
            mongodump --host $mongo_cluster --gzip --db $db_name --archive=/data/backup/${back_name}_${tm}.gz
        fi
    done
}


function delbefore
{
    local backup_path='/data/backup'
    cd $backup_path
    for back_name in "${name_list[@]}"
    do
        if [ $(ls -al | grep $back_name | grep -Eco $file_regex) -gt 7 ]; then
            local datas_len=$(ls *.gz | grep -c $back_name)
            local datas_rm=($(ls *.gz | grep $back_name | awk '{print $NF}' | sort -Vr | sed -n 8,${datas_len}p))
            for d in ${datas_rm[@]}
            do
                printf "%s\t%30s${YELLOW} %s ${NC1}]\n" " * remove data " "[" "$d."
                rm -rf $d > /dev/null 2&>1
            done
        fi
    done    
    cd $CWD
}

function main
{
    dumpdata
    
    delbefore
}

if [ -f /data/backup/${log_name} ]; then
    find /data/backup/ -type f -name "${log_name}" -delete
fi

main | tee -a /data/backup/${log_name}
