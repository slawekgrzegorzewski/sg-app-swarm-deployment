#!/bin/bash

core/management/stop_all.sh
sleep 5
core/management/stop_all.sh
sleep 5
core/management/stop_all.sh
sleep 20

sudo rm -rf core
sudo rm -rf db
sudo rm -rf sg-application

sudo unzip -o docker.zip
sudo rm docker.zip

sudo dos2unix core/**/* 2> /dev/null
sudo dos2unix db/**/* 2> /dev/null
sudo dos2unix secrets/**/* 2> /dev/null
sudo dos2unix sg-application/**/* 2> /dev/null
sudo dos2unix infrastructure/**/* 2> /dev/null

sudo chmod +x core/**/*
sudo chmod +x db/**/*
sudo chmod +x secrets/**/*
sudo chmod +x sg-application/**/*
sudo chmod +x infrastructure/**/*

infrastructure/setup/setup.sh

core/management/start_all.sh