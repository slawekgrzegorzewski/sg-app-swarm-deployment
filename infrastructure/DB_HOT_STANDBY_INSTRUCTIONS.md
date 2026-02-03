1. Create tmp volume for master DB and mount it in docker-compose.yml
```bash
mkdir /home/slawek/Docker/tmp_master

    volumes:
      - ...
      - ...
      - /home/slawek/Docker/tmp_master:/tmp
```

2. Create tmp volume for standy DB and mount it in docker-compose.yml
```
mkdir /home/slawek/Docker/tmp_standby

volumes:
      - ...
      - ...
      - /home/slawek/Docker/tmp_stanby:/tmp
```

3. Login to a server where master DB is running
```bash
    sudo docker exec <<container_id>> psql -U postgres -c "SHOW listen_addresses;"
    sudo docker exec <<container_id>> psql -U postgres -c "SHOW port;"
    sudo docker exec <<container_id>> psql -U postgres -c "SHOW wal_level;"
    sudo docker exec -it <<container_id>> bash;
```

4. add following line to `/var/lib/postgresql/data/pg_hba.conf`
```bash
    host replication replicator 0.0.0.0/0 scram-sha-256
```
5. execute the following command in db connection

```sql
    CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD '<<replicator_password>>';
    SELECT * FROM pg_create_physical_replication_slot('<<replication_slot_name>>');
    SELECT * FROM pg_replication_slots;
```

```bash
    sudo docker exec -it <<container_id>> bash
    pg_basebackup -D /tmp -S replication_slot_standby1 -X stream -P -U replicator -Fp -R
```

6. Copy `tmp_master` to `hotstandby_data` on machine where replica DB will be running. This might be hard, last time I used WinSCP

7. Verify `postgresql.auto.conf` file on replica DB. It should look like this:
```postgresql.auto.conf
    primary_conninfo = 'host=db_database port=5432 user=replicator password=<<replicator_password>>'
    primary_slot_name = 'replication_slot_standby1'
    restore_command = 'cp /var/lib/postgresql/data/pg_wal/%f "%p"'
```