package myLogApp;
use Dancer ':syntax';
use Dancer::Plugin::Redis;
use utf8;
use Data::Dumper;
our $VERSION = '0.1';

get '/' => sub {
    template 'index';
};

get '/redis' =>  sub{
   # template 'redis', { tables => [redis->smembers('20140823')]};
    #template 'redis';
    #print Dumper \[redis->smembers('20140823')];
    my @members = redis->smembers('20140823');
    print $_,"\n" for @members;
};

true;
