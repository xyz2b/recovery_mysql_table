#!/bin/bash

cd /tmp/
# 清空临时库
source ./recovery.config

echo "clear tmp mysql instance, $mysql_recovery_host:$mysql_recovery_port"

cd $mysql_recovery_bin
sh $mysql_recovery_stop_scirpt
rm -fr $mysql_recovery_data/*
rm -fr $mysql_recovery_logs/*

echo "clear tmp mysql instance completed, $mysql_recovery_host:$mysql_recovery_port"