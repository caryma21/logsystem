1.redis涉及的键值如下：
--------------------------------------------------------------------
key	        value	                类型	        说明
searchQueue	mailname	        list	        存放队列
mailname	待查询的IP、account信息	set	        查询信息
seal	        number	                string	        进程数累加
logsystem:user        mailname                hash            存放用户登陆帐号
--------------------------------------------------------------------
2.支持最大5个查询任务同时进行（可以自行调整）seal值
3.首次登陆需要在logsystem:user插入记录，密码保存为md5方式
4.程序主要分为client、server
5.需要安装的模块Config::Tiny Time::Local File:Tail
