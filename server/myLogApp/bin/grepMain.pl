#!/usr/bin/perl
use strict;
use warnings;
use Parallel::ForkManager;
use File::Find;
use FindBin;
use POSIX qw(strftime);
use Config::Tiny;
use lib "$FindBin::Bin/../lib/";
use redisControl;
use Data::Dumper;
use Mail::Sender;
my $configFile = "$FindBin::Bin/../etc/config.ini";
my $configNew  = Config::Tiny->new;
my $config     = $configNew->read($configFile);

#redis 配置信息读取
my $redisConfig = $config->{'redis'};
my $rServer     = $redisConfig->{'server'};
my $reconnect   = $redisConfig->{'reconnect'};
my $every       = $redisConfig->{'every'};
my $debug       = $redisConfig->{'debug'};
my $rPassword   = $redisConfig->{'password'};

#日志相关信息读取
my $logConfig  = $config->{'loginfo'};
my $logPath    = $logConfig->{'path'};
my $myLogName  = $logConfig->{'my_log_name'};
my $wwwLogName = $logConfig->{'www_log_name'};
my $output     = $logConfig->{'output'};
my $logKey     = $logConfig->{'logKeyName'};

#mail相关信息读取
my $mailConfig   = $config->{'mail'};
my $mailUser     = $mailConfig->{'user'};
my $mailSmtp     = $mailConfig->{'smtp'};
my $mailPassword = $mailConfig->{'password'};
my $mailCc       = $mailConfig->{'cc'};
my $mailFrom     = $mailConfig->{'mailfrom'};
my ( $uMail, $date, $type, $ip, $account, @files, $logFile );
my $pm = Parallel::ForkManager->new(3);    #开启3个进程
my $r  = Redis->new(
    server    => $rServer,
    reconnect => $reconnect,
    every     => $every,
    debug     => $debug,
    password  => $rPassword
);
my $redisControl = redisControl->new();
my $data = redisControl->taskPop( $r, 'searchQueue' ); #获取队列中的任务
my $nowDate = strftime( "%Y%m%d", localtime(time) );
my $nowSearchList =
  [ map { sprintf "%02d", $_ } 0 .. strftime( "%H", localtime(time) ) ]
  ;    #推算之前的日志并且format

if ($data) {

    for my $dateType ( keys %$data ) {    #提取日期和所查日志类型
        ( $uMail, $date, $type ) = split /:/, $dateType;
        for ( @{ $data->{$dateType} } ) {

            if (/(?:\d{1,3}\.){3}\d{1,3}/) {
                $ip->{$_}++;
            }
            else {
                $account->{$_}++;
            }
        }
    }

    if ( $date =~ /$nowDate/ ) {
        todayFind( $logPath, $output, $ip, $account, $nowSearchList, $logKey );
    }
    else {
        yesterdayFind( $logPath, $output, $ip, $account );
    }

    #查询当天日志
    sub todayFind {
        my ( $logPath, $output, $ip, $account, $nowSearchList, $logKey ) = @_;
        my $pm = Parallel::ForkManager->new(2); 
        open IP, ">$output/${date}for${type}toIp.txt"      or die "$!";
        open AC, ">$output/${date}for${type}toAccount.txt" or die "$!";
        for my $day (@$nowSearchList) {
            $pm->start and next;
            my $dataLog = $r->hkeys("$logKey:${date}${day}:${type}");
            for (@$dataLog) {

                if (/.*?(?:login_account|u)=([^&]+)/i) {    #帐号信息

                    #提取IP帐号信息，与之前的hash去匹配。

                    print AC "$_\n" if $account->{$1};
                }
                if (/^((?:\d{1,3}\.){3}\d{1,3})/) {         #IP信息
                    print IP "$_\n" if $ip->{$1};
                }

            }
            $pm->finish;
        }
        $pm->wait_all_children;

    }

    #查询非当天的日志
    sub yesterdayFind {
        my ( $logPath, $output, $ip, $account ) = @_;
        find( \&myLogFind, $logPath );    #搜索所要寻找的LOG文件
        open IP, ">$output/${date}for${type}toIp.txt"      or die "$!";
        open AC, ">$output/${date}for${type}toAccount.txt" or die "$!";
        for my $file (@files) {
            print $file , "\n";
            $pm->start and next;
            open FH, $file or die "$!";
            while (<FH>) {
                if (/.*?(?:login|u)=([^&]+)/i) {    #帐号信息

                    #提取IP帐号信息，与之前的hash去匹配。

                    print AC "$_\n" if $account->{$1};
                }
                if (/^((?:\d{1,3}\.){3}\d{1,3})/) {         #IP信息
                    print IP "$_\n" if $ip->{$1};
                }
            }
            $pm->finish;
        }
        $pm->wait_all_children;
    }

    #发送邮件
    my $subject = "${date}日志查询完毕";
    my $msg     = "您好！日志在附件中\n\r谢谢！";
    if ( -f "$output/${date}for${type}toIp.txt" and !-z _ )
    {    #判断文件是否为空
        $logFile = "$output/${date}for${type}toIp.txt";
    }
    elsif ( -f "$output/${date}for${type}toAccount.txt" and !-z _ ) {
        $logFile = "$output/${date}for${type}toAccount.txt";
    }
    else {
        $msg     = "您好！所查询信息在日志中不存在\n\r谢谢！";
        $logFile = "$output/undef.txt";
    }
    my $size = ( stat($logFile) )[7] / 1024 / 1024;
    if ( $size > 50 ) {
        my $msg =
"您好！日志大于50MB，请在path\n\r谢谢！";
        $logFile = "$output/undef.txt";
    }
    send_mail(
        $mailSmtp, $mailFrom, $mailUser, $mailPassword, $uMail,
        $subject,  $msg,      $mailCc,   $logFile
    );
    my $r  = Redis->new(
    server    => $rServer,
    reconnect => $reconnect,
    every     => $every,
    debug     => $debug,
    password  => $rPassword
);
    $r->decr('seal');    #邮件发送完毕，进程结束，较少一个进程
}
else {
    exit 0;
}

sub myLogFind {
    if ( -f $_ ) {
        if ( $type =~ /my/ ) {    #判断my/www日志类型
            push @files, $File::Find::name if /${myLogName}_$date/;
        }
        else {
            push @files, $File::Find::name if /${wwwLogName}_$date/;
        }

    }
}

sub send_mail {
    my (
        $smtp,    $mail_from, $user, $passwd, $mail_to,
        $subject, $msg,       $cc,   $logFile
    ) = @_;
    open my $DEBUG, "> mail.log" or die "Can't open the debug      file:$!\n";
    my $sender = new Mail::Sender {
        ctype    => 'text/plain; charset=utf-8',
        encoding => 'utf-8',
    };
    $sender->MailFile(
        {
            smtp        => $smtp,
            from        => $mail_from,
            auth        => 'LOGIN',
            TLS_allowed => '0',
            authid      => $user,
            authpwd     => $passwd,
            to          => $mail_to,
            bcc         => $cc,
            subject     => $subject,
            msg         => $msg,
            file        => $logFile,
            debug       => $DEBUG
        }
    );
}
