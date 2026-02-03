Create tmp volume for master DB and mount it in docker-compose.yml
```
mkdir /home/slawek/Docker/tmp_master

    volumes:
      - ...
      - ...
      - /home/slawek/Docker/tmp_master:/tmp
```
Create tmp volume for standy DB and mount it in docker-compose.yml
```
mkdir /home/slawek/Docker/tmp_standby

volumes:
      - ...
      - ...
      - /home/slawek/Docker/tmp_stanby:/tmp
```