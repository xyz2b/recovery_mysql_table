#!/bin/bash

cd /tmp/
# 初始化临时实例，停止进程，清理data和logs目录，然后将全备恢复出来

source ./recovery.config
source ./temp.config

echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | init temp mysql $mysql_recovery_host:$mysql_recovery_port instance"

echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | clear temp mysql $mysql_recovery_host:$mysql_recovery_port instance"


# 解压备份文件
if [ ! -d "$mysql_recovery_backup_temp_dir" ];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | $mysql_recovery_backup_temp_dir dir is not exited"
  exit -1
fi
cd $mysql_recovery_backup_temp_dir
backup_file_dir=`echo "$backup_file"|cut -f 1 -d'.'`
mkdir -p $backup_file_dir

echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | use xbstream to decompress xbackup file: $backup_file to $backup_file_dir"
$innobackupex_bin/xbstream -x < $backup_file -C $backup_file_dir/
if [ $? -ne 0 ];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | xbstream $backup_file failed"
  rm -fr $mysql_recovery_backup_temp_dir
  exit -1
fi
cd $backup_file_dir/

if [ $backup_use_compress -eq 1 ];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | innobackupex use compress, use qpress to decompress file"
  for f in `find ./ -iname "*\.qp"`;
  do 
    $qpress_bin/qpress -dT2 $f $(dirname $f) 
    if [ $? -ne 0 ];then
      echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | qpress $backup_file failed"
      rm -fr $mysql_recovery_backup_temp_dir
      exit -1
    fi
    rm -fr $f;
  done
fi

if [ ! -f xtrabackup_binlog_info ];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | $backup_file is not include xtrabackup_binlog_info file"
  rm -fr $mysql_recovery_backup_temp_dir
  exit -3
fi
mysql_bin_log_start_file=`cat xtrabackup_binlog_info|head -1|cut -f 1`
mysql_start_log_pos=`cat xtrabackup_binlog_info|head -1|cut -f 2`
mysql_start_gtid=`cat xtrabackup_binlog_info|cut -f 3|xargs|egrep -o "${server_uuid}:[0-9]{1,}-[0-9]{1,}"`
mysql_bin_log_start_file_modify_time=`date '+%Y-%m-%d %H:%M:%S' -r $mysql_bin_log_start_file`
mysql_bin_log_start_file_modify_timestamp=`date +%s -d "%mysql_bin_log_start_file_modify_time"`
echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | in mysql data innobackupex backup file $backup_file, mysql binglog file: mysql_bin_log_start_file; pos: $mysql_start_log_pos; gtid: $mysql_start_gtid"


# 使用物理备份恢复数据到临时库
echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | restore mysql backup data to temp mysql instance"
cd $mysql_recovery_backup_temp_dir
echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | innobackupex prepare step"
innobackupex --apply-log $backup_file_dir
if [ $? -ne 0 ];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | innobackupex apply-log prepare $backup_file_dir failed"
  rm -fr $mysql_recovery_backup_temp_dir
  exit -1
fi
echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | innobackupex copy data step"
innobackupex --defaults-file=$mysql_recovery_conf  --copy-back $backup_file_dir
if [ $? -ne 0 ];then
  echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | innobackupex mov $backup_file_dir data to mysql failed"
  rm -fr $mysql_recovery_backup_temp_dir
  exit -1
fi
chown -R "$mysql_recovery_linux_user:$mysql_recovery_linux_group" $mysql_recovery_data
chown -R "$mysql_recovery_linux_user:$mysql_recovery_linux_group" $mysql_recovery_logs
rm -fr $mysql_recovery_backup_temp_dir

echo "[`date +%Y%m%d%H%M%S`] | fileanme: "$BASH_SOURCE" | line_number: "$LINENO" | init temp mysql $mysql_recovery_host:$mysql_recovery_port completed"

echo "mysql_start_gtid=$mysql_start_gtid"
echo "mysql_start_log_pos=$mysql_start_log_pos"
echo "mysql_bin_log_start_file=$mysql_bin_log_start_file"