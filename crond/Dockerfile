FROM registry.ipt-gitlab:8081/ta-web/sit-db-mongo/mongo-base:1.0.0

RUN apt-get update -y \
    && apt-get install openssh-client -y 
    
    
RUN mkdir -p /data/backup

ADD mongo-cluster-backup.sh /root
