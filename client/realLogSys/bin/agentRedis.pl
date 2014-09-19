#!/usr/bin/perl
use strict;
use warnings;
use Config::Tiny;
use FindBin;
use lib "$FindBin::Bin/../lib/";
use redisControl;
use POSIX qw(strftime);
use Time::Local;
use File::Tail;
$| = 1;
main();

sub main {
    my $configFile = "$FindBin::Bin/../etc/config.ini";
    my $configNew  = Config::Tiny->new;
    my $config     = $configNew->read($configFile);

    #redis配置信息
    my $redisConfig = $config->{'redis'};
    my $rServer     = $redisConfig->{'server'};
    my $reconnect   = $redisConfig->{'reconnect'};
    my $every       = $redisConfig->{'every'};
    my $debug       = $redisConfig->{'debug'};
    my $rPassword   = $redisConfig->{'password'};

    #日志信息
    my $logConfig = $config->{'log_info'};
    my $name      = $logConfig->{'logFile'};
    my $logType   = $logConfig->{'logType'};
    my $ifconfig  = `ifconfig`;
    my $serverIp;
    $serverIp = $1
      if $ifconfig =~
      /eth0(?!:)[\s\S]+?inet[^:]+:((?:\d{1,3}\.){3}\d{1,3})/; #获取服务器IP
    my $file =
      File::Tail->new( name => $name, maxinterval => 60, adjustafter => 7 );
    my $r = Redis->new(
        server    => $rServer,
        reconnect => $reconnect,
        every     => $every,
        debug     => $debug,
        password  => $rPassword
    );
    my ($line);
    my $redisControl = redisControl->new();

    while ( defined( $line = $file->read ) ) {
        chomp($line);
        $line =~ s/password1?=(?:[^\&]+\&|[^\s]+)//g;
        if ( $line =~ /^.*?\[([^]]+)/ ) {
            my $logTamp = timeTamp($1);    #计算日期的时间戳
            $redisControl->logSetRedis( $r, $line, $logType, $serverIp,
                $logTamp );
        }

    }

}

sub timeTamp {
    my $str   = shift;
    my %month = (
        "Jan" => 1,
        "Feb" => 2,
        "Mar" => 3,
        "Apr" => 4,
        "May" => 5,
        "Jun" => 6,
        "Jul" => 7,
        "Aug" => 8,
        "Sep" => 9,
        "Oct" => 10,
        "Nov" => 11,
        "Dec" => 12
    );
    my ( $day, $mon, $year, $hour, $minute, $sec ) =
      ( split /\/|:/, $str )[ 0, 1, 2, 3, 4, 5 ];
    my $format_date = "$year-$month{$mon}-$day $hour:$minute:$sec";
    my $timetemp =
      timelocal( $sec, $minute, $hour, $day, $month{$mon} - 1, $year );
    return $timetemp;

}
