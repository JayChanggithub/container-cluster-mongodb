#!/bin/bash
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC1='\033[0m'
CWD=$PWD
mongo_flag=False
redis_flag=False
__file__=$(basename $0)
log_name=$(basename $__file__ .sh).log
tm=$(date +'%Y%m%d%T' | tr -s ':' ' ' | tr -d ' ')
revision="`grep 'Rev:' README.md | grep -Eo '([0-9]+\.){2}[0-9]+'`"
passwd='BACKPW'

# backup to NAS, no need to sync between NODE1 and NODE2
# k8s_node1=10.99.104.214
# k8s_node1=""
# k8s_node2=10.99.104.219
back_server=10.99.104.243
file_regex='ares_back_[0-9]+|ares_PeerRev_[0-9]+|ares_RMS_[0-9]+|ares-et_[0-9]+|ares-pa_[0-9]+'

db_list=(chrysaetos
         PeerRev
         RMS
         ares-et
         ares-pa)

name_list=(ares_back
           ares_PeerRev
           ares_RMS
           ares-et
           ares-pa)

# define global functions
function usage
{
    more << EOF
Usage: $0 [Option] argv

Backup Mongo/Redis database data to backup server.

Options:
  -V, --version    display the script version
  -m, --mongo      backup mongodb data
  -r, --redis      backup redis data

EOF
    exit 0
}

function dumpdata
{
    # switch to mongo-compose path
    cd /srv/deploy/sit-db-mongo/

    local container_list=$(docker-compose ps \
                          | sed '1d' \
                          | awk '{print $1 ":" $5}' \
                          | sed '1d')

    # check containers health
    for c in $container_list
    do
        if [ "$(echo $c | awk -F ':' '{print $2}')" != "Up" ]; then
            local container=$(echo $c | awk -F ':' '{print $1}')
            local status=$(echo $c | awk -F ':' '{print $2}')
            printf "%s\t%30s${RED} %s ${NC1}]\n" " * $container " "[" "status: $status."
            exit 255
        fi
    done

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
        esac
        docker-compose exec mongo-master bash -c \
        "mongodump --host localhost:27017 --gzip --db $db_name --archive=/data/db/${back_name}_${tm}.gz"
    done
    cd $CWD
}

function checkgz
{
    local gz_path=/srv/mongo/mongo-master/db/


    cd $gz_path
    for f in ${name_list[@]}
    do
        if [ ! -f ${f}_${tm}.gz ]; then
            printf "%s\t%30s${RED} %s ${NC1}]\n" " * backup data gzfile ${f}_${tm}.gz" "[" "not exist."
            exit 1
        fi
    done
    cd $CWD
    return 0
}

function movebackup
{
    local backup_path='/data/G2BAK/'
    local remote_backup='/data/Mongo'

    cd /srv/mongo/mongo-master/db/
    for gz in *.gz
    do
        if [ $(echo $gz | grep -Eco $file_regex) -eq 1 ]; then
            mv $gz $backup_path
        fi
    done
    cd $CWD
    cd $backup_path
    for d in *.gz
    do
        if [ $(echo $d | grep -Eco $file_regex) -eq 1 ] &&
           [ "$back_server" != "" ]; then
            # sshpass -p ${passwd} rsync -avzh -e "ssh -o StrictHostKeyChecking=no" \
            #            /data/G2BAK/$d root@${back_server}:${remote_backup}
            # using the NAS mount path could not support rsync change remote backup method to scp
            sshpass -p ${passwd} scp -o StrictHostKeyChecking=no \
                    -rp ${backup_path}*.gz root@${back_server}:$remote_backup 2> /dev/null

        fi
    done

    local remote_filecount=$(sshpass -p ${passwd} ssh root@$back_server \
                                     -o StrictHostKeychecking=no \
                                     ls -al $remote_backup | grep -c 'gz')

    if [ $(ls -al $backup_path | grep -c 'gz') -ne $remote_filecount ]; then
        printf "%s\t%30s${RED} %s ${NC1}]\n" " * backup data " "[" "fail."
        exit 1
    fi
    printf "%s\t%30s${YELLOW} %s ${NC1}]\n" " * backup data " "[" "done."
    cd $CWD
}

function delbefore
{
    local backup_path='/data/G2BAK/'
    local remote_backup='/data/Mongo'

    # remove remote server data
    if [ "$back_server" != "" ]; then
        local isdir=$(sshpass -p ${passwd} ssh root@$back_server \
                              -o StrictHostKeychecking=no \
                              test -d ${remote_backup}; echo $?)

        if [ $isdir -eq 0 ]; then
            sshpass -p ${passwd} ssh root@${back_server} \
                    -o StrictHostKeychecking=no "rm -rf $remote_backup/*.gz"
        fi
    fi

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

function delremotebefore
{
    if [ "$k8s_node1" == "" ]; then
        return 1
    fi
    local backup_path='/data/G2BAK/'
    local remote_data=$(sshpass -p ${passwd} ssh root@$k8s_node1 \
                        -o StrictHostKeychecking=no \
                        "ls -al ${backup_path}/*.gz \
                        | awk '{print $NF}' \
                        | sort \
                        | head -n $(( $(ls -al ${backup_path}/*.gz | wc -l) - 7 ))")

    for d in $(echo $remote_data | awk '{print $NF}')
    do
        local f=${d##/*/}
        printf "%s\t%30s${YELLOW} %s ${NC1}]\n" " * move remote data " "[" "$f."
        sshpass -p ${passwd} ssh root@$k8s_node1 \
                    -o StrictHostKeychecking=no \
                    "mv ${backup_path}/$f /tmp/"
    done
}

function mongobackup
{
    # dump data to master node
    dumpdata

    # check dump data
    checkgz

    # reserved latest 7
    delbefore

    # backup data to remote
    movebackup

    # reserved remote latest 7
    # delremotebefore
}

function redisbackup
{
    local container_id=$(docker ps | grep ares-prod-redis | awk '{print $1}')
    local datetime=$(date +'%Y%m%d_%T' | tr -s ':' ' ' | tr -d ' ')
    local backupdir=/data/REDIS/$datetime

    # K8S-NODE2 local
    if [ ! -d $backupdir ]; then
        mkdir -p $backupdir
    fi
    docker exec $container_id redis-cli save
    docker cp $container_id:/data/dump.rdb $backupdir
    if [ -f ${backupdir}/dump.rdb ]; then
        echo -e '\nRedis local backup success!\n'
    else
        echo -e '\nRedis local backup failure!\n'
        exit 1
    fi

    # backup server remote
    if [ "$back_server" != "" ]; then
        #local isdir=$(sshpass -p ${passwd} ssh root@$back_server \
        #                      -o StrictHostKeychecking=no \
        #                      test -d ${backupdir}; echo $?)
        #if [ $isdir -ne 0 ]; then
        #    sshpass -p ${passwd} ssh root@$back_server \
        #            -o StrictHostKeychecking=no \
        #            "mkdir -p $backupdir"
        #fi
        #sshpass -p ${passwd} rsync -avzh \
        #        -e "ssh -o StrictHostKeyChecking=no" \
        #        ${backupdir}/dump.rdb root@${back_server}:$backupdir
        if [ -f ~/.ssh/known_hosts ]; then
            rm -rf /root/.ssh/known_hosts
        fi

        sshpass -p ${passwd} scp -o StrictHostKeyChecking=no \
                                 -rp ${backupdir} root@$back_server:/data/REDIS 2> /dev/null
        local isfile=$(sshpass -p ${passwd} ssh root@$back_server \
                               -o StrictHostKeychecking=no \
                               test -f ${backupdir}/dump.rdb; echo $?)
        if [ $isfile -eq 0 ]; then
            echo -e '\nRedis remote backup to backup server NAS mount point success!\n'
        else
            echo -e '\nRedis remote backup to backup server NAS mount point failure!\n'
            exit 1
        fi
    fi

    # keep 7 newest datas
    backupdir_paraent=$(dirname $backupdir)
    local back_datas=($(ls $backupdir_paraent | sort -Vr))
    if [ ${#back_datas[@]} -gt 7 ]; then
        for e in $(ls $backupdir_paraent | sort -Vr | sed -n 8,${#back_datas[@]}p)
        do
            rm -rf ${backupdir_paraent}/$e
            if [ "$back_server" != "" ]; then
                sshpass -p ${passwd} ssh root@$back_server \
                        -o StrictHostKeychecking=no \
                        "rm -rf ${backupdir_paraent}/$e"
            fi
            echo " ---> remove backup data: ${backupdir_paraent}/$e"
        done
        echo -e '\ndone!\n'
    fi
    echo "List the newest 7 backup datas in $(hostname):"
    ls $backupdir_paraent | sort -Vr | awk '{print " ---> '$backupdir_paraent/'" $0}'
    if [ "$back_server" != "" ]; then
        echo
        echo "List the newest 7 backup datas in $(hostname):"
        sshpass -p ${passwd} ssh root@$back_server \
                -o StrictHostKeychecking=no \
                ls $backupdir_paraent | \
                sort -Vr | \
                awk '{print " ---> '$backupdir_paraent/'" $0}'
    fi
    echo -e '\ndone!\n'
}

function main
{
    if [ "$mongo_flag" == "False" -a "$redis_flag" == "False" ]; then
        echo "Nothing to do.."
        exit 0
    fi
    if [ "$mongo_flag" == "True" ]; then
        echo -e "\nStarting backup MongoDB data.."
        mongobackup
    fi
    if [ "$redis_flag" == "True" ]; then
        echo -e "\nStarting backup Redis data.."
        redisbackup
    fi
}

# parse arguments
if [ "$#" -eq 0 ]; then
    echo "Invalid arguments, try '-h/--help' for more information."
    exit 1
fi
while [ "$1" != "" ]
do
    case $1 in
        -h|--help)
            usage
            ;;
        -V|--version)
            echo "$0 $revision"
            exit 0
            ;;
        -m|--mongo)
            mongo_flag=True
            ;;
        -r|--redis)
            redis_flag=True
            ;;
        * ) echo "Invalid arguments, try '-h/--help' for more information."
            exit 1
            ;;
    esac
    shift
done

# main
main | tee $CWD/reports/${log_name}
