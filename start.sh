#!/bin/bash

########################### recovery ##############################
############################ 表级回档 #############################
##### 用来恢复的临时实例需要是mysql空实例，刚安装的，不用启动 #####
################# my.cnf 配置修改，提升恢复速度 ###################
################## relay_log_recovery=0 ###########################
##################     sync_binlog=0    ###########################
############ innodb_flush_log_at_trx_commit=0 #####################
############ slave_parallel_type=LOGICAL_CLOCK ####################
#############    slave_parallel_workers=8  ########################
###################### skip-log-bin ###############################
###################################################################
# 备份文件格式backup_`date +%Y%m%d%H%M%S`.xbstream，中间需要带上日期，以备份文件名称中的日期来寻找对应的全备文件
# 备份文件需要使用innobackupex物理备份，是否使用压缩，通过recovery.config中的backup_use_compress参数控制

# [app@VM-0-11-centos ~]$ ssh app@127.0.0.1 "date"           
# The authenticity of host '127.0.0.1 (127.0.0.1)' can't be established.
# ECDSA key fingerprint is SHA256:e4z4le+TU+RXIFU3rXFCe6C2GGGrkISBEjk3tlWogek.
# ECDSA key fingerprint is MD5:a2:9a:a7:6c:a9:09:0f:34:5f:65:62:87:38:52:ec:6b.
# Are you sure you want to continue connecting (yes/no)? 

source ./recovery.config

# 执行核心
sh recovery.sh >> ./recovery.log 2>&1

# 收尾工作
ssh $mysql_recovery_linux_user@$mysql_recovery_host "/bin/sh /tmp/clear_tmp_mysql.sh"
ssh $backup_server_user@$backup_server "/bin/rm -fr /tmp/get_backupfile.sh /tmp/recovery.config"

ssh $mysql_recovery_linux_user@$mysql_recovery_host "/bin/rm -fr $mysql_recovery_backup_temp_dir /tmp/init_temp_mysql_instance.sh /tmp/clear_tmp_mysql.sh /tmp/recovery.config /tmp/temp.config"

ssh $mysql_linux_user@$mysql_host "/bin/rm -fr $mysql_backup_temp_dir /tmp/get_binlog.sh /tmp/temp.config /tmp/recovery.config"
