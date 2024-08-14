#!/bin/bash

core/management/stop_all.sh
sleep 5
core/management/stop_all.sh
sleep 5
core/management/stop_all.sh
sleep 20

rm -rf core
rm -rf db
rm -rf sg-application

unzip -o dockerRpi4.zip
rm dockerRpi4.zip

dos2unix core/**/* 2> /dev/null
dos2unix db/**/* 2> /dev/null
dos2unix secrets/**/* 2> /dev/null
dos2unix sg-application/**/* 2> /dev/null

chmod +x core/**/*
chmod +x db/**/*
chmod +x secrets/**/*
chmod +x sg-application/**/*

core/management/start_all.sh