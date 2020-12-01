FROM mongo:4.0.4

# apt update
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update -y
RUN apt-get install -y apt-utils \
                       ca-certificates \
                       tzdata \
                       vim \
                       iputils-ping \
                       curl \
                       net-tools

RUN rm -rf /var/lib/apt/lists/*

# adjust the timezone
RUN ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
RUN dpkg-reconfigure -f noninteractive apt-utils
RUN dpkg-reconfigure -f noninteractive tzdata

# add gpg key
ENV GPG_KEYS 9DA31620334BD75D9DCB49F368818C72E52529D4
RUN gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys "$GPG_KEYS"
RUN gpg --armor --export "$GPG_KEYS" | apt-key add -

ARG MONGO_PACKAGE=mongodb-org
ARG MONGO_REPO=repo.mongodb.org
ENV MONGO_PACKAGE=${MONGO_PACKAGE} MONGO_REPO=${MONGO_REPO}

VOLUME [ '/var/log/mongodb/', '/var/lib/mongodb' ]

COPY mongod.conf /etc/

ADD autokey /etc

RUN chmod 777 /etc/autokey 

USER root

RUN chown -R root:root /data && ls -al /data

WORKDIR /data

EXPOSE 27017

# CMD [ "mongod", "--smallfiles", "--wiredTigerCacheSizeGB=2" ]
CMD [ "mongod", "--smallfiles", "--config", "/etc/mongod.conf", "--wiredTigerCacheSizeGB=5" ]
