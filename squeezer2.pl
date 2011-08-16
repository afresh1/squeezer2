#!/usr/bin/perl
# $AFresh1: squeezer2.pl,v 1.9 2011/08/16 01:01:48 andrew Exp $
#######################################################################
# squeezer2.pl *** SQUid optimiZER
#                  Rewrite of squeezer.pl by
#                    Maciej Kozinski <maciej_kozinski@wp.pl>
#                  http://strony.wp.pl/wp/maciej_kozinski/squeezer.html
#
#                  The idea for this came from Maciej's script, although
#                  I rewrote most of it and shamelessly stole bits and
#                  pieces of his script to use. Any errors in this
#                  version are totally my mistake and should be reported
#                  to me. However I don't guarantee that it will work
#                  right, so if it is completely screwed up and crashes
#                  your computer or starts a global thermonuclear war, I
#                  take no responsibility.
#
#                  I tried to write it so that it doesn't require any
#                  additional modules so that it could run more easily
#                  chrooted if you so choose. I will someday hopefully put
#                  back the feature where it will run from the web server
#                  and generate the reports on the fly.  Although for me
#                  that doesn't work well as my logs are generally 200 megs
#                  a day and it takes quite a while to generate the report
#                  so I just have it run from cron (actually as a part of
#                  /etc/daily on my OpenBSD box) Then I run it and generate
#                  current reports from the command line if I need to.
#
#                  Here are the lines I have in my /etc/daily. It generates
#                  a daily report and then a report of all the logs that I
#                  have.  I generally keep 7 days of logs.
#
#                  echo ""
#                  echo "Rotating squid logs"
#                  /usr/local/sbin/squid -k rotate
#
#                  echo ""
#                  echo "Generating squid usage reports"
#                  /usr/local/bin/squeezer2.pl /var/squid/logs/access.log.0 >/var/www/htdocs/squeezer/SQ`date +%Y%m%d`.html
#                  /usr/local/bin/squeezer2.pl >/var/www/htdocs/squeezer/all.html
#
#
#
# 02/19/2003 01:16AM *** Andrew Fresh <andrew@afresh1.com>
#
# 03/14/2003 12:49AM *** After working on this for almost a month, on
#                    and off when I had time, it is finally about right
#                    I think. If you have any questions, please let me
#                    know, I need to work on my commenting so let me know
#                    where I am sucking at it.
#
# 03/19/2003 08:47PM *** replacing the by_regex section with the stats
#                    from squij.  squij is kewlness!  written by Mark
#                    Nottingham, it shows awesome stats, and using
#                    that, now so does this script!
#                    You can find Mark at http://www.mnot.net/
#
# 04/14/2011 20:53   *** Rewrite again to do some cleanup and make it so
#                    we can initialize stats holders.  Unfortunately, it
#                    is now like half as fast!  This fixed the problem with
#                    uninitialized variables, so the speed fix is not yet as
#                    important.
#
#######################################################################
use strict;
use warnings;

# these are the variables that need to be changed if your configuration is
# different from mine.

our $VERSION = '0.7';
my $conf_file = '/etc/squid/squid.conf';
my $conf      = Read_Conf($conf_file);
my $log_path  = $conf->{log} || '/var/squid/logs/access.log';

# Here you set which information you want to see. The more you turn on, the
# longer it takes, but you get better kewler info These I have enabled and are
# what I find to be the most useful
use constant {

    # The most useful options should likely be 1 or enabled
    SHOW_HIT_STATS        => 1,
    SHOW_HOUR_STATS       => 1,
    SHOW_SIZE_STATS       => 1,
    SHOW_DENIED_BY_URL    => 1,
    SHOW_DENIED_BY_CLIENT => 1,
    SHOW_REGEX_STATS      => 1,    # from Squij, can be slow tho

    # These are enabled but are only useful if you have peers.
    # If not, you can disable for speed.
    SHOW_SERVER_STATS => 1,
    SHOW_FETCH_STATS  => 1,

    # These I have disabled by default
    SHOW_CLIENT_STATS     => 0,    # many clients make the page very long
    SHOW_WEB_SERVER_STATS => 0,    # many URLs make the page very long
    SHOW_STATUS_STATS     => 0,    # shown with less detail in FETCH_STATS
    SHOW_EXT_STATS        => 0,
    SHOW_TYPE_STATS       => 0,
};

#
# Lower the priority to lower CPU consumption - the squid is the no 1!
#
use constant PRIO_PROCESS => 0;
setpriority( PRIO_PROCESS, $$, 19 );

if ( -t STDIN && !@ARGV ) {
    @ARGV = glob( $log_path . '*' );
    die "No log to process!\n" unless @ARGV;
}

# Don't really want globals, but really, just a database.
my ( %stats, $Total );
my $first_time  = time;
my $last_time   = 0;
my $total_lines = 0;

my @copy_keys        = qw( req bytes elapsed );
my @copy_keys_cached = qw( cached_req cached_bytes );

if (SHOW_REGEX_STATS) {
    push @copy_keys, qw( fresh stale modified unmodified );
}

my @numeric_keys = (
    @copy_keys, @copy_keys_cached, qw( largest_bytes largest_cached_bytes )
);

my %CACHED;

%{ $CACHED{FETCHES} } = map { $_ => 1 } qw(
    SIBLING_HIT CD_SIBLING_HIT PARENT_HIT CD_PARENT_HIT
    DEFAULT_PARENT SINGLE_PARENT FIRST_UP_PARENT ROUNDROBIN_PARENT
    FIRST_PARENT_MISS CLOSEST_PARENT_MISS CLOSEST_PARENT
    ROUNDROBIN_PARENT CACHE_DIGEST_HIT ANY_PARENT
);

%{ $CACHED{HITS} } = map { $_ => 1 } qw(
    UDP_HIT TCP_HIT TCP_IMS_HIT TCP_NEGATIVE_HIT
    TCP_MEM_HIT TCP_OFFLINE_HIT UDP_HIT
    TCP_REFRESH_HIT
);

%{ $CACHED{MISS} } = map { $_ => 1 } qw(
    TCP_MISS TCP_REFRESH_MISS TCP_SWAPFAIL_MISS
);

%{ $CACHED{STATUS} } = map { $_ => 1 } qw(
    TCP_REFRESH_HIT/200
);

%{ $CACHED{FRESH} } = map { $_ => 1 } qw(
    TCP_HIT     TCP_MEM_HIT
    TCP_IMS_HIT TCP_IMS_MISS
    TCP_NEGATIVE_HIT
);

%{ $CACHED{STALE} } = map { $_ => 1 } qw(
    TCP_REFRESH_HIT     TCP_REFRESH_MISS
    TCP_REF_FAIL_HIT
);

%{ $CACHED{REFRESH} } = map { $_ => 1 } qw(
    TCP_CLIENT_REFRESH TCP_CLIENT_REFRESH_MISS
);

%{ $CACHED{MODIFIED} } = map { $_ => 1 } qw(
    TCP_REFRESH_MISS
);

%{ $CACHED{UNMODIFIED} } = map { $_ => 1 } qw(
    TCP_REFRESH_HIT
);

set_opt( Start => description => <<'EOL' );
Squeezer is a tool for gathering different statistical information from
<a href="http://www.squid-cache.org/">Squid</a> web cache server to tune it fine.
The tool is destined basically for web cache operators, but can be obtained and used
for any other purpose. The software has been written in <a href="http://www.perl.com/">
PERL</a> and as Squid itself and PERL - it's free. <b><font color="#FF0000">But you
use it at your own risk!</font> There are several sections that are disabled by default
but can be enabled by editing the script and enabling them. The problems with having
them all enabled are: it slows the processing WAY down, and it makes this
report very large. If you don't use siblings, there are also a few sections that can be
disabled by editing the script, these are "Sibling efficiency" and "By Peer Status"</b>

EOL

set_opt( General => special_show => \&general );
set_opt( General => description  => <<'EOL' );
All values given to you by squeezer are related to the period,
limited by the times described here.
<ul>
<li><i>Start date</i> is a time of the first analyzed service request</li>
<li><i>End date</i> is the time of the last analyzed service request</li>
<li><i>Total time</i> is the length of analyzed period</li>
<li><i>kBytes/Hour</i> is the average amount of data (in kilobytes)
    transferred per hour of analyzed period</li>
<li><i>Average Object Size</i> is the average size (in kB) of
    objects requested</li>
<li><i>Hit Rate</i> is a percentage of cache hits to total requests</li>
<li><i>Bandwidth Savings Total</i> is the total amount of kBytes read
    from the cache</li>
<li><i>Bandwidth Savings Percent</i> is the percentage of kBytes read
    from the cache to total kBytes transfered</li>
<li><i>Average Speed Increase</i> shows how much faster all the traffic is
    on average compared to potentially all-direct traffic</li>
</ul>
EOL

set_opt( Output => special_show => sub { } );
set_opt( Output => title        => 'Output and it\'s interpretation' );
set_opt( Output => description  => <<'EOL' );
The output contains several profiles of information with several different positions (categories) in each. Each category is characterized with several values which are described below:
<ul>
<li><i>Cached Requests</i> is the number of requests that were answered from the cache in each category</li>
<li><i>Cached Req/s</i> are the number of cached requests per second of time spent answering cached requests in each category</li>
<li><i>Cached % of Reqs</i> is a percentage of the number of cached requests to number of total requests in each category</li>
<li><i>Cached Reqs Graph</i> is a graphical representation of the Cached % of Reqs</li>
<BR>
<li><i>Requests</i> is the number of service requests classified into a category</li>
<li><i>Req/s</i> are the number of requests that were served of this category in the amount of time that was used serving requests for the category</li>
<li><i>Req %</i> is the share of current category's requests in total number of requests</li>
<li><i>Req Graph</i> is a graphical representation of the Req %</li>
<BR>
<li><i>Cached Bytes</i> is a total number of bytes retrieved from the cache in each category</li>
<li><i>Cached Bytes/s</i> are the number of cached bytes per second of time spent answering cached requests in each category</li>
<li><i>Cached % of B</i>ytes is a percentage of bytes retrieved from the cache to the total number of bytes in this category</li>
<li><i>Cached Bytes Graph</i> is a graphical representation of the Cached % of Bytes</li>
<BR>
<li><i>kBytes</i> is the amount of traffic classified into category (in kilobytes)</li>
<li><i>B/s</i> is the speed (in bytes per second) of transfer in current category (in kilobytes)</li>
<li><i>kB %</i> is the share of current category's traffic in total traffic from this web cache</li>
<li><i>kB Graph</i> is a graphical representation of the kB %</li>
<BR>
<li><i>Time</i> is the total amount of time spent serving requests in each category</li>
<li><i>Time %</i> is a percentage of time spend on each category's requests to the total amount of time spent serving requests</li>
<li><i>Time Graph</i> is a graphical representation of the Time %</li>
<BR>
<li><i>Largest Cached Item</i> is the size (in bytes) of the largest item in each category that was cached</li>
<li><i>Largest Item</i> is the size (in bytes) of the largest item requested whether it was cached or not</li>
</ul>
EOL

set_opt( Statistics => special_show => \&statistics );
set_opt( Statistics => title        => 'Cache Statistics' );
set_opt( Statistics => description  => <<'EOL' );
This is an overview of the cache, it shows whether it is doing you any good to have this server running.

<ul>

<li>
<i>Cached_Local</i> is the characteristics for fetches from local web cache
server; it shows you the general information about the efficiency of the
local server - how much traffic goes locally instead of from outside and
how much faster that is compared to the direct fetches</li>

<li>
<i>Cached_Other</i> is an aggregate category for the fetches from the
cooperating web cache servers - it gives you the overview of cooperation
between you and your siblings/parents</li>

<li>
<i>Cached_Total</i> is the total traffic traffic fetched from all caches, local and all peers</li>

<li>
<i>Direct fetches</i> is the characteristics for direct fetches
from the origin servers</li>

<li>
<i>Total</i> is the characteristics of <b>all</b> the traffic coming
through this web cache server - no matter who satisfied the request: cached or direct</li>

<br>
<li>
<i>kB Times to direct</i> in this category shows how
much all the traffic is on an average faster compared to potentially all-direct
traffic; good for reporting and cache advertising purposes ;)
<font color="#FF0000">this value is important - it tells you
whether the cache speeds up your service or not!</font></li>

</ul>
EOL

init( Total => 'Total' );
set_opt( Total => show_cached => 1 );
set_opt( Total => title       => 'Total Requests' );
set_opt( Total => description => <<'EOL' );
This table is the total of all requests served by this caching server.
EOL

if (SHOW_TYPE_STATS) {
    set_opt( by_type => show_cached => 1 );
    set_opt( by_type => title       => 'By MIME type' );
    set_opt( by_type => description => <<'EOL' );
This table shows you detailed statistics about efficiency of fetching
objects of different types. It is useful for making different
refresh_patterns in your squid.conf. This does make a sense while
refreshing different types of objects - rather large like pictures
and movies and changed rarely - and smaller and changed often -
like HTML documents. As you can imagine relaxing the refreshing
rules for the first ones will raise your byte hit ratio and speed
of service without large risk of staleness, while the second ones
still need the tight refreshing rules. From that table you could
see the impact of the different object types for your web cache
server and it's efficiency. This is can be replaced by the table
of refresh patterns hit characteristics by editing the script, but
it slows the script down immensely.
EOL
}

init( by_cache => 'Direct' );
set_opt( by_cache => title       => 'By Caching Server' );
set_opt( by_cache => description => <<'EOL' );
This shows how many requests were served for each caching server.
EOL

if (SHOW_CLIENT_STATS) {
    set_opt( by_client => show_cached => 1 );
    set_opt( by_client => description => <<'EOL' );
This shows how many requests were served for each client accessing the server.
EOL
}

if (SHOW_FETCH_STATS) {
    set_opt( by_fetch => title       => 'By Peer Status' );
    set_opt( by_fetch => description => <<'EOL' );
This shows how many requests were served from each caching server.
EOL
}

if (SHOW_STATUS_STATS) {
    set_opt( by_status => title       => 'By Status Code' );
    set_opt( by_status => description => <<'EOL' );
This table shows detail of the status returned by different requests.
EOL
}

if (SHOW_HIT_STATS) {
    set_opt( by_hit => title       => 'By cache result codes' );
    set_opt( by_hit => description => <<'EOL' );
This table shows the characteristics for different cache result
codes. The only useful information I have found is the difference
between TCP_MEM_HIT (which are objects fetched from squid's RAM
buffer) against TCP_HIT (which are fetched from disk buffer). Low
value for TCP_HIT displays the need for dedicate more RAM for Squid
and/or rearranging the cache_dir layout - spreading several cache
directories over several disk/controllers or any further disk
performance improvement.
EOL
}

if (SHOW_HOUR_STATS) {
    init( by_hour => sprintf "%02d", $_ ) for 0 .. 23;
    set_opt( by_hour => show_cached => 1 );
    set_opt( by_hour => description => <<'EOL' );
This shows cache statistics by hour of day. This is in the local time zone for the log file.
EOL
    set_opt(
        by_hour => sort => sub {
            my ( $x, $y, $s ) = @_;
            no warnings 'numeric';
            $x <=> $y || $x cmp $y;
        }
    );
}

if (SHOW_SIZE_STATS) {
    set_opt( by_size => title       => 'By size of request' );
    set_opt( by_size => description => <<'EOL' );
This shows cache statistics by size of request in bytes.
EOL
}

if (SHOW_EXT_STATS) {
    set_opt( by_ext => show_cached => 1 );
    set_opt( by_ext => title       => 'By file extension or type of file' );
    set_opt( by_ext => description => <<'EOL' );
<p>I use this table to decide what refresh_patterns to use, and which order to put them.</p>

<p>The best way to show how it finds the different expressions, it to show you the matching it does.</p>

<pre>
        $url =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
        my $ext
            = $url =~ m{\?|\=|\&|\@|\;}  ? '_query'
            : $url =~ m{:\d+$}           ? '_port'
            : $url =~ m{[^/]+(\.[^/]+)$} ? $1
            : $url =~ m{://[^/]+/?$}     ? '_base'
            : $url =~ m{/[^/\.]*$}       ? '_dir'
            : $url =~ m{:\d+}            ? '_port'
            : $url =~ m{^\.?\d+$}        ? '_number'
            :                              '_unknown';

</pre>
EOL
    set_opt(
        by_ext => sort => sub {
            my ( $x, $y, $s ) = @_;
            $s->{$y}->{req} <=> $s->{$x}->{req};
        }
    );
}

if (SHOW_SIZE_STATS) {
    set_opt( by_size => show_cached => 1 );
    set_opt( by_size => title       => 'By size of request' );
    set_opt( by_size => description => <<'EOL' );
This shows cache statistics by size of request in bytes.
EOL
    set_opt(
        by_size => sort => sub {
            my ( $x, $y, $s ) = @_;
            no warnings 'numeric';
            $x <=> $y || $x cmp $y;
        }
    );
}

if ( SHOW_REGEX_STATS && $conf->{regexes} ) {
    init( 'by_regex', 'Total' );
    set_opt( by_regex => title =>
            'Refresh pattern efficiency (Thanks to squij!)' );
    set_opt( by_regex => description => <<'EOL' );
<ul>
<li><i>REGEX</i> - the pattern. 'i' is appended if it is case-insensitive.</li>
<li><i>CURRENT OPTIONS</i> - The options currently specified in squid.conf.</li>
<li><i>AVE SVC TIME</i> - time (in seconds) that it takes to send these objects to the client, in seconds. This includes objects satisfied from the cache as well as from the network.</li>
<li><i>RATE REQ/BYTE</i> - hit rate, in requests and bytes, for that object. The items with the most requests should most likely be at the top of the list</li>
of refresh_patterns.</li>
<li><i>FRESH/STALE</i> - ratio of fresh hits vs. stale hits for the pattern.</li>
<li><i>UNMOD/MOD</i> - ratio of stale hits that were unmodified on the origin server, against those that were modified.</li>
<li><i>TOTAL REQ/BYTES</i> - total number of requests and bytes seen for the pattern.</li>
<li><i>TOTAL Graph REQ/BYTES</i> - A graph of a percentage of the current items reqests/bytes to the total requests/bytes</li>
<li>The last row is of overall statistics for each column, for all content.</li>
<li><i>* note that byte hit rates are those sent to the client; client IMS hits may cause this to be inaccurate.</i></li>
<li><i>* if 0 is in either side of one of the ratios, it means that there was no traffic seen for that item.</i></li>
</ul>
So, how do you use this? <br />

Hit rate and total hits are merely metrics for how much a pattern is used,
and how effectively the matching objects can be cached. They allow you to
determine what patterns are worth working with, and which ones may need to
be split into separate patterns.<br />

Fresh/stale tells you how the refresh parameters are performing; a higher
fresh ratio means that more requests are being satisfied directly from the
cache.<br />

Unmod/mod compares how many stale hits that were checked (with an IMS) on the
origin server are modified. If there is a high ratio of unmodified stale hits,
it may be good to raise your refresh thresholds. On the other hand, if there
is a high number of modified hits, it indicates that your thresholds are too
high, and are more likely to be modified when your cache still believes that
they are fresh.<br />

It is a good idea to aim to keep unmod/mod at 1:1 or with a slightly higher
unmod number.<br />

For example:
<pre>
               regex      hit rate  fresh/stale  unmod/mod       total
------------------------------------------------------------------------------
             \.gif$       25% ( 14%)     5:2     1:1       19357 (     48709k)
             \.jpg$       16% ( 19%)    15:2     3:1        1990 (     24105k)
             \.htm$       29% ( 29%)     1:1     3:4        1110 (      9311k)
            \.html$       21% ( 24%)     1:2     2:11       4099 (     27138k)
             \.exe$        9% ( 12%)     1:0     0:0          19 (     42313k)
                \/$       48% ( 61%)     2:15    1:5        3407 (     35211k)
                  .        7% (  2%)     1:1     1:3        6049 (    206117k)
              total       24% ( 14%)     1:1     1:1       36877 (    355795k)
</pre>

<ul>
<li><i>.gif</i> traffic has very good statistics; the hit rate, total traffic and fresh ratio are all high, and unmod/mod is 1:1, which is about where we want it.</li>

<li><i>.jpg</i> traffic is also good, but could possibly benefit from even higher refresh thresholds.</li>

<li><i>.htm</i> and .html traffic is fresh fairly often, but is usually modified when it becomes stale; this indicates that we should consider scaling back those patterns.</li>

<li>All cache hits to .exe objects were fresh.</li>

<li>The default pattern ('.') is being used a fair amount; it may be worthwhile to try more precise patterns.</li>

<li>* The output of squij is still experimental, and unproven. Currently, UDP
(inter-cache) traffic is NOT included; only HTTP (client) traffic is measured.</li>
</ul>
EOL
    set_opt( by_regex => regexes      => $conf->{regexes} );
    set_opt( by_regex => special_show => \&regex );
    foreach my $re ( @{ $conf->{regexes} } ) {
        init( by_regex => $re->{regex} );
    }
}

if ( SHOW_SERVER_STATS && $conf->{servers} ) {
    set_opt( by_server => show_options => 1 );
    set_opt( by_server => title        => 'Sibling efficiency' );
    set_opt( by_server => description  => <<'EOL' );
This table shows you the characteristics of the fetches from individual
cooperating web cache servers. This one will help you to properly
set up sibling relationships. The servers are sorted by the amount of transfer
- the effective siblings/parents are higher in the table. Remember about
some rules

<ul>
<li>
the slowest sibling will go probably down the table - it answers slowly
for ICP queries and the chance of SIBLING HIT for him is reduced; it does
mean that faster siblings should have bigger <i>Xfer %</i>  - if it
is not true something goes wrong - e.g. you probably try to access large
(and having good ICP hit ratio), but slow (heavily loaded) server - this
will slow you down! If it is parent, you can use weight options to balance
it; if it is sibling you'll probably need to copy it's data to your cache
(do not use <i>proxy only </i>option!) or even turn it off.</li>

<li>
the fastest siblings can use the proxy only option to avoid the replication
of the data which is available fast e.g. from the same fast network (LAN
or MAN) by the some backup/additional/private link; doing that you save
your disk space and database entries for something, which could be fetched
at any time with small cost</li>
</ul>
EOL
    foreach my $k ( keys %{ $conf->{servers} } ) {
        init( 'by_server', $k );
        set_item_opt(
            by_server => $k => options => join '<br />',
            map      { "$_&nbsp;" . $conf->{servers}->{$k}->{$_} }
                grep { defined $conf->{servers}->{$k}->{$_} }
                sort keys %{ $conf->{servers}->{$k} }
        );
    }
}

if (SHOW_WEB_SERVER_STATS) {
    set_opt( by_web_server => show_cached => 1 );
    set_opt( by_web_server => description => <<'EOL' );
This is a list of all requests by the web server from which it was requested.
EOL
}

if (SHOW_DENIED_BY_URL) {
    set_opt( denied_by_url => title       => '' );
    set_opt( denied_by_url => description => <<'EOL' );
This is a list of all denied requests and the URL that was denied.
This is useful for monitoring if your ACL's are set up properly
EOL
}

if (SHOW_DENIED_BY_CLIENT) {
    set_opt( denied_by_client => title       => '' );
    set_opt( denied_by_client => description => <<'EOL' );
This is a list of all denied requests and the IP of the client that
was denied. This is useful for monitoring if your ACL's are set up
properly and if there are some other IP's trying to use your cache
EOL
}

my $last_file = '';
while (<>) {
    warn "Processing $ARGV\n" if $ARGV ne $last_file;
    $last_file = $ARGV;
    my $stat = parse_line($_) or next;
    $total_lines++;

    $first_time = $stat->{time} if $first_time > $stat->{time};
    $last_time  = $stat->{time} if $last_time < $stat->{time};

    add_stats( Total => 'Total', $stat );

    add_stats( by_status => $stat->{status}, $stat )
        if SHOW_STATUS_STATS;

    add_stats(
        by_hour => sprintf( '%02d', ( localtime $stat->{time} )[2] ),
        $stat
    ) if SHOW_HOUR_STATS;

    add_stats( denied_by_url => $stat->{url}, $stat )
        if SHOW_DENIED_BY_URL && $stat->{hit} =~ /DENIED/;

    add_stats( by_client => $stat->{remotehost}, $stat )
        if SHOW_CLIENT_STATS && $stat->{remotehost};

    add_stats( denied_by_client => $stat->{remotehost}, $stat )
        if SHOW_DENIED_BY_CLIENT
            && $stat->{remotehost}
            && $stat->{hit} =~ /DENIED/;

    add_stats( by_type => lc( $stat->{mime} ), $stat )
        if SHOW_TYPE_STATS;

    add_stats( by_type => $stat->{fetch}, $stat )
        if SHOW_FETCH_STATS;

    add_stats( by_hit => $stat->{hit}, $stat ) if SHOW_HIT_STATS;

    if (SHOW_EXT_STATS) {
        my $url = $stat->{url};
        $url =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
        my $ext
            = $url =~ m{\?|\=|\&|\@|\;}  ? '_query'
            : $url =~ m{:\d+$}           ? '_port'
            : $url =~ m{[^/]+(\.[^/]+)$} ? $1
            : $url =~ m{://[^/]+/?$}     ? '_base'
            : $url =~ m{/[^/\.]*$}       ? '_dir'
            : $url =~ m{:\d+}            ? '_port'
            : $url =~ m{^\.?\d+$}        ? '_number'
            :                              '_unknown';

        add_stats( by_ext => $ext, $stat );
        add_stats( by_ext => lc($ext) . ' (-i)', $stat )
            if $ext !~ /^_/;
    }

    if ( $stat->{cached_req} ) {
        if ( $stat->{cached_fetch} ) {
            add_stats( by_cache => 'Remote',        $stat );
            add_stats( by_cache => $stat->{server}, $stat );
        }
        else {
            add_stats( by_cache => 'Local', $stat );
        }
        add_stats( by_cache => 'Total', $stat );
    }
    else {
        add_stats( by_cache => 'Direct', $stat );
    }

    if (SHOW_SIZE_STATS) {
        my $size = 'More';
        for ( my $i = 1; $i < 1_000_000_000; $i *= 10 ) {
            $size = $i and last if $stat->{bytes} < $i;
        }
        add_stats( by_size => $size, $stat );
    }

    if (SHOW_WEB_SERVER_STATS) {
        my ($web_server) = $stat->{url} =~ m{^\w+://([^/]+)};
        add_stats( by_web_server => $web_server, $stat )
            if $web_server;
    }

    if ( SHOW_REGEX_STATS && $conf->{regexes} ) {
        foreach my $regex ( @{ $conf->{regexes} } ) {
            if ( $stat->{url} =~ $regex->{compiled} ) {
                add_stats( by_regex => 'Total',         $stat );
                add_stats( by_regex => $regex->{regex}, $stat );

                # XXX Squij_Tags
                last;
            }
        }
    }

    next if $stat->{fetch} =~ /DIRECT$/;

    if (SHOW_SERVER_STATS) {
        add_stats( by_server => $stat->{server}, $stat );
        add_stats( by_server => 'Total',         $stat );
    }
}

make_report();

sub Read_Conf {

    #
    # Read info about siblings and refresh_patterns
    # This is taken pretty much verbatim from the original squeezer.pl
    #
    my $conf = shift;
    my @regex;
    my %servers;
    my %conf = (
        regexes => \@regex,
        servers => \%servers,
        log     => '',
    );

    if ( !-e $conf ) {
        warn "Config file $conf not found!\n";
        return \%conf;
    }

    open( my $fh, $conf ) or die "Could not open $conf!\n";
    while (<$fh>) {
        s/\r?\n$//;
        if (/^\s*refresh_pattern\s+/) {
            my ( $rx, $opts, $compiled );
            if (/\s+\-i\s+/) {
                ( undef, undef, $rx, $opts ) = split( /\s+/, $_, 4 );
                $compiled = qr/$rx/i;
                $rx       = '-i ' . $rx;
            }
            else {
                ( undef, $rx, $opts ) = split( /\s+/, $_, 3 );
                $compiled = qr/$rx/;
            }

            push @regex,
                {
                regex    => $rx,
                options  => $opts,
                compiled => $compiled,
                };
        }
        elsif (/^\s*(?:cache_peer|cache_host)\s/) {
            my ( $keyword, $server, $rel, $http, $icp, $opt ) = split(/\s+/);
            $opt =~ s/login=.*:\K.*// if $opt;
            $servers{$server}{relation}  = $rel;
            $servers{$server}{http_port} = $http;
            $servers{$server}{icp_port}  = $icp;
            $servers{$server}{options}   = $opt;
        }
        elsif (/^\s*cache_access_log\s/) {
            ( undef, $conf{log} ) = split;
        }
    }
    close $fh;
    return \%conf;
}

sub init {
    my ( $group, $key ) = @_;
    return $stats{$group}{stats}{$key} if $stats{$group}{stats}{$key};

    my %s;
    $s{$_} = 0 for @numeric_keys;
    $stats{$group}{stats}{$key} = \%s;

    return \%s;
}

sub set_opt {
    my ( $group, $opt, $value ) = @_;
    $stats{$group}{opts}{$opt} = $value;
}

sub set_item_opt {
    my ( $group, $key, $opt, $value ) = @_;
    $stats{$group}{stats}{$key}{opts}{$opt} = $value;
}

sub add_stats {
    my ( $group, $key, $stat ) = @_;
    return unless $group && $key;

    my $s = $stats{$group}{stats}{$key} || init( $group, $key );

    $s->{$_} += $stat->{$_} for @copy_keys;
    $s->{largest_bytes} = $stat->{bytes}
        if $s->{largest_bytes} < $stat->{bytes};

    if ( $stat->{cached_req} ) {
        foreach my $k (@copy_keys_cached) {
            my $sk = substr( $k, 7 );
            $s->{$k} += $stat->{$sk};
        }
        $s->{largest_cached_bytes} = $stat->{bytes}
            if $s->{largest_cached_bytes} < $stat->{bytes};
    }
}

sub parse_line {
    my %stat = ( req => 1, cached_req => 0 );
    @stat{
        qw(
            time elapsed remote_host status bytes
            method url rfc931 peer_status mime
            )
        }
        = split ' ', $_[0];

    return if index $stat{status}, 'TCP_';

    @stat{qw( hit   code )}   = split '/', $stat{status};
    @stat{qw( fetch server )} = split '/', $stat{peer_status};

    if (   $CACHED{HITS}{ $stat{hit} }
        || $CACHED{STATUS}{ $stat{status} }
        || $CACHED{FETCH}{ $stat{fetch} } )
    {
        $stat{cached_req}   = 1;
        $stat{cached_fetch} = exists $CACHED{FETCH}{ $stat{fetch} };
    }

    if (SHOW_REGEX_STATS) {
        $stat{modified}   = exists $CACHED{MODIFIED}{ $stat{hit} };
        $stat{unmodified} = exists $CACHED{UNMODIFIED}{ $stat{hit} };
        $stat{fresh}      = exists $CACHED{FRESH}{ $stat{hit} };
        $stat{stale}      = exists $CACHED{STALE}{ $stat{hit} };
    }

    return \%stat;
}

sub make_report {
    $Total = $stats{Total}{stats}{Total};

    my $by_cache = $stats{by_cache}{stats};
    $stats{Statistics}{stats}{Total} = $stats{Total}{stats}{Total};
    foreach my $k (qw( Direct Cached_Total Cached_Local Cached_Remote )) {
        my $by_cache_key = $k;
        $by_cache_key =~ s/^Cached_//;

        if ( $by_cache->{$by_cache_key} ) {
            $stats{Statistics}{stats}{$k} = $by_cache->{$by_cache_key};
        }
        else { init( Statistics => $k ) }
    }

    print start();

    foreach my $key ( sort keys %stats ) {
        print section( $key, $stats{$key} );
    }

    print sysinfo();
    print end();
}

sub start {
    my $title = $stats{Start}{opts}{title}
        || 'Statistics from '
        . localtime($first_time) . ' to '
        . localtime($last_time);
    my $description = $stats{Start}{opts}{description} || '';
    return <<"EOL";
<html><head><title>$title</title>
<style type="text/css">
h1,h2 { text-align: center }
table { border: 0; cellspacing: 1; celladding: 2 }
th { background: #ddddff; text-align: left }
td { text-align: right }
.header  th { background: #bbbbee; text-align: center }
.special th,.special td { 
    background: #bbbbee; 
    text-align: center; 
    font-size: small 
}
td.special { background: lightblue; }
.options { text-align: left }
.even { background: #ffffdd }
.odd  { background: #eeeebb }
.right { text-align: right !important }
.graph {
    font-size: xx-small;
    font-weight: bold;
    letter-spacing: -0.25em;
    text-align: left;
}
</style>
</head>
<body>
    <h1>Squid server optimizing information</h1>
    <h2>$title</h2>
    <h5>$description</h5>
EOL
}

sub end {
    return <<"EOL";
<i><a href="http://afresh1.com/squeezer2/">squeezer2.pl v$VERSION</a>
by <a href='mailto:andrew\@afresh1.com'>Andrew Fresh</a>
<br>
<a href="http://strony.wp.pl/wp/maciej_kozinski/squeezer.html">Tutorial on using squeezer generated data</a>
</body>
</html>
EOL
}

sub sysinfo {
    my ( $user, $system, $cuser, $csystem ) = times;
    my $total_time = $user + $system + $cuser + $csystem;

    my $output = <<"EOL";
    <h3>Squeezer Performance</h3>
    <table>
EOL

    $output
        .= sprintf '<tr class="even"><th>User time</th><td>%s</td></tr>'
        . '<tr class="odd"><th>System time</th><td>%s</td></tr>'
        . '<tr class="even special"><th>Total time</th><td>%s</td></tr>'
        . '<tr class="odd"><th>Lines Processes</th><td>%s</td></tr>'
        . '<tr class="even special"><th>Speed</th><td>%s lines/s</td></tr>',
        $user, $system, $total_time, $total_lines,
        Commify( sprintf "%d", $total_lines / $total_time );

    $output .= <<"EOL";
    </table>
    <hr />
EOL
    return $output;
}

sub section {
    my ( $section, $stat ) = @_;

    my $title = $stat->{opts}->{title} || Titlify($section);
    my $description = $stat->{opts}->{description};

    my $output = '<h3>' . $title . "</h3>\n";
    $output .= '<h5>' . $description . "</h5>\n" if $description;

    if ( $stat->{opts}->{special_show} ) {
        return $output, $stat->{opts}->{special_show}->(@_), '<hr />';
    }

    return unless $stat->{stats};

    $output .= <<"EOL";
    <table>
EOL
    my @cols;
    if ( my $sort = $stat->{opts}->{sort} ) {

        #$sort = sub { $a <=> $b || $a cmp $b };
        @cols = sort { $sort->( $a, $b, $stat->{stats} ) }
            keys %{ $stat->{stats} };
    }
    else {
        @cols = sort {
            $stat->{stats}->{$b}->{bytes} <=> $stat->{stats}->{$a}->{bytes}
        } keys %{ $stat->{stats} };
    }

    my $i = 0;
    foreach my $k (@cols) {
        my $s = $stat->{stats}->{$k};

        unless ( $i % 25 ) {
            $output .= "<tr class='header'>\n";
            $output .= " <td>&nbsp;</td>\n";
            $output .= " <th>Options</th>\n"
                if $stat->{opts}->{show_options};

            if ( $stat->{opts}->{show_cached} ) {
                $output .= join "\n",
                    ' <th>Cached Requests</th>',
                    ' <th>Cached Req/s</th>',
                    ' <th>Cached % of Reqs</th>',
                    ' <th>Cached Reqs Graph</th>';
                $output .= "\n";
            }

            $output .= join "\n",
                ' <th>Requests</th>',
                ' <th>Req/s</th>',
                ' <th>Req %</th>',
                ' <th>Req Graph</th>';
            $output .= "\n <td>&nbsp;</td>\n";

            if ( $stat->{opts}->{show_cached} ) {
                $output .= join "\n",
                    ' <th>Cached Bytes</th>',
                    ' <th>Cached B/s</th>',
                    ' <th>Cached % of B</th>',
                    ' <th>Cached Bytes Graph</th>';
                $output .= "\n";
            }

            $output .= join "\n",
                ' <th>kBytes</th>',
                ' <th>B/s</th>',
                ' <th>kB %</th>',
                ' <th>Kb Graph</th>';
            $output .= "\n <td>&nbsp;</td>\n";

            $output .= join "\n",
                ' <th>Time</th>',
                ' <th>Time %</th>',
                ' <th>Time Graph</th>';
            $output .= "\n";

            $output .= join "\n",
                ' <th>Largest Cached Item</th>',
                ' <th>Largest Item</th>';

            $output .= "</tr>\n";
        }

        $output .= "<tr class='" . ( $i % 2 ? 'odd' : 'even' ) . "'>\n";

        $output .= " <th>$k</th>\n";

        $output
            .= " <td class='options'>"
            . ( $s->{opts}->{options} || '&nbsp;' )
            . "</td>\n"
            if $stat->{opts}->{show_options};

        foreach my $type (qw( cached_req req cached_bytes bytes )) {
            next if !$stat->{opts}->{show_cached} && $type =~ /^cached_/;

            my $count = $s->{$type};
            $count /= 1024 if $type eq 'bytes';
            my $total = $Total->{$type};
            $total /= 1024 if $type eq 'bytes';
            my $elapsed = $s->{elapsed} / 1000;
            my $percent = $total ? 100 * ( $count / $total ) : 0;

            $output .= sprintf " <td>%s</td>\n",
                Commify( sprintf "%5.2f", $count );
            $output .= sprintf " <td>%s</td>\n",
                Commify( sprintf "%5.2f", $elapsed ? $count / $elapsed : 0 );
            $output .= sprintf " <td>%s</td>\n",
                Commify( sprintf "%5.2f", $percent );
            $output .= sprintf " <td class='graph'>%s</td>\n",
                Graph($percent);

            $output .= " <th>$k</th>\n" if $type !~ /^cached_/;
        }

        my $percent
            = $Total->{elapsed}
            ? 100 * ( $s->{elapsed} / $Total->{elapsed} )
            : 0;

        $output .= sprintf " <td>%s</td>\n", Timeify( $s->{elapsed} );
        $output .= sprintf " <td>%s</td>\n",
            Commify( sprintf "%5.2f", $percent );
        $output .= sprintf " <td class='graph'>%s</td>\n", Graph($percent);

        $output .= sprintf " <td>%s</td>\n",
            Commify( sprintf "%5.2f", $s->{largest_cached_bytes} || 0 );
        $output .= sprintf " <td>%s</td>\n",
            Commify( sprintf "%5.2f", $s->{largest_bytes} || 0 );

        $output .= "</tr>\n";
        $i++;
    }

    $output .= <<"EOL";
    </table>
EOL
    return $output, '<hr />';
}

sub general {
    my ( $section, $stat ) = @_;
    my $direct = $stats{'by_cache'}{stats}{Direct};

    my $hours = ( ( $last_time - $first_time ) / 60 / 60 );
    my $output = <<"EOL";
    <table>
        <tr class='even total'>
EOL
    $output .= sprintf "\t\t<th>Start Date</th><td>%s</td>\n",
        scalar localtime($first_time);

    $output .= "\t</tr><tr class='odd total'>\n";
    $output .= sprintf "\t\t<th>End Date</th><td>%s</td>\n",
        scalar localtime($last_time);

    $output .= "\t</tr><tr class='even total'>\n";
    $output .= sprintf "\t\t<th>Total Time (hh:mm:ss)</th><td>%s</td>\n",
        Timeify( 1000 * ( $last_time - $first_time ) );

    $output .= "\t</tr><tr class='special'>\n";
    $output .= sprintf "\t\t<th colspan=2>kBytes Per Hour</th>\n";

    $output .= "\t</tr><tr class='even'>\n";
    $output .= sprintf "\t\t<th>Cached kBytes/Hour</th><td>%s</td>\n",
        Commify( sprintf "%5.2f",
        $hours ? $Total->{cached_bytes} / 1024 / $hours : 0 );

    $output .= "\t</tr><tr class='odd'>\n";
    $output .= sprintf "\t\t<th>Direct kBytes/Hour</th><td>%s</td>\n",
        Commify( sprintf "%5.2f",
        $hours ? ( $direct->{bytes} / 1024 / $hours ) : 0 );

    $output .= "\t</tr><tr class='even total'>\n";
    $output .= sprintf "\t\t<th>Total kBytes/Hour</th><td>%s</td>\n",
        Commify( sprintf "%5.2f",
        $hours ? $Total->{bytes} / 1024 / $hours : 0 );

    $output .= "\t</tr><tr class='special'>\n";
    $output .= sprintf "\t\t<th colspan=2>Reqs Per Hour</th>\n";

    $output .= "\t</tr><tr class='even'>\n";
    $output .= sprintf "\t\t<th>Cached Reqs/Hour</th><td>%s</td>\n",
        Commify( sprintf "%5.2f",
        $hours ? $Total->{cached_req} / 1024 / $hours : 0 );

    $output .= "\t</tr><tr class='odd'>\n";
    $output .= sprintf "\t\t<th>Direct Reqs/Hour</th><td>%s</td>\n",
        Commify( sprintf "%5.2f",
        $hours ? $direct->{req} / 1024 / $hours : 0 );

    $output .= "\t</tr><tr class='even total'>\n";
    $output .= sprintf "\t\t<th>Total Reqs/Hour</th><td>%s</td>\n",
        Commify( sprintf "%5.2f",
        $hours ? $Total->{req} / 1024 / $hours : 0 );

    $output .= "\t</tr><tr class='special'>\n";
    $output .= sprintf "\t\t<th colspan=2>Average Object Size</th>\n";

    $output .= "\t</tr><tr class='even'>\n";
    $output
        .= sprintf "\t\t<th>Average Cached Object Size</th><td>%s</td>\n",
        Commify(
        sprintf "%5.2f",
        $Total->{cached_req}
        ? $Total->{cached_bytes} / 1024 / $Total->{cached_req}
        : 0
        );

    $output .= "\t</tr><tr class='odd'>\n";
    $output
        .= sprintf "\t\t<th>Average Direct Object Size</th><td>%s</td>\n",
        Commify( sprintf "%5.2f",
        $direct->{req} ? $direct->{bytes} / 1024 / $direct->{req} : 0 );

    $output .= "\t</tr><tr class='even total'>\n";
    $output .= sprintf "\t\t<th>Average Object Size</th><td>%s</td>\n",
        Commify( sprintf "%5.2f",
        $Total->{req} ? $Total->{bytes} / 1024 / $Total->{req} : 0 );

    $output .= "\t</tr><tr class='special'>\n";
    $output .= sprintf "\t\t<th colspan=2>Other</th>\n";

    $output .= "\t</tr><tr class='even total'>\n";
    $output .= sprintf "\t\t<th>Hit Rate</th><td>%s</td>\n",
        Commify( sprintf "%5.2f",
        $Total->{req} ? 100 * $Total->{cached_req} / $Total->{req} : 0 );

    $output .= "\t</tr><tr class='odd total'>\n";
    $output .= sprintf "\t\t<th>Bandwidth Savings Total</th>"
        . "<td class='special'>%s</td>\n",
        Commify( sprintf "%5.2f", $Total->{cached_bytes} / 1024 );

    $output .= "\t</tr><tr class='even total'>\n";
    $output
        .= sprintf "\t\t<th>Bandwidth Savings Percent</th><td>%s</td>\n",
        Commify(
        sprintf "%5.2f",
        $Total->{bytes} ? 100 * $Total->{cached_bytes} / $Total->{bytes} : 0
        );

    my $total_speed
        = $Total->{elapsed} ? $Total->{bytes} / $Total->{elapsed} : 0;
    my $direct_speed
        = $direct->{elapsed} ? $direct->{bytes} / $direct->{elapsed} : 0;

    $output .= "\t</tr><tr class='odd total'>\n";
    $output .= sprintf "\t\t<th>Average Speed Increase</th>"
        . "<td class='special'>%s</td>\n",
        Commify( sprintf "%5.2f",
        $direct_speed
        ? 100 * ( ( $total_speed / $direct_speed ) - 1 )
        : 0 );

    $output .= <<"EOL";
        </tr>
    </table>
EOL

    return $output;
}

sub statistics {
    my ( $section, $stat ) = @_;

    my $direct_speed
        = $stat->{stats}->{Direct}->{elapsed}
        ? $stat->{stats}->{Direct}->{bytes}
        / ( $stat->{stats}->{Direct}->{elapsed} / 1000 )
        : 0;

    my $output = <<"EOL";
    <table>
      <tr class='header'>
        <td>&nbsp;</td>
        <th>Requests</th>
        <th>kBytes</th>
        <th>B/s</th>
        <th>kB %</th>
        <th>kB Graph</th>
        <th>kB Times to Direct</th>
        <th>Times Graph</th>
      </tr>
EOL

    my $i = 0;
    foreach my $k ( sort keys %{ $stat->{stats} } ) {
        my $s = $stat->{stats}->{$k};
        my $speed
            = $s->{elapsed} ? $s->{bytes} / ( $s->{elapsed} / 1000 ) : 0;
        my $percent
            = $Total->{bytes} ? 100 * $s->{bytes} / $Total->{bytes} : 0;
        my $direct_class = $k eq 'Direct' ? " class='special'" : '';
        my $times_to_direct
            = $speed && $direct_speed ? $speed / $direct_speed : 0;
        my $times_to_direct_class
            = $times_to_direct < 0
            ? " class='red graph'"
            : " class='graph'";

        $output .= "    <tr class='" . ( $i % 2 ? 'odd' : 'even' ) . "'>\n";

        $output
            .= sprintf '        '
            . '<th>%s</th>'
            . '<td>%s</td>'
            . '<td>%s</td>'
            . '<td>%s</td>'
            . '<td>%s</td>'
            . "<td class='graph'>%s</td>"
            . '<td%s>%s</ td > '
            . "<td%s>%s</d>" . "\n",
            $k,
            Commify( sprintf "%.2f", $s->{req} ),
            Commify( sprintf "%.2f", $s->{bytes} / 1024 ),
            Commify( sprintf "%.2f", $speed ),
            Commify( sprintf "%.2f", $percent ),
            Graph($percent),
            $direct_class, Get_Ratio( $speed, $direct_speed ),
            $times_to_direct_class,
            Graph(
            $times_to_direct
            ? 100 * ( log($times_to_direct) / log(10) )
            : 0
            );

        $output .= "    </tr>\n";
        $i++;
    }

    $output .= <<"EOL";
    </table>
EOL
    return $output;
}

sub regex {
    my ( $section, $stat ) = @_;
    my $regexes = $stat->{opts}->{regexes} || return;
    my $total = $stat->{stats}->{Total};

    my $output = <<"EOL";
    <table>
EOL

    my $i = 0;
    foreach my $re ( @{$regexes}, { regex => 'Total', options => '' } ) {
        my $s = $stat->{stats}->{ $re->{regex} } || next;

        $output .= <<'EOL' unless $i % 25;
      <tr class='header'>
        <td>&nbsp;</td>
        <th>Current</th>
        <th>Avg Svc</th>
        <th colspan=2>Rate</th>
        <th>Fresh :</th>
        <th>Unmod :</th>
        <th colspan=2>Total</th>
        <th colspan=2>Total Graph</th>
      </tr>
      <tr class='header'>
        <th>Regex</th>
        <th>Options</th>
        <th>Time</th>
        <th>Reqs</th>
        <th>Bytes</th>
        <th>Stale</th>
        <th>Modified</th>
        <th>Reqs</th>
        <th>Bytes</th>
        <th>Reqs</th>
        <th>Bytes</th>
      </tr>
EOL

        $output
            .= '      <tr class='
            . ( $i % 2 ? 'even' : 'odd' )
            . ( $re->{regex} eq 'Total' ? ' special' : '' ) . ">\n";

        $output
            .= sprintf '        '
            . '<th>%s</th>'
            . '<td>%s</td>'
            . '<td>%s</td>'
            . '<td>%s</td>'
            . '<td>%s</td>'
            . '<td>%s</td>'
            . '<td>%s</td>'
            . '<td>%s</td>'
            . '<td>%s</td>'
            . "<td class='graph right'>%s</td>"
            . "<td class='graph'>%s</td>", $re->{regex}, $re->{options},
            Commify( sprintf "%5.3f",
            $s->{req} ? $s->{elapsed} / 1000 / $s->{req} : 0 ),
            Commify(
            $s->{req} ? sprintf "%5.2f%%",
            100 * $s->{cached_req} / $s->{req} : 0
            ),
            Commify(
            $s->{bytes} ? sprintf "%5.2f%%",
            100 * $s->{cached_bytes} / $s->{bytes} : 0
            ),
            Get_Ratio( $s->{fresh},      $s->{stale} ),
            Get_Ratio( $s->{unmodified}, $s->{modified} ),
            Commify( sprintf "%3d",   $s->{req} ),
            Commify( sprintf "%5.2f", $s->{bytes} / 1024 ),
            Graph( $total->{req} ? 100 * $s->{req} / $total->{req} : 0 ),
            Graph(
            $total->{bytes} ? 100 * $s->{bytes} / $total->{bytes} : 0 );

        $output .= "      </tr>\n";
        $i++;
    }

    $output .= <<"EOL";
    </table>
EOL
    return $output;
}

sub Titlify {
    return join ' ', map { ucfirst $_ } split '_', $_[0];
}

# This takes a number and returns it with comma's like us american's like to
# see numbers
sub Commify {
    local $_ = shift;
    return unless defined $_;
    return '-' if /^\s*[0\.]*\%?$/;
    1 while s/^([-+]?\d+)(\d{3})/$1,$2/;
    return $_;
}

# Changes an epoch time to hh:mm:ss.mili
sub Timeify {
    my ($milisecond) = @_;

    my ( $hour, $minute, $second );

    $second = $milisecond / 1000;
    $minute = $second / 60;
    $second = $second % 60;
    $hour   = $minute / 60;
    $minute = $minute % 60;

    return sprintf "%02d:%02d:%05.3f", $hour, $minute, $second;
}

sub Get_Ratio {
    my ( $first, $second ) = @_;

    my $max_smaller = 3.5;
    my $max_bigger  = 999;

    return '-' if !defined $first && !defined $second;
    return '-:' if !defined $first;
    return ':-' if !defined $second;

    return "0:0" if $first == 0 && $second == 0;
    return "0:1" if $first == 0;
    return "1:0" if $second == 0;
    return "1:1" if $first == $second;

    my $reverse_order = $first < $second;
    my ( $larger, $smaller )
        = $reverse_order ? ( $second, $first ) : ( $first, $second );

    # If it is too big, make it the largest ratio it can be
    if ( ( $larger / $smaller ) > $max_bigger ) {
        $larger  = $max_bigger;
        $smaller = 1;
    }

    # If the smaller number is bigger than the largest we want it to be,
    # reduce the whole ratio
    else {
        while ( $smaller > $max_smaller ) {
            my $approx = ( 1 / ( $smaller / $larger ) );
            my $divisor = $smaller / $approx;
            $divisor = 1.01 if $divisor <= 1;

            $larger  /= $divisor;
            $smaller /= $divisor;
        }
    }

    # Round the numbers
    $larger  = sprintf( "%1.0f", $larger );
    $smaller = sprintf( "%1.0f", $smaller );

    # If the larger number is divisable by the smaller number,
    # reduce both by dividing by the smaller
    while ( !( $larger % $smaller ) && ( $smaller != 1 ) ) {
        $larger  /= $smaller;
        $smaller /= $smaller;
    }

    # if both numbers are divisible by a small list of primes,
    # divide them out
    foreach ( 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41 ) {
        while ( !( $larger % $_ ) && !( $smaller % $_ ) ) {
            $larger  /= $_;
            $smaller /= $_;
        }
    }

    return $reverse_order
        ? "$smaller:$larger"
        : "$larger:$smaller";
}

sub Graph {
    my ($amount) = @_;
    return '|' x $amount;
}
