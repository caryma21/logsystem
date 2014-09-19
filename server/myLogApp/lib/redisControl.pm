package redisControl;
use strict;
use warnings;
use Redis;
use Data::Dumper;

use POSIX qw(strftime);

sub new {
    my $self  = {};
    my $class = shift;
    bless $self;
    return $self;
}

# 插入数值到redis
sub insertHKey {
    my $self = shift;
    my ( $r, $sIp, $cIp, $date, $timestamp, $count, $seal, $type, $level ) = @_;
    $r->hmset(
        'blackList',    #设置key
        "$sIp:$cIp:date"      => $date,         #设置日期
        "$sIp:$cIp:timestamp" => $timestamp,    #设置unix时间戳
        "$sIp:$cIp:count"     => $count,        #插入总次数
        "$sIp:$cIp:seal"      => $seal,         #是否被封
        "$sIp:$cIp:type"      => $type,         #IP或者CALL类型
        "$sIp:$cIp:level"     => $level         #哪种级别被封
    );
}

sub insertKey {
    my $self = shift;
    my ( $r, $sIp, $cIp, $date, $timestamp, $count, $seal, $type, $level ) = @_;
    my $minDate = strftime( "%Y%m%d%H%M", localtime(time) );
    my $houDate = strftime( "%Y%m%d%H",   localtime(time) );
    $r->sadd( $date           => "$sIp:$cIp" );    #按天来存储IP信息
    $r->sadd( $minDate        => "$sIp:$cIp" );    #按分钟存储IP信息
    $r->sadd( $houDate        => "$sIp:$cIp" );
    $r->sadd( "$sIp:$date"    => "$sIp:$cIp" );
    $r->sadd( "$sIp:$minDate" => "$sIp:$cIp" );
    $r->sadd( "$sIp:$houDate" => "$sIp:$cIp" );
    $r->set( "$sIp:$cIp:$date:count"     => $count );     #详细按天的数据
    $r->set( "$sIp:$cIp:$date:seal"      => $seal );
    $r->set( "$sIp:$cIp:$date:type"      => $type );
    $r->set( "$sIp:$cIp:$date:timestamp" => $timestamp );
    $r->set( "$sIp:$cIp:$date:level"     => $level );
    $r->set( "$sIp:$cIp:$minDate:count" => $count );   #详细按分钟的数据
    $r->set( "$sIp:$cIp:$minDate:seal"  => $seal );
    $r->set( "$sIp:$cIp:$minDate:type"  => $type );
    $r->set( "$sIp:$cIp:$minDate:timestamp" => $timestamp );
    $r->set( "$sIp:$cIp:$minDate:level"     => $level );
    $r->set( "$sIp:$cIp:$houDate:count" => $count );   #详细按小时的数据
    $r->set( "$sIp:$cIp:$houDate:seal"  => $seal );
    $r->set( "$sIp:$cIp:$houDate:type"  => $type );
    $r->set( "$sIp:$cIp:$houDate:timestamp" => $timestamp );
    $r->set( "$sIp:$cIp:$houDate:level"     => $level );

}

#IP每10分钟抽出最新
sub ipCountMin {
    my $self = shift;
    my ( $r, $data, $end ) = @_;

    #my $llen = $r->llen($data);

    my ($ser) = ( split /:/, $data )[0];
    my $list = $r->lrange( $data, 0, $end );

    return $list;
}

#IP排行榜统计
sub ipTop {
    my $self = shift;
    my ( $r, $date ) = @_;
    my $top100Ip;
    my @ips = $r->sort( $date, "by", "*:$date:count", "limit", 0, 100, "desc" );
    for my $value (@ips) {
        push @{ $top100Ip->{$value} },
          $r->mget(
            "$value:$date:count", "$value:$date:level",
            "$value:$date:type",  "$value:$date:seal",
            "$value:$date:timestamp"
          );
    }
    return $top100Ip;
}

#刷新每分钟IP的次数
sub realTimeDateIp {
    my $self = shift;
    my $sData;
    my ( $r, $sec ) = @_;
    my $startTime = strftime( "%Y%m%d%H%M", localtime( time() - $sec ) );

    # print $startTime;
    my $dataFrom =
      $r->smembers("$startTime");    #统计服务器的各个时间段IP成员

    unless (@$dataFrom) {            #如果IP没有被封
        my $sIp;
        my $ifconfig = `ifconfig`;
        $sIp = $1
          if $ifconfig =~
          /eth0(?!:)[\s\S]+?inet[^:]+:((?:\d{1,3}\.){3}\d{1,3})/
          ;                          #获取服务器IP
        $sData->{$sIp} = 0;
    }
    for (@$dataFrom) {
        my ( $sIp, $cIp ) = split /:/;
        $sData->{$sIp}++;
    }
    for my $sIp ( keys %$sData ) {
        $r->lpush( "$sIp:min" => $sData->{$sIp} )
          ;                          #根据IP分别统计每分钟的次数
    }
}

sub realHourDateIp {
    my $self = shift;
    my $sData;
    my ( $r, $sec ) = @_;
    my $startTime = strftime( "%Y%m%d%H", localtime( time() - $sec ) );
    my $dataFrom =
      $r->smembers("$startTime");    #统计服务器的各个时间段IP成员
    unless ($dataFrom) {             #如果IP没有被封
        my $sIp;
        my $ifconfig = `ifconfig`;
        $sIp = $1
          if $ifconfig =~
          /eth0(?!:)[\s\S]+?inet[^:]+:((?:\d{1,3}\.){3}\d{1,3})/
          ;                          #获取服务器IP
        $sData->{$sIp} = 0;
    }
    for (@$dataFrom) {
        my ( $sIp, $cIp ) = split /:/;
        $sData->{$sIp}++;
    }
    for my $sIp ( keys %$sData ) {
        $r->lpush( "$sIp:hour" => $sData->{$sIp} )
          ;                          #根据IP分别统计每小时的次数
    }
}

#出列
sub taskPop {
    my $self = shift;
    my ( $r, $queueName ) = @_;
    my $data;
    return 0 if $r->get('seal') > 4;    #进程大于4则退出
    my $userTask = $r->lpop($queueName);
    if ($userTask) {
        my $info = $r->smembers($userTask); #获取队列名里的帐号IP信息
        for (@$info) {
            my ( $date, $ipAcc, $type ) = split /:/;
            push @{ $data->{"$userTask:$date:$type"} }, $ipAcc;    #组成ref

        }
        $r->del($userTask) or warn "key doesn't exist";    #删除成员信息
        $r->incr('seal');                                  #进程数添加1
    }
    else {
        return 0;
    }
    return $data;
}

sub delKey {
    my $self = shift;
    my ( $r, $key ) = @_;
    if ( $r->del($key) ) {
        return 1;
    }
    else {
        return 0;
    }
}

1;
