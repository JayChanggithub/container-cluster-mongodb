#!/bin/bash

PUR='\033[0;35m'
RED='\033[0;31m'
NC1='\033[0m'
YELLOW='\033[0;33m'
script=$(basename $0)
log_name=$(basename $script .sh).log
line='================================================================'

function check_img
{
    local image='CI_IMAGE:__VERSION__'
    if [ $(docker images | grep -ci $image) -eq 0 ]; then
        echo $PRIVATE_TOKEN | \
        docker login -u iec070781 registry.ipt-gitlab:8081 --password-stdin
        docker pull $image
        return 0
    fi
}

function networkconntest
{
    local network=$1
    if [ "$(command -v curl)" == "" ]; then
        ping $network -c 1 -q > /dev/null 2>&1
    else
        curl $network -c 1 -q > /dev/null 2>&1
    fi

    if [ $? -ne 0 ]; then
        printf "${RED} %s ${NC1} \n" "network disconnection."
        exit 1
    fi
    return 0

}

function checkstatus
{
    case $? in
        "0")
            echo -en "${YELLOW}"
            more << "EOF"

 ________ _           _        __
|_   __  (_)         (_)      [  |
  | |_ \_|_  _ .--.  __  .--.  | |--.
  |  _| [  |[ `.-. |[  |( (`\] | .-. |
 _| |_   | | | | | | | | `'.'. | | | |
|_____| [___|___||__|___|\__) )___]|__]

EOF
            echo -en "${NC1}";;
        "1")
            echo -en "${RED}"
            more << "EOF"
 ______     _ _
 |  ____|  (_) |
 | |__ __ _ _| |
 |  __/ _` | | |
 | | | (_| | | |
 |_|  \__,_|_|_|
EOF
            echo -en "${NC1}";;
    esac
}

function dockerservice
{
    local json=$(cat << EOF
{
    "bip": "172.27.0.1/16",
    "dns": ["10.99.2.59","10.99.6.60"],
    "insecure-registries":["http://registry.ipt-gitlab:8081"],
    "live-restore": true,
    "exec-opts": ["native.cgroupdriver=systemd"],
    "log-driver": "json-file",
    "log-opts": {
    "max-size": "10k",
    "max-file": "3"
      }
}
EOF
)
    if [ "$(command -v docker)" != "" ]; then
        printf "${PUR} %s ${NC1} \n" "docker engine already installation."
    else
        printf "${RED} %s ${NC1} \n" "start installed the Docker engine."
        yum install -y yum-utils device-mapper-persistent-data lvm2
        yum-config-manager \
        --add-repo \
        https://download.docker.com/linux/centos/docker-ce.repo
        yum-config-manager --enable docker-ce-edge
        yum makecache fast
        yum install -y docker-ce
        systemctl enable docker.service
        systemctl start docker.service
        if [ $? -ne 0 ]; then
            yum --enablerepo=epel install docker-ce -y
            systemctl enable docker.service
            systemctl start docker.service
        fi
    fi

    # check command of docker-compose
    if [ "$(command -v docker-compose)" == "" ]; then
        curl -s -L \
        https://github.com/docker/compose/releases/download/1.21.2/docker-compose-$(uname -s)-$(uname -m) \
        -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        systemctl enable docker.service
        systemctl restart docker.service
    fi

    # check docker daemon file
    printf "${PUR} %s ${NC1} \n" "${line}Setup the /etc/docker/daemon.json${line}"
    tee /tmp/docker_tmp.json << eof
$json
eof

    # setup docker configuration
    if [ ! -f /etc/docker/daemon.json -o \
         -n "$(diff /etc/docker/daemon.json /tmp/docker_tmp.json)" ]; then
        tee /etc/docker/daemon.json << eof
$json
eof
        systemctl daemon-reload
        systemctl restart docker.service
        if [ $(docker ps | grep -ci 'gitlab-runner') -ne 0 ]; then
            docker restart gitlab-runner
        fi
    fi
    if [ $? -ne 0 ]; then
        printf "${RED} %s ${NC1} \n" "docker service failed."
        exit 1
    fi
    return 0
}

function compose_net
{
    local subnet='172.28.0.0'
    if [ $(docker network ls \
           | awk '{print $2}' \
           | sed '1d' \
           | grep -ci 'docker-compose-net') -eq 0 ]; then
        docker network create --subnet=${subnet}/16 docker-compose-net
        local sub_info=$(docker network inspect docker-compose-net \
                         | grep -Ei 'Subnet' \
                         | awk -F ':' '{print $2}' \
                         | grep -Po '(\d+\.){3}\d+')
        if [ "$sub_info" == "$subnet" ]; then
            printf "%s\t%30s${YELLOW} %s ${NC1}]\n" " * subnet " "[" "$subnet"
            return 0
        else
            printf "%s\t%30s${RED} %s ${NC1}]\n" " * subnet " "[" "Failed."
            exit 1
        fi
    fi
    printf "%s\t%30s${YELLOW} %s ${NC1}]\n" " * docker-compose-net: $sub_info " "[" "exsit."
    return 0
}

function runservice
{
    if [ $(docker-compose ps | grep -ci mongo) -ne 0 ]; then
        docker-compose restart
        return 0
    fi
    if [ -f $PWD/docker-compose.yaml ]; then
        docker-compose --compatibility -f $PWD/docker-compose.yaml up -d
        if [ $? -ne 0 ]; then
            return 1
        fi
        return 0
    else
        printf "%s\t%30s${RED} %s ${NC1}]\n" " * docker-compose.yaml " "[" "not found."
        exit 1
    fi
}

function main
{
    # network connection
    networkconntest www.google.com

    # check docker service
    dockerservice

    # check docker-compose bridge net
    compose_net

    # check docker image
    check_img

    # docker-compose *.yaml
    runservice

    # check result
    checkstatus
}

main | tee $PWD/reports/${log_name}
