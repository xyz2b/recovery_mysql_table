前置：存放备份文件的节点、临时回档mysql节点、待回档源mysql节点，需要和执行该程序所在的节点做SSH免密登录

备份文件格式backup_`date +%Y%m%d%H%M%S`.xbstream，中间需要带上日期，以备份文件名称中的日期来寻找对应的全备文件

备份文件需要使用innobackupex物理备份，是否使用压缩，通过recovery.config中的backup_use_compress参数控制

需要通过recovery.config来设置回档时间和回档表，同时需要设置回档mysql实例和源mysql实例的一些参数

通过sh start.sh启动
