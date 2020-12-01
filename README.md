# SIT-DB-Mongo

> Mongo cluster from docker-compse : [Mongo-DB](https://blog.skbali.com/2019/05/mongodb-replica-set-using-docker-compose/)

---

## Suitable Project

   - `None`

---

## Version

`Rev: 1.0.2`

---

## Description

   - MongoDB is a cross-platform and open-source document-oriented database, a kind of NoSQL database.
   - This makes data integration for certain types of applications faster and easier.
   - MongoDB is built for scalability, high availability and performance from a single server deployment to large and complex multi-site infrastructures.

---

## Usage

  - **`Docker-compose`**

    - Check docker-compose bridge network.

      ```bash
      $ docker network ls
      ********        docker-compose-net   bridge              local

      $ ifconfig
      br-******
      inet 172.28.0.1  netmask 255.255.0.0  broadcast 172.28.255.255

      # check the bridge detail information
      $ docker inspect <bridge network name>
      ```

    - Stop the Mongo DB cluster from docker-compose.

      ```bash
      # switch to path of deploy mongodb
      $ cd /srv/deploy/sit-db-mongo

      # check the container service
      $ docker-compose ps
          Name                  Command               State            Ports
      --------------------------------------------------------------------------------
      mongo-master   /usr/bin/mongod --bind_ip_ ...   Up      0.0.0.0:31000->27017/tcp
      mongo-slave1   /usr/bin/mongod --bind_ip_ ...   Up      0.0.0.0:31001->27017/tcp
      mongo-slave2   /usr/bin/mongod --bind_ip_ ...   Up      0.0.0.0:31002->27017/tcp

      # stop mongo db cluster and remove container
      $ docker-compose stop mongo-master mongo-slave1 mongo-slave2  && docker-compose rm mongo-master mongo-slave1 mongo-slave2
      ```

    - Setting the cluster primary, secondary db and sync the data from replica set

      ```bash
      # login the container bash
      $ docker-compose exec mongo-master bash

      # login mongo database
      $ mongo --port 27017

      # replica set initial
      > rs.initiate()

      {
          "operationTime" : Timestamp(1570707192, 1),
          "ok" : 0,
          "errmsg" : "already initialized",
          "code" : 23,
          "codeName" : "AlreadyInitialized",
          "$clusterTime" : {
                  "clusterTime" : Timestamp(1570707192, 1),
                  "signature" : {
                          "hash" : BinData(0,"AAAAAAAAAAAAAAAAAAAAAAAAAAA="),
                          "keyId" : NumberLong(0)
                  }
          }
      }

      # add another db
      > rs.add('mongo-slave1')
      > rs.add('mongo-slave2')

      # let us check our replica set
      > rs.printSlaveReplicationInfo()
      > db.runCommand("ismaster")
      ```

    - if login from secondary db

      ```bash
      $ mongo --port <node port>
      > rs.slaveOk()
      > show dbs
      admin       0.000GB
      chrysaetos  0.262GB
      config      0.000GB
      local       0.670GB

      # switch db
      > use <db name>

      # print a list of all collections for current database
      > show collections
      ```

    - How to force a menber to be primary

      > Force a menber to be primary: [docs](https://docs.mongodb.com/manual/tutorial/force-member-to-be-primary/)

      ```bash
      # The first login to primary node
      > cfg = rs.conf()
      > cfg.members[0].priority = 1 # reset the primary node
      > cfg.members[1].priority = 0.5
      > cfg.members[2].priority = 0.5
      > rs.reconfig(cfg)
      ```

    - How to connect mongodb

      ```baah
      # master
      $ mongo --port 31000

      # slave1
      $ mongo --port 31001

      # slave2
      $ mongo --port 31002
      ```

    - Restore the data to mongodb cluster

      ```bash
      $ cp -r <data> /srv/mongo/mongo-master/db/
      $ docker-compose exec mongo-master bash -c 'mongorestore -d <data> --drop /data/db/<data>'
      ```

    - Restore database from `.gz`

      ```bash
      $ cd /srv/deploy/sit-db-mongo

      # first restore
      $ docker-compose exec mongo-master bash -c 'mongorestore --gzip --archive=/data/db/<filename>.gz --db chrysaetos'

      # second restore to cover before same data
      $ docker-compose exec mongo-master bash -c 'mongorestore --gzip --drop --archive=/data/db/<filename>.gz --db chrysaetos'
      ```

    - Backup database to `gz`

      ```bash
      $ cd /srv/deploy/sit-db-mongo
      $ docker-compose exec mongo-master bash -c \
      'mongodump --host localhost:27017 --gzip --db chrysaetos --archive=/data/db/ares_back_$(date +'%Y%m%d%T' | tr -s ':' ' ' | sed -E s', ,,'g).gz'
      ```

  - **`kubernetes`**


     - Create persistent volumes of Glusterfs for mongoDB cluster


       ```bash
       $ git clone http://ipt-gitlab.ies.inventec:8081/SIT-develop-tool/Cluster-PersistentVolume-Glusterfs.git

       # modify the endpoint IP of cluster
       $ vim Cluster-PersistentVolume-Glusterfs/inventory

       $ vim Cluster-PersistentVolume-Glusterfs/variables/variables.yaml


       master1_host: 'k8s-master1'
       master2_host: 'k8s-master2'
       master3_host: 'k8s-master3'


       master1_ip: '192.168.44.1'
       master2_ip: '192.168.44.2'
       master3_ip: '192.168.44.3'

       share_volumes:
         - 'mongo-data1'
         - 'mongo-data2'
         - 'mongo-data3'

       # deployment the glusterfs type volume in each endpoint
       $ ansible-playbook -i inventory deploy.yaml


       ....
       ....
       ....

       # Check volume information in each endpoint
       $ gluster volume info
       $ ls /opt/gluster
       ```

    - Create replicaset mongoDB in kubernetes ecosystem


      ```bash
      $ kubectl apply -f deployments/*

      # check pod status
      $ kubectl get sc,pv,pvc,pod -n kube-ops
      ```

    - initialize and setup the MongoDB replicaset cluster

      ```bash
      $ kubectl exec -it mongo-0 mongo -n kube-ops bash

      > cfg = {_id:"rs0",
               members: [
                   {_id:0, host:"mongo-0.mongo:27017"},
                   {_id:1, host:"mongo-1.mongo:27017"},
                   {_id:2, host:"mongo-2.mongo:27017"}
               ]
        };


      > rs.initiate(cfg)
      > cfg = rs.conf()
      > cfg.members[0].priority = 1 # reset the primary node
      > cfg.members[1].priority = 0.5
      > cfg.members[2].priority = 0.5
      > rs.reconfig(cfg)


      # check status is primary or secondary
      > rs.status()['members'][$index]['stateStr']

      # when 'stateStr' not primary or secondary re-initialize again
      ```

    - After primary node restart encountered mongo logs as 'InvalidReplicaSetConfig: Our replica set config is invalid or we are not a member of it'

      ```bash
      $ kubectl exec -it mongo-0 mongo -n kube-ops bash
      > rs.reconfig(rs.config(),{force:true})
      ```


    - whole the mongo cluster members

      ```bash
      $ kubectl exec -it mongo-0 -n kube-ops bash
      $ mongo mongodb://mongo-0.mongo,mongo-1.mongo,mongo-2.mongo --eval 'rs.status()' | grep name

                   "name" : "mongo-0.mongo:27017",
                   "name" : "mongo-1.mongo:27017",
                   "name" : "mongo-2.mongo:27017",
      ```

    - Find out the primary mongo member

      ```bash
      $ kubectl exec -it mongo-0 -n kube-ops bash


      for index in `seq 0 2`
      do
          flag=`mongo mongodb://mongo-$index.mongo --eval 'db.runCommand("ismaster")' \
                | grep 'ismaster' \
                | awk -F ':' '{print $2}' \
                | sed -E s',^ ,,'g | tr -d ','`
          if [ "$flag" == "true" ]; then
              echo -e "\n mongo-$index is primary \n"
          fi
      done
      ```

    - Restore data from `.gz`

      ```bash
      $ kubectl cp ares_RMS_20200916132039.gz ${mongo-master-pod}:/tmp -n kube-ops
      $ kubectl exec -it ${mongo-master-pod} -n kube-ops -it bash
      $ mongorestore --gzip --drop --archive=/tmp/ares_RMS_20200916132039.gz --db RMS
      ```

    - Dump data to `.gz`

      ```bash
      $ kubectl run mongo-client --image registry.ipt-gitlab:8081/ta-web/sit-db-mongo/mongo-backup-client:__$VERSION__ --attach --rm --restart=Never -it -n kube-ops -- bash
      $ mongo_cluster='rs0/mongo-0.mongo:27017,mongo-1.mongo:27017,mongo-2.mongo:27017'
      $ mongodump --host $mongo_cluster --gzip --db chrysaetos --archive=/tmp/ares_back.gz
      $ scp -rp /tmp/ares_back.gz root@10.99.104.214:/tmp
      ```
---

## Log

  - The shell script execution log within in path `/srv/deploy/sit-db-mongo/reports`

    ```bash
    $ cat /srv/deploy/sit-db-mongo/reports/mongo-setup.log
    ```
  - The backup script execution log within in path `/srv/deploy/sit-db-mongo/reports`

    ```bash
    $ cat /srv/deploy/sit-db-mongo/reports/mongo_backup.log
    ```

---

## Contact
##### Author: Chang.Jay
