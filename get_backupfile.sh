#!/bin/bash

cd /tmp/
# 获取对应恢复时间点之前最近的一次全量备份
source ./recovery.config

echo "[`date +%Y%m%d%H%M%S`]  | line_number: "$LINENO" |start find xbackup file before $recovery_date"

# 需要恢复到的时间点
if [[ $recovery_date == '' ]];then
  echo "[`date +%Y%m%d%H%M%S`]  | line_number: "$LINENO" |recovery date is not be null"
  exit -6
fi
if [ ! -f $backup_file ];then
  echo "[`date +%Y%m%d%H%M%S`]  | line_number: "$LINENO" |backup file is not find"
  exit -6
fi
recovery_date_timestamp=`date +%s -d "$recovery_date"`
if [ $? -ne 0 ];then
  echo "[`date +%Y%m%d%H%M%S`]  | line_number: "$LINENO" |recovery date must be format to 2022-12-09 10:45:00"
  exit -6
fi
recovery_date_compact=`date +%Y%m%d%H%M%S -d @$recovery_date_timestamp`

if [[ $recovery_tables == '' ]];then
  echo "[`date +%Y%m%d%H%M%S`]  | line_number: "$LINENO" |recovery table is not be null"
  exit -6
fi

# 寻找对应的全备文件
echo "[`date +%Y%m%d%H%M%S`]  | line_number: "$LINENO" |find first mysql data innobackupex backup file before $recovery_date"
cd $mysql_data_backup_dir
if [ $? -ne 0 ];then
  echo "[`date +%Y%m%d%H%M%S`]  | line_number: "$LINENO" |Backup dir is not existed"
  exit -1
fi
backup_file=''
for f in `ls -1t|egrep "*\.$backup_file_suffix"`;
do 
  if [ ! -s $f ];then
    echo "[`date +%Y%m%d%H%M%S`]  | line_number: "$LINENO" |$f is empty, deleted"
    rm -fr $f
    continue
  fi
  file_create_time=`echo $f | egrep -o '[0-9]{14}'`
  if [[ $file_create_time == '' ]];then
    continue
  fi
  if [ $file_create_time -lt $recovery_date_compact ];then
    backup_file=$f
    break
  fi
done
echo "[`date +%Y%m%d%H%M%S`]  | line_number: "$LINENO" |find xbackup file before $recovery_date completed"
echo "backup_file=$backup_file"