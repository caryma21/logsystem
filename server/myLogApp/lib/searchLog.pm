package searchLog;
use Dancer ':syntax';
use Dancer::Plugin::Redis;
use utf8;
use Data::Dumper;
use Digest::MD5 qw(md5 md5_hex md5_base64);
$| = 1;

get '/login' => sub {

    template 'login' => { table => 'login' };

};

post '/login' => sub {
    if ( redis->hexists( 'logsystem:user',params->{username})
        && md5_hex( params->{password} ) eq
        redis->hget( 'logsystem:user', params->{username} )
        )
    {
        session user => params->{username};
        redirect params->{path};
    }
    else {
    
        redirect '/login';
    }
};

get '/logout' => sub {
    session->destroy;
    redirect '/login';
};
prefix '/search';
get '/' => sub {
    if ( session('user') ) {

        template 'search' => { logout =>
'<a href="/logout" title="Close <% session.user%>" session>Logout</a>'
        };

    }
    else {
        template 'search' =>
          { table => '<a href="/login" style="color: red">Please Login!</a>' };
    }
};
my ( $info, $date );
post '/' => sub {
    if ( session('user') ) {
        my $user = session('user');

        my ( $info, $date, $type );
        $info = params->{info};
        $date = params->{date};
        $type = params->{type};
        $date = $1.$2.$3 if $date=~/(\d+)-(\d+)-(\d+)/;  
        my @infos = split /\n/, $info;

        if (   length scalar @infos != 0
            && length $date != 0
            && length $type != 0 )
        {    #信息不为空，日期不为空
            $date =~ s/\s*//g;
            for (@infos) {
                next if /^\s*[\r\n]*$/;    #清除空号
                s/\s*//g;                  #替换空字符
                redis->sadd( $user => "$date:$_:$type" );
                ; #数据入库，格式：登陆人员账号，查询帐号/IP，查询日期
            }
            my $qLen = redis->llen("searchQueue");
            if ( $qLen != 0 ) {    #判断队列中是否有重复的任务
                my @arr = redis->lrange( "searchQueue", 0, $qLen );
                for (@arr) {
                    return "已在队列中，请不要重复提交！.<a href='http://14.18.204.157:3000/search'>点击返回</a>"
                      if /$user/;
                }
            }
            return "提交成功!查询完之后会邮件通知$user.<a href='http://14.18.204.157:3000/search'>点击返回</a>"
              if redis->rpush( "searchQueue", $user );
            redirect '/search/output';
        }
        else {
            return "信息不完整";
        }
    }
    else {
        template 'output' =>
          { table => '<a href="/login" style="color: red">Please Login!</a>' };
    }

};
get '/output' => sub {
    if ( session('user') ) {

        template 'output' => { info => '' };
    }
    else {
        template 'output' =>
          { table => '<a href="/login" style="color: #fff">Please Login!</a>' };
    }
};

1;