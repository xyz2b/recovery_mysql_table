#!/bin/bash

# 回档的主控文件
source ./recovery.config

echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | start recovery mysql $mysql_host:$mysql_port table $recovery_tables to $recovery_date"

recovery_table=`echo $recovery_tables|sed s/[[:space:]]//g`

# 获取对应恢复时间点之前最近的一次全量备份，传送到本地
scp recovery.config $backup_server_user@$backup_server:/tmp/
if [ $? -ne 0 ];then
	echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | scp recovery.config to backup server $backup_server_user@$backup_server:/tmp/ failed"
	exit -1;
fi
scp get_backupfile.sh $backup_server_user@$backup_server:/tmp/
if [ $? -ne 0 ];then
	echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | scp get_backupfile.sh to backup server $backup_server_user@$backup_server:/tmp/ failed"
	exit -1;
fi

echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | exec get_backupfile.sh in $backup_server_user@$backup_server backup server" 
backup_server_stdout=`ssh $backup_server_user@$backup_server "/bin/sh /tmp/get_backupfile.sh"`
if [ $? -ne 0 ];then
	echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | exec get_backupfile.sh in backup server $backup_server_user@$backup_server failed"
	echo "$backup_server_stdout"
	exit -1;
fi
echo "$backup_server_stdout"

backup_file=`echo "$backup_server_stdout"|tail -1|grep backup_file|cut -f 2 -d'='`
if [[ $backup_file == '' ]];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | Can not find any xbackup file before $recovery_date"
  exit -6
fi
echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | find first mysql data innobackupex backup file before $recovery_date: $backup_file"
echo "backup_file=$backup_file" > temp.config

/bin/mkdir -p $mysql_recovery_backup_temp_dir
if [ $? -ne 0 ];then
	echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | create $mysql_recovery_backup_temp_dir dir failed"
	exit -1;
fi
scp $backup_server_user@$backup_server:$mysql_data_backup_dir/$backup_file $mysql_recovery_backup_temp_dir/
if [ $? -ne 0 ];then
	echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | scp $backup_file backup file to this server failed"
	rm -fr $mysql_recovery_backup_temp_dir
	exit -1;
fi


export MYSQL_PWD=$mysql_recovery_password
mysql_client="$mysql_bin/mysql -h $mysql_host -u $mysql_user -P $mysql_port -N -B"
server_uuid=`$mysql_client -e "show global variables like 'server_uuid';"|awk '{print $2}'`
if [ $? -ne 0 ];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | show server uuid from mysql instance $mysql_host:$mysql_port failed"
  exit -1
fi
echo "server_uuid=$server_uuid" >> temp.config

# 将获取到的全备文件传送到临时实例，然后初始化临时实例上的mysql，停止进程，清理data和logs目录，然后将全备恢复出来
mysql_recovery_server_stdout=`ssh $mysql_recovery_linux_user@$mysql_recovery_host "/bin/mkdir -p $mysql_recovery_backup_temp_dir"`
if [ $? -ne 0 ];then
	echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | exec /bin/mkdir -p $mysql_recovery_backup_temp_dir in mysql recovery server $mysql_recovery_linux_user@$mysql_recovery_host failed"
	echo "$mysql_recovery_server_stdout"
	rm -fr $mysql_recovery_backup_temp_dir
	exit -1;
fi
echo "$mysql_recovery_server_stdout"

scp $mysql_recovery_backup_temp_dir/$backup_file $mysql_recovery_linux_user@$mysql_recovery_host:$mysql_recovery_backup_temp_dir/
if [ $? -ne 0 ];then
	echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | scp $backup_file backup file to $mysql_recovery_linux_user@$mysql_recovery_host:$mysql_recovery_backup_temp_dir/ temp recovery mysql failed"
	rm -fr $mysql_recovery_backup_temp_dir
	exit -1;
fi

scp init_temp_mysql_instance.sh $mysql_recovery_linux_user@$mysql_recovery_host:/tmp/
if [ $? -ne 0 ];then
	echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | scp init_temp_mysql_instance.sh to temp mysql server $mysql_recovery_linux_user@$mysql_recovery_host:/tmp/ failed"
	exit -1;
fi

scp clear_tmp_mysql.sh $mysql_recovery_linux_user@$mysql_recovery_host:/tmp/
if [ $? -ne 0 ];then
	echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | scp clear_tmp_mysql.sh to temp mysql server $mysql_recovery_linux_user@$mysql_recovery_host:/tmp/ failed"
	exit -1;
fi

scp temp.config $mysql_recovery_linux_user@$mysql_recovery_host:/tmp/
if [ $? -ne 0 ];then
	echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | scp temp.config to temp mysql server $mysql_recovery_linux_user@$mysql_recovery_host:/tmp/ failed"
	exit -1;
fi
rm -fr temp.config

echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | exec clear_tmp_mysql.sh in $mysql_recovery_linux_user@$mysql_recovery_host temp recovery mysql" 
mysql_recovery_server_stdout=`ssh $mysql_recovery_linux_user@$mysql_recovery_host "/bin/sh /tmp/clear_tmp_mysql.sh"`
if [ $? -ne 0 ];then
	echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | exec clear_tmp_mysql.sh in $mysql_recovery_linux_user@$mysql_recovery_host temp recovery mysql failed"
	echo "$mysql_recovery_server_stdout"
	exit -1;
fi
echo "$mysql_recovery_server_stdout"

echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | exec init_temp_mysql_instance.sh in $mysql_recovery_linux_user@$mysql_recovery_host temp recovery mysql" 
mysql_recovery_server_stdout=`ssh $mysql_recovery_linux_user@$mysql_recovery_host "/bin/sh /tmp/init_temp_mysql_instance.sh"`
if [ $? -ne 0 ];then
	echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | exec init_temp_mysql_instance.sh in $mysql_recovery_linux_user@$mysql_recovery_host temp recovery mysql failed"
	echo "$mysql_recovery_server_stdout"
	exit -1
fi
echo "$mysql_recovery_server_stdout"

# 起始binlog文件和位置信息
mysql_bin_log_start_file=`echo "$mysql_recovery_server_stdout"|tail -1|grep mysql_bin_log_start_file|cut -f 2 -d'='`
if [[ $mysql_bin_log_start_file == '' ]];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | Can not find binlog file info in xbackup backup file"
  exit -6
fi
echo "mysql_bin_log_start_file=$mysql_bin_log_start_file" > temp.config
mysql_start_log_pos=`echo "$mysql_recovery_server_stdout"|tail -2|head -1|grep mysql_start_log_pos|cut -f 2 -d'='`
if [[ $mysql_start_log_pos == '' ]];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | Can not find binlog pos info in xbackup backup file"
  exit -6
fi
if [ ! -n "$(echo $mysql_start_log_pos | sed -n "/^[0-9]\+$/p")" ];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | binlog pos is not number in xbackup backup file"
  exit -6
fi
mysql_start_gtid=`echo "$mysql_recovery_server_stdout"|tail -3|head -1|grep mysql_start_gtid|cut -f 2 -d'='`
if [[ $mysql_start_gtid == '' ]];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | Can not find binlog gtid info in xbackup backup file"
  exit -6
fi
echo "mysql_start_gtid=$mysql_start_gtid" >> temp.config
mysql_gtid_set=`echo "$mysql_recovery_server_stdout"|tail -4|head -1|grep mysql_gtid_set|cut -f 2 -d'='`
if [[ $mysql_gtid_set == '' ]];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | Can not find mysql_gtid_set in xbackup backup file"
  exit -6
fi

rm -fr $mysql_recovery_backup_temp_dir/*


# 去待恢复mysql实例上，找到结束binlog以及结束位置gtid信息，然后将所有有关的binlog传送到本地
mysql_server_stdout=`ssh $mysql_linux_user@$mysql_host "/bin/mkdir -p $mysql_backup_temp_dir"`
if [ $? -ne 0 ];then
	echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | exec /bin/mkdir -p $mysql_backup_temp_dir in mysql server $mysql_linux_user@$mysql_host failed"
	echo "$mysql_server_stdout"
	exit -1;
fi
echo "$mysql_server_stdout"

scp get_binlog.sh $mysql_linux_user@$mysql_host:/tmp/
if [ $? -ne 0 ];then
	echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | scp get_binlog.sh to mysql server $mysql_linux_user@$mysql_host:/tmp/ failed"
	exit -1;
fi

scp temp.config $mysql_linux_user@$mysql_host:/tmp/
if [ $? -ne 0 ];then
	echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | scp temp.config to mysql server $mysql_linux_user@$mysql_host:/tmp/ failed"
	exit -1;
fi
rm -fr temp.config

echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | exec get_binlog.sh in $mysql_linux_user@$mysql_host mysql" 
mysql_server_stdout=`ssh $mysql_linux_user@$mysql_host "/bin/sh /tmp/get_binlog.sh"`
if [ $? -ne 0 ];then
	echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | exec get_binlog.sh in $mysql_linux_user@$mysql_host mysql failed"
	echo "$mysql_server_stdout"
	exit -1;
fi
echo "$mysql_server_stdout"

mysql_end_gtid=`echo "$mysql_server_stdout"|tail -1|grep mysql_end_gtid|cut -f 2 -d'='`
# mysql_end_gtid需要加1，因为是SQL_BEFORE_GTIDS，需要回放到mysql_end_gtid，还要往后移一位
mysql_end_gtid_no=`echo "$mysql_end_gtid"|awk -F'-' '{print $NF}'`
mysql_end_uuid=`echo "$mysql_end_gtid"|awk -F':' '{print $1}'`
((mysql_sql_brefore_gtid_no = mysql_end_gtid_no + 1))
# mysql_sql_brefore_gtid=`echo "$server_uuid:$mysql_sql_brefore_gtid_no"`
mysql_server_uuid_gtid_no=`echo $mysql_gtid_set|awk -F', ' '{i=1; while(i<=NF){if(match($i, /'$mysql_end_uuid'/) > 0) print $i; i++ }}'|awk -F'-' '{print $NF}'`
mysql_gtid_set=`echo $mysql_gtid_set|awk -F', ' '{i=1; while(i<=NF){if(match($i, /'$mysql_end_uuid'/) > 0)  sub('$mysql_end_gtid_no', '$mysql_sql_brefore_gtid_no', $i); if(i==NF){ printf "%s",$i } else {printf "%s, ",$i}; i++ }}'`
binlog_package=`echo "$mysql_server_stdout"|tail -2|head -1|grep binlog_package|cut -f 2 -d'='`

scp $mysql_linux_user@$mysql_host:$mysql_backup_temp_dir/$binlog_package $mysql_recovery_backup_temp_dir/
if [ $? -ne 0 ];then
	echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | scp $binlog_package binlog package to this server failed"
	rm -fr $mysql_recovery_backup_temp_dir
	exit -1;
fi

# 将binlog传送到临时实例，并解压到临时实例的logs下
mysql_recovery_server_stdout=`ssh $mysql_recovery_linux_user@$mysql_recovery_host "/bin/mkdir -p $mysql_recovery_backup_temp_dir"`
if [ $? -ne 0 ];then
	echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | exec /bin/mkdir -p $mysql_recovery_backup_temp_dir in mysql recovery server $mysql_recovery_linux_user@$mysql_recovery_host failed"
	echo "$mysql_recovery_server_stdout"
	rm -fr $mysql_recovery_backup_temp_dir
	exit -1;
fi
echo "$mysql_recovery_server_stdout"

scp $mysql_recovery_backup_temp_dir/$binlog_package $mysql_recovery_linux_user@$mysql_recovery_host:$mysql_recovery_backup_temp_dir/
if [ $? -ne 0 ];then
	echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | scp $mysql_recovery_backup_temp_dir/$binlog_package binlog paclage to temp mysql server $mysql_recovery_linux_user@$mysql_recovery_host:$mysql_recovery_backup_temp_dir/ failed"
	ssh $mysql_recovery_linux_user@$mysql_recovery_host "/bin/rm -fr $mysql_recovery_backup_temp_dir"
	rm -fr $mysql_recovery_backup_temp_dir
	exit -1;
fi

mysql_recovery_server_stdout=`ssh $mysql_recovery_linux_user@$mysql_recovery_host "/bin/tar zxf $mysql_recovery_backup_temp_dir/$binlog_package -C $mysql_recovery_logs/"`
if [ $? -ne 0 ];then
	echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | exec /bin/tar zxf $mysql_recovery_backup_temp_dir/$binlog_package -C $mysql_recovery_logs/ in $mysql_recovery_linux_user@$mysql_recovery_host temp recovery mysql failed"
	echo "$mysql_recovery_server_stdout"
	ssh $mysql_recovery_linux_user@$mysql_recovery_host "/bin/rm -fr $mysql_recovery_backup_temp_dir"
	exit -1;
fi
echo "$mysql_recovery_server_stdout"

mysql_server_stdout=`ssh $mysql_linux_user@$mysql_host "/bin/rm -fr $mysql_backup_temp_dir"`
if [ $? -ne 0 ];then
	echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | exec /bin/rm -fr $mysql_backup_temp_dir in mysql server $mysql_linux_user@$mysql_host failed"
	echo "$mysql_server_stdout"
	rm -fr $mysql_recovery_backup_temp_dir
	exit -1;
fi
echo "$mysql_server_stdout"

mysql_recovery_server_stdout=`ssh $mysql_recovery_linux_user@$mysql_recovery_host "chown -R "$mysql_recovery_linux_user:$mysql_recovery_linux_group" $mysql_recovery_logs/"`
if [ $? -ne 0 ];then
	echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | exec chown -R "$mysql_recovery_linux_user:$mysql_recovery_linux_group" $mysql_recovery_logs/ in $mysql_recovery_linux_user@$mysql_recovery_host temp recovery mysql failed"
	echo "$mysql_recovery_server_stdout"
	ssh $mysql_recovery_linux_user@$mysql_recovery_host "/bin/rm -fr $mysql_recovery_backup_temp_dir"
	exit -1;
fi
echo "$mysql_recovery_server_stdout"

# 启动临时实例
mysql_recovery_server_stdout=`ssh $mysql_recovery_linux_user@$mysql_recovery_host "cd $mysql_recovery_bin && sh $mysql_recovery_start_scirpt > nohup.out"`
if [ $? -ne 0 ];then
	echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | exec cd $mysql_recovery_bin && sh $mysql_recovery_start_scirpt in $mysql_recovery_linux_user@$mysql_recovery_host temp recovery mysql failed"
	echo "$mysql_recovery_server_stdout"
	ssh $mysql_recovery_linux_user@$mysql_recovery_host "/bin/rm -fr $mysql_recovery_backup_temp_dir"
	exit -1;
fi
echo "$mysql_recovery_server_stdout"
rm -fr $mysql_recovery_backup_temp_dir

# 等待mysql启动
sleep 5

# 操作临时库，回放relaylog
recovery_mysql_client="$mysql_recovery_bin/mysql -h $mysql_recovery_host -u $mysql_recovery_user -P $mysql_recovery_port -N -B"
recovery_mysql_client_with_column_name="$mysql_recovery_bin/mysql -h $mysql_recovery_host -u $mysql_recovery_user -P $mysql_recovery_port -B"

## change master指定一个空的主库，创建SQL线程
$recovery_mysql_client -e "reset master;"
if [ $? -ne 0 ];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | reset master in temp mysql instance failed"
  exit -1
fi
$recovery_mysql_client -e "stop slave;"
if [ $? -ne 0 ];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | stop slave in temp mysql instance failed"
  exit -1
fi
$recovery_mysql_client -e "reset slave;"
if [ $? -ne 0 ];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | reset slave in temp mysql instance failed"
  exit -1
fi
$recovery_mysql_client -e "reset slave all;"
if [ $? -ne 0 ];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | reset slave all in temp mysql instance failed"
  exit -1
fi

## change master
mysql_relay_log_start_file=`echo $mysql_bin_log_start_file| sed "s/$mysql_bin_log_file_prefix/$mysql_relay_log_file_prefix/"`
$recovery_mysql_client -e "CHANGE MASTER TO MASTER_HOST='1.1.1.1',RELAY_LOG_FILE='$mysql_relay_log_start_file',RELAY_LOG_POS=$mysql_start_log_pos;"
if [ $? -ne 0 ];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | change master to relay_log_file=$mysql_relay_log_start_file relay_log_pos=$mysql_start_log_pos failed"
  exit -1
fi

# 查看指定的位点是否生效
recovery_mysql_slave_relay_log_info=`$recovery_mysql_client -e "select * from mysql.slave_relay_log_info;"`
if [ $? -ne 0 ];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | query mysql.slave_relay_log_info failed"
  exit -1
fi
if [[ $recovery_mysql_slave_relay_log_info == '' ]];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | mysql.slave_relay_log_info is null"
  exit -4
fi
recovery_mysql_slave_relay_log_file=`echo $recovery_mysql_slave_relay_log_info | cut -f 2 -d' '|xargs basename`
if [[ $recovery_mysql_slave_relay_log_file == '' ]];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | mysql.slave_relay_log_info recovery_mysql_slave_relay_log_file is null"
  exit -4
fi
recovery_mysql_slave_relay_log_pos=`echo $recovery_mysql_slave_relay_log_info | cut -f 3 -d' ' `
if [ $recovery_mysql_slave_relay_log_pos -eq 0 ];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | mysql.slave_relay_log_info recovery_mysql_slave_relay_log_pos is 0"
  exit -4
fi
if [ $recovery_mysql_slave_relay_log_file != $mysql_relay_log_start_file -o $recovery_mysql_slave_relay_log_pos -ne $mysql_start_log_pos ];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | the relay log file and log pos in recovery mysql instance and the relay log file and log pos in backup file are not equal"
  exit -4
fi

## 指定回放数据的表或库
## 指定库: CHANGE REPLICATION FILTER REPLICATE_WILD_DO_TABLE = ('sbtest.%');
table_array=(${recovery_tables//,/ })
table_string=''
for table in ${table_array[@]};
do
  if [[ $table_string == '' ]];then
    table_string=`echo "'$table'"`
  else
    table_string=`echo "$table_string,'$table'"`
  fi
done

$recovery_mysql_client -e "CHANGE REPLICATION FILTER REPLICATE_WILD_DO_TABLE = ($table_string);"
if [ $? -ne 0 ];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | change replication filter $recovery_table failed"
  exit -1
fi
 
## 只需要开启SQL线程对指定的relay log开始回放即可
$recovery_mysql_client -e "START SLAVE SQL_THREAD UNTIL SQL_BEFORE_GTIDS=\"$mysql_gtid_set\";"
if [ $? -ne 0 ];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | start slave sql_thread UNTIL SQL_BEFORE_GTIDS=$mysql_gtid_set failed"
  exit -1
fi
 
## 持续执行可看到binlog数据开始回放
while :
do
	recovery_mysql_slave_status=`$recovery_mysql_client_with_column_name -e "show slave status\G"`
	if [ $? -ne 0 ];then
	  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | get recovery mysql slave status failed"
	  exit -1
	fi

	executed_gtid_set=`echo "$recovery_mysql_slave_status"|sed -n '/Executed_Gtid_Set/,/Auto_Position/{p}'|grep -v Auto_Position|sed 's/Executed_Gtid_Set://g'|sed 's/ //g'|xargs`
	slave_sql_running=`echo "$recovery_mysql_slave_status"|grep Slave_SQL_Running|awk '{print $2}'`
	last_errno=`echo "$recovery_mysql_slave_status"|grep Last_Errno|awk '{print $2}'`
	last_error=`echo "$recovery_mysql_slave_status"|grep Last_Error|awk '{print $2}'`
	replicate_wild_do_table=`echo "$recovery_mysql_slave_status"|grep Replicate_Wild_Do_Table|awk '{print $2}'`
	slave_SQL_running_state=`echo "$recovery_mysql_slave_status"|grep Slave_SQL_Running_State|awk -F":" '{print $2}'`

#	if [[ $executed_gtid_set == '' ]];then
#		echo "Waiting for slave workers to process their queues, sleep 5s, do next check, slave_sql_running=$slave_sql_running, slave_SQL_running_state=$slave_SQL_running_state"
#		sleep 5
#		continue
#	fi

#	executed_gtid_set_no=`echo $executed_gtid_set|awk -F':' '{print $NF}'|awk -F'-' '{print $NF}'`

	if [[ $slave_sql_running == "No" ]];then
		if [ $last_errno -eq 0 ];then
			# 完成同步
			echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | playback complete, slave_sql_running=$slave_sql_running, last_errno=$last_errno, last_error=$last_error, replicate_wild_do_table=$replicate_wild_do_table, executed_gtid_set=$executed_gtid_set, mysql_end_gtid=$mysql_end_gtid, slave_SQL_running_state=$slave_SQL_running_state"
			break
		else
			echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | playback error, slave_sql_running=$slave_sql_running, last_errno=$last_errno, last_error=$last_error, replicate_wild_do_table=$replicate_wild_do_table, executed_gtid_set=$executed_gtid_set, mysql_end_gtid=$mysql_end_gtid, slave_SQL_running_state=$slave_SQL_running_state"
			exit -6
		fi
	fi

	echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | playing back, slave_sql_running=$slave_sql_running, last_errno=$last_errno, last_error=$last_error, replicate_wild_do_table=$replicate_wild_do_table, executed_gtid_set=$executed_gtid_set, mysql_end_gtid=$mysql_end_gtid, slave_SQL_running_state=$slave_SQL_running_state"
	echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | sleep 5s, do next check"
	sleep 5
done


$recovery_mysql_client -e "stop slave;"
if [ $? -ne 0 ];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | stop slave in temp mysql instance failed"
  exit -1
fi
$recovery_mysql_client -e "reset slave;"
if [ $? -ne 0 ];then
  echo "r[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | eset slave in temp mysql instance failed"
  exit -1
fi
$recovery_mysql_client -e "reset slave all;"
if [ $? -ne 0 ];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | reset slave all in temp mysql instance failed"
  exit -1
fi

/bin/mkdir -p $mysql_recovery_backup_temp_dir/ibd/

# 修改表名，然后加载到待恢复库
recovery_table_array=(${recovery_tables//,/ })
recovery_table_to_array=(${recovery_tables_to//,/ })
for((i=0;i<${#recovery_table_array[@]};i++))
do
	table=${recovery_table_array[i]}
	table_to=${recovery_table_to_array[i]}
	temp_table_db=`echo "$table_to" | cut -f 1 -d'.'`
	temp_table_name=`echo "$table_to" | cut -f 2 -d'.'`

	$recovery_mysql_client -e "rename table $table to $table_to;"
	if [ $? -ne 0 ];then
	  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | rename table $table to $table_to in temp mysql instance failed"
	  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | recovery $table to $table_to failed"
	  continue
	fi

	create_tmp_table=`$recovery_mysql_client -e "show create table $table_to;"`
	if [ $? -ne 0 ];then
	  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | show create table $table_to in temp mysql instance failed"
	  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | recovery $table to $table_to failed"
	  continue
	fi
	create_tmp_table_sql=`echo $create_tmp_table | sed "s/^$temp_table_name//"`

	$mysql_client -e "use $temp_table_db; $create_tmp_table_sql;"
	if [ $? -ne 0 ];then
	  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | $create_tmp_table in mysql instance failed"
	  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | recovery $table to $table_to failed"
	  continue
	fi

	$mysql_client -e "alter table $table_to discard tablespace;"

	# 锁表成只读
	$recovery_mysql_client -e "flush table $table_to for export;"

	# copy ibd文件
	# 这时候保证没有新的写入，把bak_b的ibd文件拷贝到待恢复实例对应的目录下，并修改文件权限
	temp_table_db=`echo "$table_to" | cut -f 1 -d'.'`
	temp_table_name=`echo "$table_to" | cut -f 2 -d'.'`

	scp $mysql_recovery_linux_user@$mysql_recovery_host:$mysql_recovery_data/$temp_table_db/$temp_table_name.ibd $mysql_recovery_backup_temp_dir/ibd/
	if [ $? -ne 0 ];then
	  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | scp $mysql_recovery_linux_user@$mysql_recovery_host:$mysql_recovery_data/$temp_table_db/$temp_table_name.ibd file to this server failed"
	  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | recovery $table to $table_to failed"
	  continue
	fi

	scp $mysql_recovery_backup_temp_dir/ibd/$temp_table_name.ibd $mysql_linux_user@$mysql_host:$mysql_data/$temp_table_db/
	if [ $? -ne 0 ];then
	  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | scp $temp_table_name.ibd file to $mysql_linux_user@$mysql_host:$mysql_data/$temp_table_db/ mysql failed"
	  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | recovery $table to $table_to failed"
	  continue
	fi

	mysql_server_stdout=`ssh $mysql_linux_user@$mysql_host "chown $mysql_linux_user.$mysql_linux_group $mysql_data/$temp_table_db/$temp_table_name.ibd"`
	if [ $? -ne 0 ];then
	  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | exec /bin/rm -fr $mysql_backup_temp_dir in mysql server $mysql_linux_user@$mysql_host failed"
	  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | recovery $table to $table_to failed"
	  echo "$mysql_server_stdout"
	  continue
	fi
	echo "$mysql_server_stdout"
	
	$recovery_mysql_client -e "unlock tables;"
	if [ $? -ne 0 ];then
	  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | unlock tables in temp mysql instance failed"
	  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | recovery $table to $table_to failed"
	  continue
	fi

	$mysql_client -e "alter table $table_to import tablespace;"
	if [ $? -ne 0 ];then
	  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | alter table $table_to import tablespace in mysql instance failed"
	  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | recovery $table to $table_to failed"
	  continue
	fi
done

rm -fr $mysql_recovery_backup_temp_dir

echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | recovery mysql $mysql_host:$mysql_port table $recovery_tables to $recovery_date completed"


