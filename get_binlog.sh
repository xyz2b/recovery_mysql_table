#!/bin/bash
cd /tmp/
# 去待恢复mysql实例上，找到结束binlog以及结束位置gtid信息，然后将所有有关的binlog传送到本地

source ./recovery.config
source ./temp.config

echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | start to get binlog in $mysql_host:$mysql_port mysql instance"

if [ ! -d "$mysql_recovery_backup_temp_dir" ];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | $mysql_recovery_backup_temp_dir dir is not exited"
  exit -1
fi
# 寻找对应的binlog文件
# 第一个更新时间大于恢复时间点的binlog
echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | find first mysql binlog file after $recovery_date"
cd $mysql_logs
if [ $? -ne 0 ];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | Mysql binlog dir is not existed"
  rm -fr $mysql_backup_temp_dir
  exit -1
fi
mysql_bin_log_end_files=`find ./ -type f -regex "\./$mysql_bin_log_file_prefix\..*[0-9]$" -newermt "$recovery_date"|grep -v index`
if [[ $mysql_bin_log_end_files == '' ]];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | Can't find any mysql binlog file after $recovery_date"
  rm -fr $mysql_backup_temp_dir
  exit -2
fi
mysql_bin_log_end_file=`echo "$mysql_bin_log_end_files" | xargs ls -1tr| head -1 | xargs basename`
mysql_bin_log_end_file_modify_time=`date '+%Y-%m-%d %H:%M:%S' -r $mysql_bin_log_end_file`
mysql_bin_log_end_file_modify_timestamp=`date +%s -d "$mysql_bin_log_end_file_modify_time"`
mysql_bin_log_start_file_modify_time=`date '+%Y-%m-%d %H:%M:%S' -r $mysql_bin_log_start_file`
mysql_bin_log_start_file_modify_timestamp=`date +%s -d "$mysql_bin_log_start_file_modify_time"`
echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | find first mysql binlog file after $recovery_date: $mysql_bin_log_end_file"

# 在这个binlog中，以恢复时间点为stop-datetime，找到恢复时间点的gtid
$mysql_bin/mysqlbinlog --stop-datetime="$recovery_date" $mysql_bin_log_end_file > $mysql_backup_temp_dir/$mysql_bin_log_end_file.list
if [ $? -ne 0 ];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | Parse $mysql_bin_log_end_file failed"
  rm -fr $mysql_backup_temp_dir
  exit -1
fi

mysql_start_gtid_no=`echo "$mysql_start_gtid"|awk -F"-" '{print $6}'`
mysql_uuid=`echo "$mysql_start_gtid"|awk -F':' '{print $1}'`
# get_binlog.sh，需要传入gtid，传入的gtid，从init_temp_mysql_instance.sh中返回mysql_start_gtid即可
# 然后拿到uuid，然后直接倒序匹配最后一行，判断是否为空，不为空，然后再匹配一下GTID_NEXT，如果有GTID_NEXT就是单事务的，直接返回，如果没有GTID_NEXT，就是一段，需要匹配到最后的序号，拼上UUID返回
# 避免根据回档时间点找到的是一个空的binlog
# binlog开头一定有 Previous-GTIDs，指示前一个binlog的gtid范围，1e54ba88-27ee-11eb-994b-525400b3e8d5:1-2163637
# 正常事务的gtid：GTID_NEXT= '1e54ba88-27ee-11eb-994b-525400b3e8d5:2163638'
mysql_end_gtid_line=`tac $mysql_backup_temp_dir/$mysql_bin_log_end_file.list|grep "$mysql_uuid"|head -1`
is_gtid_next=`echo "$mysql_end_gtid_line"|grep "GTID_NEXT"|wc -l`
# Previous-GTIDs
if [ $is_gtid_next -eq 0 ];then
	mysql_revious_gtids=`echo "$mysql_end_gtid_line"|awk '{print $2}'`
	mysql_end_gtid_no=`echo "$mysql_revious_gtids"|awk -F"-" '{print $6}'`
	mysql_end_gtid=`echo "$mysql_uuid:$mysql_end_gtid_no"`
else	# GTID_NEXT
	mysql_end_gtid=`echo "$mysql_end_gtid_line"|cut -f 2 -d"'"`
	mysql_end_gtid_no=`echo "$mysql_end_gtid"|awk -F":" '{print $2}'`
fi
if [[ $mysql_end_gtid == '' ]];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | Can't find end log gtid before $recovery_date in $mysql_bin_log_end_file"
  rm -fr $mysql_backup_temp_dir
  exit -2
fi
if [ $mysql_end_gtid_no -lt $mysql_start_gtid_no ];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | find end log gtid: $mysql_end_gtid in $mysql_bin_log_end_file is less than start log gtid: $mysql_start_gtid in xbackup file"
  rm -fr $mysql_backup_temp_dir
  exit -2
fi
echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | find first mysql binlog item before $recovery_date in $mysql_bin_log_end_file, this item gtid: $mysql_end_gtid"

rm -fr $mysql_backup_temp_dir/$mysql_bin_log_end_file.list



# 找到从全量备份中的binlog文件开始到上面找到的binlog文件结束，将这些binlog转成relaylog，并将其复制到临时库的mysql logs目录下
cd $mysql_backup_temp_dir
binlog_temp_dir=binlog_${mysql_bin_log_start_file}_${mysql_bin_log_end_file}
mkdir -p $binlog_temp_dir

# 从mysql_bin_log_start_file到mysql_bin_log_end_file的binlog文件copy到临时文件夹中
cd $mysql_logs
echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" |find all binlog from $mysql_bin_log_start_file(mtime: $mysql_bin_log_start_file_modify_time-$mysql_bin_log_start_file_modify_timestamp) to $mysql_bin_log_end_file(mtime: $mysql_bin_log_end_file_modify_time-$mysql_bin_log_start_file_modify_timestamp)"
((start_timestamp = mysql_bin_log_start_file_modify_timestamp - 1))
((end_time_timestamp = mysql_bin_log_end_file_modify_timestamp + 1))
start_time=`date "+%Y-%m-%d %H:%M:%S" -d @$start_timestamp`
end_time=`date "+%Y-%m-%d %H:%M:%S" -d @$end_time_timestamp`
# ctime和mtime是同时变化的，所以这里有个bug，如果mysql_bin_log_end_file还在更新，可能就会漏掉
mysql_bin_log_files=`find ./ -type f -regex "\./$mysql_bin_log_file_prefix\..*[0-9]$" -newermt "$start_time" ! -newermt "$end_time"`
if [[ $mysql_bin_log_files == '' ]];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | Can't find any binlogs from $mysql_bin_log_start_file to $mysql_bin_log_end_file"
  exit -2
fi
echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | find all binlog from $mysql_bin_log_start_file to $mysql_bin_log_end_file: $mysql_bin_log_files"

echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | rename all binlog to relaylog, package them"
cp -fr $mysql_bin_log_files $mysql_backup_temp_dir/$binlog_temp_dir/
# 避免上面的bug，漏掉mysql_bin_log_end_file，所以这里再复制一次
cp -fr $mysql_bin_log_end_file $mysql_backup_temp_dir/$binlog_temp_dir/
cd $mysql_backup_temp_dir/$binlog_temp_dir/
rename $mysql_bin_log_file_prefix $mysql_relay_log_file_prefix $mysql_bin_log_file_prefix*
ls ./$mysql_relay_log_file_prefix.* > $mysql_relay_log_file_prefix.index
tar zcf $mysql_backup_temp_dir/$binlog_temp_dir.tar.gz *
if [ $? -ne 0 ];then
  echo "package binlog files from $mysql_bin_log_start_file to $mysql_bin_log_end_file failed"
  rm -fr $binlog_temp_dir
  rm -fr $binlog_temp_dir.tar.gz
  exit -1
fi
rm -fr $mysql_backup_temp_dir/$binlog_temp_dir

echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | get binlog in $mysql_host:$mysql_port mysql instance completed"

echo "binlog_package=$binlog_temp_dir.tar.gz"
echo "mysql_end_gtid=$mysql_end_gtid"

