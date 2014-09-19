1.主要实现功能如下：
  可以查询当天、非当天日志,web方式查询，直接进入目录bin/app.pl 默认端口为3000
  当天主要存储在redis中；
  非当天存储形式为文本方式，存放历史服务器
2.redis涉及的键值如下：
--------------------------------------------------------------------
key	        value	                类型	        说明
searchQueue	mailname	        list	        存放队列
mailname	待查询的IP、account信息	set	        查询信息
seal	        number	                string	        进程数累加
logsystem:user        mailname                hash            存放用户登陆帐号
--------------------------------------------------------------------
3.支持最大5个查询任务同时进行（可以自行调整）seal值
4.首次登陆需要在logsystem:user插入记录，密码保存为md5方式
5.程序主要分为client、server
6.需要安装的模块Config::Tiny Time::Local File:Tail Mail::Sender Parallel::ForkManager
