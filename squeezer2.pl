#!/usr/bin/perl -w
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
#                  correctly, so if it is completely screwed up and crashes 
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
# 02/19/2003 01:16AM *** Andrew Fresh <andrew@mad-techies.org>
#
# 03/14/2003 12:49AM *** After working on this for almost a month, on 
#                    and off when I had time, it is finally about right 
#                    I think. If you have any questions, please let me 
#                    know, I need to work on my commenting so let me know 
#                    where I am sucking at it.
#
#######################################################################
use strict;
use diagnostics;

# these are the variables that need to be changed if your configuration is different from mine.
my $base_dir  = '/var/squid';
my $conf_name = '/etc/squid/squid.conf';
my $log_dir = $base_dir . '/logs';
my $log_name = 'access.log';

# Here you set which information you want to see. The more you turn on, the longer it takes, but you get better kewler info
# These I have enabled and are what I find to be the most useful
use constant SHOW_HIT_STATS	=> 1; # my default is 1 or enabled
use constant SHOW_HOUR_STATS	=> 1; # my default is 1 or enabled
use constant SHOW_SIZE_STATS	=> 1; # my default is 1 or enabled
use constant SHOW_DENIED_BY_URL 	=> 1; # my default is 1 or enabled
use constant SHOW_DENIED_BY_CLIENT	=> 1; # my default is 1 or enabled
# These I have enabled, but if you don't have any peers set up, you can disable them
use constant SHOW_SERVER_STATS	=> 1; # my default is 1 or enabled
use constant SHOW_FETCH_STATS	=> 1; # my default is 1 or enabled
# These are ones that I have disabled by default
use constant SHOW_CLIENT_STATS	=> 1; # my default is 0 or disabled because there are too many clients usually and that makes the page very long
use constant SHOW_WEB_SERVER_STATS	=> 1; # my default is 0 or disabled because there are too many URLs usually and that makes the page very long
use constant SHOW_STATUS_STATS	=> 1; # my default is 0 or disabled because this information is shown with less detail in the FETCH_STATS
use constant SHOW_REGEX_STATS	=> 1; # my default is 0 or disabled because the regex is very slow, it makes the script run 10 times or so slower
use constant SHOW_TYPE_STATS	=> 1; # my default is 0 or disabled because this makes the report very large with little good info unless you are changing your refresh_pattern's

# These are the colors for the table, I used the colors from the original script to keep the feel similar
use constant COLOR_TABLE_COL_HEAD	=> '#bbbbee';
use constant COLOR_TABLE_ROW_HEAD	=> '#ddddff';
use constant COLOR_TABLE_ROW_EVEN	=> '#ffffdd';
use constant COLOR_TABLE_ROW_ODD	=> '#eeeebb';
use constant COLOR_TABLE_CELL_SPECIAL	=> 'LIGHTBLUE';

# these are how the tables look.  I made them look kewl with no borders but the different colors in the cells seperating them.
use constant TABLE_CELL_BORDER	=> 'border=0';
use constant TABLE_CELLSPACING	=> 'cellspacing=1';
use constant TABLE_CELLPADDING	=> 'cellpadding=2 ';

# change these to change the headings for the different sections
my %Stats_Types_Headers = (
	'by_type'	=> 'By MIME type',
	'by_cache'	=> 'By Caching Server',
	'by_client'	=> 'By Client',
	'by_fetch'	=> 'By Peer Status',
	'by_status'	=> 'By Status Code',
	'by_hit'	=> 'By cache result codes',
	'by_hour'	=> 'By hours',
	'by_size'	=> 'By size of request',
	'by_regex'	=> 'Refresh pattern efficiency',
	'by_srv'	=> 'Sibling efficiency',
	'Total'		=> 'Total Requests',
	'All'		=> 'Output and it\'s interpretation',
	'by_web_server'	=> 'By web server',
	'denied_by_url'	=> 'Denied by URL',
	'denied_by_client'	=> 'Denied by Client IP',
#	''	=> '',
);

# these are the descriptions for each section, they are printed out as an <h5> so many html tags will work strangely
my %Stats_Types_Descriptions = (
	'by_type'	=> q(
This table shows you detailed statistics about efficiency of fetching objects of different types. It is useful for making different refresh_patterns in your squid.conf. This does make a sense while refreshing different types of objects - rather large like pictures and movies and changed rarely - and smaller and changed often - like HTML documents. As you can imagine relaxing the refreshing rules for the first ones will raise your byte hit ratio and speed of service without large risk of staleness, while the second ones still need the tight refreshing rules. From that table you could see the impact of the different object types for your web cache server and it's efficiency. This is can be replaced by the table of refresh patterns hit characteristics by editing the script, but it slows the script down immensely. 
),
	
	'by_cache'	=> q(
This shows how many requests were served for each caching server. 
),
	
	'by_client'	=> q(
This shows how many requests were served for each client accessing the server. 
),
	
	'by_fetch'	=> q(
The basic stuff showing you advantages/disadvantages of using parent and sibling relationship. Use with caution! Remember that your parents and siblings could be available via lines of different speed and quality. Using those aggregates for analysis may cause false conclusions.<br>
The strong point of this stuff is opportunity to compare cache digests versus ICP, if there are siblings communicating both ways in similar environment.<br>
No idea how to use that more:\( Any suggestions? 
),
	'by_status'	=> q(
This table shows detail of the status returned by different requests.
),

	'by_hit'	=> q(
This table shows the characteristics for different cache result codes. The only useful information I have found is the difference between TCP_MEM_HIT \(which are objects fetched from squid's RAM buffer\) against TCP_HIT \(which are fetched from disk buffer\). Low value for TCP_HIT displays the need for dedicate more RAM for Squid and/or rearranging the cache_dir layout - spreading several cache directories over several disk/controllers or any further disk performance improvement.
),
	
	'by_hour'	=> q(
This shows cache statistics by hour of day. This is in the local time zone for the log file.
),
	
	'by_size'	=> q(
This shows cache statistics by size of request in bytes.
),

	'by_regex'	=> q(
This shows how many requests were served for each refresh pattern. 
),
	
	'by_srv'	=> q(
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
),
	
	'Total'		=> q(
This table is the total of all requests served by this caching server.
),
	
	'cache_stats'	=> q(
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
traffic; good for reporting and cache advertising purposes ;\)
<font color="#FF0000">this value is important - it tells you 
whether the cache speeds up your service or not!</font></li>

</ul>
),

	'Description'	=> q(
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
),

	'General'	=> q(
All values given to you by squeezer are related to the period, limited by the times described here.
<ul>
<li><i>Start date</i> is a time of the first analyzed service request</li>
<li><i>End date</i> is the time of the last analyzed service request</li>
<li><i>Total time</i> is the length of analyzed period</li>
<li><i>kBytes/Hour</i> is the average amount of data (in kilobytes) transferred per hour of analyzed period</li>
<li><i>Average Object Size</i> is the average size \(in kB\) of objects requested</li>
<li><i>Hit Rate</i> is a percentage of cache hits to total requests</li>
<li><i>Bandwidth Savings Total</i> is the total amount of kBytes read from the cache</li>
<li><i>Bandwidth Savings Percent</i> is the percentage of kBytes read from the cache to total kBytes transfered</li>
<li><i>Average Speed Increase</i> shows how much faster all the traffic is on average compared to potentially all-direct traffic</li>
</ul>
),

	'All'	=> q(
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
<li><i>kBytes</i> is the amount of traffic classified into category \(in kilobytes\)</li>
<li><i>B/s</i> is the speed \(in bytes per second\) of transfer in current category \(in kilobytes\)</li>
<li><i>kB %</i> is the share of current category's traffic in total traffic from this web cache</li>
<li><i>kB Graph</i> is a graphical representation of the kB %</li>
<BR>
<li><i>Time</i> is the total amount of time spent serving requests in each category</li>
<li><i>Time %</i> is a percentage of time spend on each category's requests to the total amount of time spent serving requests</li>
<li><i>Time Graph</i> is a graphical representation of the Time %</li>
<BR>
<li><i>Largest Cached Item</i> is the size \(in bytes\) of the largest item in each category that was cached</li>
<li><i>Largest Item</i> is the size \(in bytes\) of the largest item requested whether it was cached or not</li>

</ul>
),

	'by_web_server'	=> q(
This is a list of all requests by the web server that it was requested from
),

	'denied_by_url'	=> q(
This is a list of all denied requests and the URL that was denied. This is useful for monitoring if your ACL's are set up properly 
),

	'denied_by_client'	=> q(
This is a list of all denied requests and the IP of the client that was denied. This is useful for monitoring if your ACL's are set up properly and if there are some other IP's trying to use your cache
),

#	''	=> q(),

);

# if there was a log that was specified on the command line, read it here
my $log_specified = shift;

#
# Lower the priority to lower CPU consumption - the squid is the no 1!
#
use constant PRIO_PROCESS => 0;
setpriority(PRIO_PROCESS,$$,19);

# if there was a log specified on the command line put it as the only thing in the list of logs to process, otherwise process them all.
my @logs;
if ($log_specified) {
	unless ($log_specified =~ m#^/#) { # if it doesn't appear that the whole path was specified tack on the $log_dir
		$log_specified = $log_dir . "/" . $log_specified;
	}
	push @logs, $log_specified;
} else { 
	opendir (D,$log_dir) or die "Can't open $log_dir!";
		@logs = map { $log_dir . "/" . $_ } sort {$b cmp $a} grep /$log_name*/, readdir(D);
	close (D);
}

# begin the output of the page
print "<HTML><HEAD>";

# Here we call the sub that parses the logs and returns the summary's
my ($First_Time, $Last_Time, $Stats) = Read_Logs($conf_name, @logs);

# put this meta tag because it said to at www.squid-cache.org
print "<meta name='robots' content='noindex,nofollow'>";

# Let people know where the page came from
print "<meta name='GENERATOR' content='squeezer2.pl'>";

print "<TITLE>Statistics from ", scalar localtime($First_Time), " to ", scalar localtime($Last_Time), "</TITLE>\n";
print "</HEAD><BODY>\n";

print "<H1 ALIGN=CENTER>Squid server optimizing information:</H1>\n";
print "<H2 ALIGN=CENTER>Statistics from ", scalar localtime($First_Time), " to ", scalar localtime($Last_Time), "</H2>\n";

if ($Stats_Types_Descriptions{Description}) { # if there is a description, show it.
	print "<H5>", $Stats_Types_Descriptions{Description}, "</H5>\n";
}

# This calls the reporting to show all the hard work we just did
Report_Stats($First_Time, $Last_Time, $Stats);

# show the about screen
about();

print "</BODY></HTML>\n";











sub Read_Conf
{
	#
	# Read info about siblings and refresh_patterns
	# This is taken pretty much verbatim from the original squeezer.pl
	#
	my $conf = shift;
	my @regex;
	my %servers;
	
	
	open (CONF, $conf) or die "Could not open $conf!\n";
	my $i = 0;
	while (<CONF>) {
		if (/^\s*refresh_pattern\s+/) { # Looking for refresh_patterns here
			if (/\s+\-i\s+/) {      # and deciding if they are case sensitive or not
				my ($name, $nthg, $rx, $opts) = split (/\s+/,$_,4); 
				$regex[$i]->{regex} = $rx;
				$regex[$i]->{case} = 1;
				$regex[$i]->{opts} = $opts;
			} else {
				my ($name,  $rx, $opts) = split (/\s+/,$_,3); 
				$regex[$i]->{regex} = $rx;
				$regex[$i]->{case} = 0;
				$regex[$i]->{opts} = $opts;
			}
			$i++;
		}
		if (/^\s*cache_peer\s|cache_host\s/) {
			my ($keyword, $server, $rel, $http, $icp, $opt) = split (/\s+/);
			$servers{relation}->{$server} = $rel;
			$servers{http_port}->{$server} = $http;
			$servers{icp_port}->{$server} = $icp;
			$servers{options}->{$server} = $opt;
		}
	}
	close CONF;
	return (\@regex, \%servers);
}




sub Read_Logs # This is the loop that reads in all the stuff from the log files.
{
	my $conf = shift;
	my @logs = @_;
	my %stats; # this is the hash where I stuff all the info I will need
	           # later for reporting.  it prbly will get fairly large. 
		   # Although it is just summary so it shouldn't be too bad.
	
	my ($Regexes, $Servers) = Read_Conf($conf); # Here we parse the squid.conf and get the list of refresh_patterns and peers
	my $first_time; # here's where the first timestamp we read out of the log files goes
	my $last_time;  # here's where the last timestams we read goes
	
	# These are where we decide what is a hit.  Everything else isn't
	my $cached_fetch = 'SIBLING_HIT|CD_SIBLING_HIT|PARENT_HIT|CD_PARENT_HIT|DEFAULT_PARENT|SINGLE_PARENT|FIRST_UP_PARENT|ROUNDROBIN_PARENT|FIRST_PARENT_MISS|CLOSEST_PARENT_MISS|CLOSEST_PARENT|ROUNDROBIN_PARENT|CACHE_DIGEST_HIT|ANY_PARENT';
	my $cached_hit = 'UDP_HIT|TCP_HIT|TCP_IMS_HIT|TCP_NEGATIVE_HIT|TCP_MEM_HIT|TCP_OFFLINE_HIT|UDP_HIT';
	my $cached_status = 'TCP_REFRESH_HIT/200';

	foreach my $cur_log (@logs) {
		open CURLOG, $cur_log or die "Couldn't open CURLOG, $cur_log: $!";
		while (<CURLOG>) {
			chomp;
			#
			# Do accounting of TCP requests only
			#
			next if (!/ TCP_/o);
			
			# Split line to useful stuff
			my ($time, $elapsed, $remotehost, $status, $bytes, $method, $url, $rfc931, $peerstatus, $mime) = split (/\s+/);
			#
			# Split the rest of data
			#
			my ($hit, $code) = split (/\//, $status);
			my ($fetch, $server) = split (/\//, $peerstatus);
			my $cur_hour = (localtime($time))[2];
			my ($web_server) = $url =~ m#://([^/]+)/#; 
	
			# Here the first and last timestamps in the log files get set
			($first_time = $time) unless $first_time;
			$last_time = $time;

			# and we make sure that $bytes is initialized
			$bytes ||= 0;

			# now we decide whether this request should be counted in the cached stats below using the lists from above
			my $cached_req = 0;
			my $cached_bytes = 0;
			my $cached_elapsed = 0;
			if ($hit =~ /^($cached_hit)$/ || $status =~ /^($cached_status)$/ || $fetch =~ /^($cached_fetch)$/) {
				$cached_req = 1;
				$cached_bytes = $bytes;
				$cached_elapsed = $elapsed;
			}


			# *** these are the descriptions for the variables that are used to store the information that we are gathering
			# 
			# $type is the category that the information is going to be displayed under
			# $item is the individual line within that category
			#
			# {$type}->{$item}->{bytes}
			# 	adds up all the bytes used in the category
			# 	
			# {$type}->{$item}->{elapsed} 
			# 	adds up the total time used in the category
			# 	
			# {$type}->{$item}->{req} 
			# 	is the total number of requests for the category
			#
			# {$type}->{$item}->{largest_bytes} 
			# 	is the largest (in bytes) request for the category
			# 	
			# {$type}->{$item}->{largest_cached_bytes} 
			#	is the largest (in bytes) request that was answered from the cache for the category
			#
			# *** These next items be in each statistic
			#
			# {$type}->{show_cached} 
			# 	is a boolean that we can test later to see if the 
			# 	cached info should be displayed (usually because we recorded it and 
			# 	not displayed when we didn't.
			# 
			# {$type}->{$item}->{cached_req} 
			# 	is the number of requests that were answered from the cache for the category
			# 	
			# {$type}->{$item}->{cached_bytes} 
			# 	is the number of bytes that were answered from the cache for the category
			# 	
			# {$type}->{$item}->{cached_elapsed}
			# 	is the amount of time spent answering requests from the cache for the category
			# 	
			# {$type}->{$item}->{opts}
			#	is the options only used in special cases
			
			# Record totals to be shown and compared to
			$stats{Total}->{show_cached} = 1;
	
			$stats{Total}->{Total}->{largest_bytes} ||= 0;	
			$stats{Total}->{Total}->{largest_cached_bytes} ||= 0;
			
			$stats{Total}->{Total}->{bytes} += $bytes;
			$stats{Total}->{Total}->{elapsed} += $elapsed;
			$stats{Total}->{Total}->{cached_req} += $cached_req;
			$stats{Total}->{Total}->{cached_bytes} += $cached_bytes;
			$stats{Total}->{Total}->{cached_elapsed} += $cached_elapsed;
			$stats{Total}->{Total}->{req}++;
			$stats{Total}->{Total}->{largest_bytes} = $bytes 
				if ($stats{Total}->{Total}->{largest_bytes} < $bytes);
			$stats{Total}->{Total}->{largest_cached_bytes} = $cached_bytes 	
				if ($stats{Total}->{Total}->{largest_cached_bytes} < $cached_bytes);

                        # Status statistics
                        if (SHOW_STATUS_STATS && $status) {
                                $stats{by_status}->{$status}->{largest_bytes} ||= 0;
                                $stats{by_status}->{$status}->{largest_cached_bytes} ||= 0;

                                $stats{by_status}->{$status}->{bytes}   += $bytes;
                                $stats{by_status}->{$status}->{elapsed} += $elapsed;
                                $stats{by_status}->{$status}->{req}++;
                                $stats{by_status}->{$status}->{largest_bytes} = $bytes
                                        if ($stats{by_status}->{$status}->{largest_bytes} < $bytes);
                                $stats{by_status}->{$status}->{largest_cached_bytes} = $cached_bytes
                                        if ($stats{by_status}->{$status}->{largest_cached_bytes} < $cached_bytes);
                        }


			if ($hit) {
				# Hit statistics
				if (SHOW_HIT_STATS) {
					$stats{by_hit}->{$hit}->{largest_bytes} ||= 0;
					$stats{by_hit}->{$hit}->{largest_cached_bytes} ||= 0;

					$stats{by_hit}->{$hit}->{bytes}   += $bytes;
					$stats{by_hit}->{$hit}->{elapsed} += $elapsed;
					$stats{by_hit}->{$hit}->{req}++;
					$stats{by_hit}->{$hit}->{largest_bytes} = $bytes 
						if ($stats{by_hit}->{$hit}->{largest_bytes} < $bytes);
					$stats{by_hit}->{$hit}->{largest_cached_bytes} = $cached_bytes 	
						if ($stats{by_hit}->{$hit}->{largest_cached_bytes} < $cached_bytes);
				}

				
				# Cache statistics
				if ($cached_req) {
					if ($fetch !~ /^($cached_fetch)$/) {
						# Local cache
						$stats{by_cache}->{Local}->{largest_bytes} ||= 0;
						$stats{by_cache}->{Local}->{largest_cached_bytes} ||= 0;
						
						$stats{by_cache}->{Local}->{bytes} += $bytes;
						$stats{by_cache}->{Local}->{elapsed} += $elapsed;
						$stats{by_cache}->{Local}->{req}++;
						$stats{by_cache}->{Local}->{largest_bytes} = $bytes 
							if ($stats{by_cache}->{Local}->{largest_bytes} < $bytes);
	 					$stats{by_cache}->{Local}->{largest_cached_bytes} = $cached_bytes 	
							if ($stats{by_cache}->{Local}->{largest_cached_bytes} < $cached_bytes);
					} else {
						# All remote servers
						$stats{by_cache}->{Remote}->{largest_bytes} ||= 0;
						$stats{by_cache}->{Remote}->{largest_cached_bytes} ||= 0;
						
						$stats{by_cache}->{Remote}->{bytes} += $bytes;
						$stats{by_cache}->{Remote}->{elapsed} += $elapsed;
						$stats{by_cache}->{Remote}->{req}++;
						$stats{by_cache}->{Remote}->{largest_bytes} = $bytes 
							if ($stats{by_cache}->{Remote}->{largest_bytes} < $bytes);
						$stats{by_cache}->{Remote}->{largest_cached_bytes} = $cached_bytes 
							if ($stats{by_cache}->{Remote}->{largest_cached_bytes} < $cached_bytes);
						
						# Each remote server
						$stats{by_cache}->{$server}->{largest_bytes} ||= 0;
						$stats{by_cache}->{$server}->{largest_cached_bytes} ||= 0;
						
						$stats{by_cache}->{$server}->{bytes} += $bytes;
						$stats{by_cache}->{$server}->{elapsed} += $elapsed;
						$stats{by_cache}->{$server}->{req}++;
						$stats{by_cache}->{$server}->{largest_bytes} = $bytes 
							if ($stats{by_cache}->{$server}->{largest_bytes} < $bytes);
						$stats{by_cache}->{$server}->{largest_cached_bytes} = $cached_bytes 
							if ($stats{by_cache}->{$server}->{largest_cached_bytes} < $cached_bytes);
					}
					# Total Cached
					$stats{by_cache}->{Total}->{largest_bytes} ||= 0;
					$stats{by_cache}->{Total}->{largest_cached_bytes} ||= 0;
									
					$stats{by_cache}->{Total}->{bytes} += $bytes;
					$stats{by_cache}->{Total}->{elapsed} += $elapsed;
					$stats{by_cache}->{Total}->{req}++;
					$stats{by_cache}->{Total}->{largest_bytes} = $bytes 
						if ($stats{by_cache}->{Total}->{largest_bytes} < $bytes);
					$stats{by_cache}->{Total}->{largest_cached_bytes} = $cached_bytes 
						if ($stats{by_cache}->{Total}->{largest_cached_bytes} < $cached_bytes);

				} else {
					# Uncached
					$stats{by_cache}->{Direct}->{largest_bytes} ||= 0;
						
					$stats{by_cache}->{Direct}->{bytes} += $bytes;
					$stats{by_cache}->{Direct}->{elapsed} += $elapsed;
					$stats{by_cache}->{Direct}->{req}++;
					$stats{by_cache}->{Direct}->{largest_bytes} = $bytes 
						if ($stats{by_cache}->{Direct}->{largest_bytes} < $bytes);
					$stats{by_cache}->{Direct}->{largest_cached_bytes} = 0; 
				}
			}


		
			# Size statistics
			if (SHOW_SIZE_STATS && $bytes) {
				SIZE: while (1) { # allow us to exit out when we match the size. I have to do this while loop cuZ I don't know how to make the {More} below work without it.
					for (my $i = 1; $i < 1000000000; $i *= 10) { # foreach multiple of ten see if it it right
						if ($bytes < $i) {
							$stats{by_size}->{show_cached} = 1;	

							$stats{by_size}->{$i}->{largest_bytes} ||= 0;
							$stats{by_size}->{$i}->{largest_cached_bytes} ||= 0;
			
							$stats{by_size}->{$i}->{bytes}   += $bytes;
							$stats{by_size}->{$i}->{elapsed} += $elapsed;
							$stats{by_size}->{$i}->{cached_req} += $cached_req;
							$stats{by_size}->{$i}->{cached_bytes} += $cached_bytes;
							$stats{by_size}->{$i}->{cached_elapsed} += $cached_elapsed;
							$stats{by_size}->{$i}->{req}++;
							$stats{by_size}->{$i}->{largest_bytes} = $bytes 
								if ($stats{by_size}->{$i}->{largest_bytes} < $bytes);
							$stats{by_size}->{$i}->{largest_cached_bytes} = $cached_bytes 	
								if ($stats{by_size}->{$i}->{largest_cached_bytes} < $cached_bytes);
	
							last SIZE;
						}
					}
					# if it is larger than the largest size above then stuff it in here.
					$stats{by_size}->{More}->{largest_bytes} ||= 0;
					$stats{by_size}->{More}->{largest_cached_bytes} ||= 0;
		
					$stats{by_size}->{More}->{bytes}   += $bytes;
					$stats{by_size}->{More}->{elapsed} += $elapsed;
					$stats{by_size}->{More}->{req}++;
					$stats{by_size}->{More}->{largest_bytes} = $bytes 
						if ($stats{by_size}->{More}->{largest_bytes} < $bytes);
					$stats{by_size}->{More}->{largest_cached_bytes} = $cached_bytes 	
						if ($stats{by_size}->{More}->{largest_cached_bytes} < $cached_bytes);

					last SIZE;
				}
			}

			# Stats by Hour
			if (SHOW_HOUR_STATS && $cur_hour) {
				$stats{by_hour}->{show_cached} = 1;

				$stats{by_hour}->{$cur_hour}->{largest_bytes} ||= 0;
				$stats{by_hour}->{$cur_hour}->{largest_cached_bytes} ||= 0;
	
				$stats{by_hour}->{$cur_hour}->{bytes}   += $bytes;
				$stats{by_hour}->{$cur_hour}->{elapsed} += $elapsed;
				$stats{by_hour}->{$cur_hour}->{cached_req} += $cached_req;
				$stats{by_hour}->{$cur_hour}->{cached_bytes} += $cached_bytes;
				$stats{by_hour}->{$cur_hour}->{cached_elapsed} += $cached_elapsed;
				$stats{by_hour}->{$cur_hour}->{req}++;
				$stats{by_hour}->{$cur_hour}->{largest_bytes} = $bytes 
					if ($stats{by_hour}->{$cur_hour}->{largest_bytes} < $bytes);
				$stats{by_hour}->{$cur_hour}->{largest_cached_bytes} = $cached_bytes 	
					if ($stats{by_hour}->{$cur_hour}->{largest_cached_bytes} < $cached_bytes);

			}

			# Stats of Denied by URL
			if (SHOW_DENIED_BY_URL && ($hit =~ /DENIED/) && $url) {
				$stats{denied_by_url}->{$url}->{largest_bytes} ||= 0;
				$stats{denied_by_url}->{$url}->{largest_cached_bytes} ||= 0;
	
				$stats{denied_by_url}->{$url}->{bytes}   += $bytes;
				$stats{denied_by_url}->{$url}->{elapsed} += $elapsed;
				$stats{denied_by_url}->{$url}->{req}++;
				$stats{denied_by_url}->{$url}->{largest_bytes} = $bytes 
					if ($stats{denied_by_url}->{$url}->{largest_bytes} < $bytes);
				$stats{denied_by_url}->{$url}->{largest_cached_bytes} = $cached_bytes 	
					if ($stats{denied_by_url}->{$url}->{largest_cached_bytes} < $cached_bytes);

			}
			
			# Stats of Denied by Client 
			if (SHOW_DENIED_BY_CLIENT && ($hit =~ /DENIED/) && $remotehost) {
				$stats{denied_by_client}->{$remotehost}->{largest_bytes} ||= 0;
				$stats{denied_by_client}->{$remotehost}->{largest_cached_bytes} ||= 0;
	
				$stats{denied_by_client}->{$remotehost}->{bytes}   += $bytes;
				$stats{denied_by_client}->{$remotehost}->{elapsed} += $elapsed;
				$stats{denied_by_client}->{$remotehost}->{req}++;
				$stats{denied_by_client}->{$remotehost}->{largest_bytes} = $bytes 
					if ($stats{denied_by_client}->{$remotehost}->{largest_bytes} < $bytes);
				$stats{denied_by_client}->{$remotehost}->{largest_cached_bytes} = $cached_bytes 	
					if ($stats{denied_by_client}->{$remotehost}->{largest_cached_bytes} < $cached_bytes);

			}
			
			# Stats by mime type
			if (SHOW_TYPE_STATS && $mime) {
				$mime =~ tr/A-Z/a-z/;
				$stats{by_type}->{show_cached} = 1;
				$stats{by_type}->{$mime}->{largest_bytes} ||= 0;
				$stats{by_type}->{$mime}->{largest_cached_bytes} ||= 0;
				
				$stats{by_type}->{$mime}->{bytes}   += $bytes;
				$stats{by_type}->{$mime}->{elapsed} += $elapsed;
				$stats{by_type}->{$mime}->{cached_req} += $cached_req;
				$stats{by_type}->{$mime}->{cached_bytes} += $cached_bytes;
				$stats{by_type}->{$mime}->{cached_elapsed} += $cached_elapsed;
				$stats{by_type}->{$mime}->{req}++;
				$stats{by_type}->{$mime}->{largest_bytes} = $bytes 
					if ($stats{by_type}->{$mime}->{largest_bytes} < $bytes);
				$stats{by_type}->{$mime}->{largest_cached_bytes} = $cached_bytes 
					if ($stats{by_type}->{$mime}->{largest_cached_bytes} < $cached_bytes);

			}
			
			
			# Fetch statistics
			if (SHOW_FETCH_STATS && $fetch) {
				$stats{by_fetch}->{$fetch}->{largest_bytes} ||= 0;
				$stats{by_fetch}->{$fetch}->{largest_cached_bytes} ||= 0;
				
				$stats{by_fetch}->{$fetch}->{bytes} +=$bytes;
				$stats{by_fetch}->{$fetch}->{elapsed} +=$elapsed;
				$stats{by_fetch}->{$fetch}->{req}++;
				$stats{by_fetch}->{$fetch}->{largest_bytes} = $bytes 
					if ($stats{by_fetch}->{$fetch}->{largest_bytes} < $bytes);
				$stats{by_fetch}->{$fetch}->{largest_cached_bytes} = $cached_bytes 
					if ($stats{by_fetch}->{$fetch}->{largest_cached_bytes} < $cached_bytes);
			}
		

			# Client statistics
			if (SHOW_CLIENT_STATS && $remotehost) {
				$stats{by_client}->{show_cached} = 1;
				$stats{by_client}->{$remotehost}->{largest_bytes} ||= 0;
				$stats{by_client}->{$remotehost}->{largest_cached_bytes} ||= 0;

				$stats{by_client}->{$remotehost}->{bytes} += $bytes;
				$stats{by_client}->{$remotehost}->{elapsed} += $elapsed;
				$stats{by_client}->{$remotehost}->{cached_req} += $cached_req;
				$stats{by_client}->{$remotehost}->{cached_bytes} += $cached_bytes;
				$stats{by_client}->{$remotehost}->{cached_elapsed} += $cached_elapsed;
				$stats{by_client}->{$remotehost}->{req}++;
				$stats{by_client}->{$remotehost}->{largest_bytes} = $bytes 
					if ($stats{by_client}->{$remotehost}->{largest_bytes} < $bytes);
				$stats{by_client}->{$remotehost}->{largest_cached_bytes} = $cached_bytes 
					if ($stats{by_client}->{$remotehost}->{largest_cached_bytes} < $cached_bytes);

			}
			
			# Web Server statistics
			if (SHOW_WEB_SERVER_STATS && $web_server) {
				$stats{by_web_server}->{show_cached} = 1;

				$stats{by_web_server}->{$web_server}->{largest_bytes} ||= 0;
				$stats{by_web_server}->{$web_server}->{largest_cached_bytes} ||= 0;

				$stats{by_web_server}->{$web_server}->{bytes} += $bytes;
				$stats{by_web_server}->{$web_server}->{elapsed} += $elapsed;
				$stats{by_web_server}->{$web_server}->{cached_req} += $cached_req;
				$stats{by_web_server}->{$web_server}->{cached_bytes} += $cached_bytes;
				$stats{by_web_server}->{$web_server}->{cached_elapsed} += $cached_elapsed;
				$stats{by_web_server}->{$web_server}->{req}++;
				$stats{by_web_server}->{$web_server}->{largest_bytes} = $bytes 
					if ($stats{by_web_server}->{$web_server}->{largest_bytes} < $bytes);
				$stats{by_web_server}->{$web_server}->{largest_cached_bytes} = $cached_bytes 
					if ($stats{by_web_server}->{$web_server}->{largest_cached_bytes} < $cached_bytes);

			}
			
			# Regex statistics
			if (SHOW_REGEX_STATS && $Regexes) {
				$stats{by_regex}->{show_cached} = 1;
				REGEX: foreach my $regex (@$Regexes) {
					# I don't recall why I have to initilize all of these, but I do know it threw errors when I didn't.  Someday removing some of these lines will be possible
					$stats{by_regex}->{$regex->{regex}}->{bytes} ||= 0;
					$stats{by_regex}->{$regex->{regex}}->{elapsed} ||= 0;
					$stats{by_regex}->{$regex->{regex}}->{cached_req} ||= 0;
					$stats{by_regex}->{$regex->{regex}}->{cached_bytes} ||= 0;
					$stats{by_regex}->{$regex->{regex}}->{cached_req} ||= 0;
					$stats{by_regex}->{$regex->{regex}}->{cached_bytes} ||= 0;
					$stats{by_regex}->{$regex->{regex}}->{cached_elapsed} ||= 0;
					$stats{by_regex}->{$regex->{regex}}->{req} ||= 0;
					$stats{by_regex}->{$regex->{regex}}->{opts} ||= $regex->{opts};
					$stats{by_regex}->{$regex->{regex}}->{largest_bytes} ||= 0;
					$stats{by_regex}->{$regex->{regex}}->{largest_cached_bytes} ||= 0;
					
					if ($regex->{case} ? $url =~ /$regex->{regex}/ix : $url =~ /$regex->{regex}/x) {
						$stats{by_regex}->{$regex->{regex}}->{bytes} += $bytes;
						$stats{by_regex}->{$regex->{regex}}->{elapsed} += $elapsed;
						$stats{by_regex}->{$regex->{regex}}->{cached_req} += $cached_req;
						$stats{by_regex}->{$regex->{regex}}->{cached_bytes} += $cached_bytes;
						$stats{by_regex}->{$regex->{regex}}->{cached_req} += $cached_req;
						$stats{by_regex}->{$regex->{regex}}->{cached_bytes} += $cached_bytes;
						$stats{by_regex}->{$regex->{regex}}->{cached_elapsed} += $cached_elapsed;
						$stats{by_regex}->{$regex->{regex}}->{req}++;
						$stats{by_regex}->{$regex->{regex}}->{largest_bytes} = $bytes 
							if ($stats{by_regex}->{$regex->{regex}}->{largest_bytes} < $bytes);
						$stats{by_regex}->{$regex->{regex}}->{largest_cached_bytes} = $cached_bytes 
							if ($stats{by_regex}->{$regex->{regex}}->{largest_cached_bytes} < $cached_bytes);

						last REGEX;

					}
				}
			}
			
#
# ATTENTION!!! Do not place anything for ALL lines below the next source line
# it will reject anything DIRECT!!!
# go next if it is fetched directly or from this cache
#
#			next if (m#DIRECT/# || m#TIMEOUT_DIRECT/# || m# - NONE/- #); 
			next if (m#DIRECT/# || m#TIMEOUT_DIRECT/#); 
			
			# Server Stats
			if (SHOW_SERVER_STATS && $server) {
				$stats{by_srv}->{$server}->{largest_bytes} ||= 0;
				$stats{by_srv}->{$server}->{largest_cached_bytes} ||= 0;
				my $opts = (
					(defined $Servers->{relation}->{$server} ? $Servers->{relation}->{$server} : "")
					. " " . 
					(defined $Servers->{options}->{$server} ? $Servers->{options}->{$server} : "")
				);
				$stats{by_srv}->{$server}->{opts} ||= $opts;
				
				$stats{by_srv}->{$server}->{bytes} += $bytes;
				$stats{by_srv}->{$server}->{elapsed} += $elapsed;
				$stats{by_srv}->{$server}->{req}++;
				$stats{by_srv}->{$server}->{largest_bytes} = $bytes 
					if ($stats{by_srv}->{$server}->{largest_bytes} < $bytes);
				$stats{by_srv}->{$server}->{largest_cached_bytes} = $cached_bytes 
					if ($stats{by_srv}->{$server}->{largest_cached_bytes} < $cached_bytes);

				$stats{by_srv}->{Total}->{largest_bytes} ||= 0;
				$stats{by_srv}->{Total}->{largest_cached_bytes} ||= 0;
				$stats{by_srv}->{Total}->{opts} = "&nbsp;";
					
				$stats{by_srv}->{Total}->{bytes} += $bytes;
				$stats{by_srv}->{Total}->{elapsed} += $elapsed;
				$stats{by_srv}->{Total}->{req}++;
				$stats{by_srv}->{Total}->{largest_bytes} = $bytes 
					if ($stats{by_srv}->{Total}->{largest_bytes} < $bytes);
				$stats{by_srv}->{Total}->{largest_cached_bytes} = $cached_bytes 
					if ($stats{by_srv}->{Total}->{largest_cached_bytes} < $cached_bytes);
			}

		}
		close CURLOG;
	}
	# return all the information we gathered.
	return ($first_time, $last_time, \%stats);
}


sub Report_Stats
{
	my $first_time = shift; # The first timestamp we saw from the logs
	my $last_time = shift;  # The last timestamp that was in the logs
	my $stats = shift;      # The hash reference that contains all the info that we gathered and are going to report on.

	# Making the total number of requests easier to get to with a shorter variable cuz it is used a lot
	my $total = $stats->{Total}->{Total};

	# Initalize a hash that will be passed to some other subs for special reporting of totals
	my %cache_stats;
	$cache_stats{Total} = $total;
	$cache_stats{Cached_Total} = $stats->{by_cache}->{Total};
	$cache_stats{Cached_Local} = $stats->{by_cache}->{Local};
	$cache_stats{Cached_Other} = $stats->{by_cache}->{Remote};
	$cache_stats{Direct} = $stats->{by_cache}->{Direct};

	# This is the main summery that shows all sorts of interesting info first off to give you an overview
	Show_General_Summary($first_time, $last_time, \%cache_stats);

	# this is generally the descriptions of all the columns that will be used in all the columns below.
	if ($Stats_Types_Descriptions{All}) { # if there is a description, show it.
		print "<H3><U>";
		print $Stats_Types_Headers{All} ? $Stats_Types_Headers{All} : 'Descriptions used throughout';
		print ":</U></H3>\n";
		
		print "<H5>", $Stats_Types_Descriptions{All}, "</H5>\n";
		print "<hr>\n";
	}

	# This is a report of items that were cached
	Show_Cache_Summary($first_time, $last_time, \%cache_stats);
	
	# Now we get into the main reporting,  we are going through each type of report
	foreach my $type (sort keys %$stats) {
		print "<H3><U>";
		print $Stats_Types_Headers{$type} ? $Stats_Types_Headers{$type} : $type;
		print ":</U></H3>\n";

		if ($Stats_Types_Descriptions{$type}) { # if there is a description, show it.
			print "<H5>", $Stats_Types_Descriptions{$type}, "</H5>\n";
		}

		# Start the table
		print "<TABLE TABLE_CELL_BORDER TABLE_CELLSPACING TABLE_CELLPADDING>\n";

		# $i is used to repeat the headers every 25 or so rows and to choose what color each row should be
		my $i = 0;
		# This is each line in this type.  Someday the sorting will be moved out to a hash at the beginning so it can be set to sort per type, but for now, this works.
		foreach my $item (sort { $a eq 'show_cached' || $b eq 'show_cached' ? # Is it the show_cached key?
					         $a cmp $b :                          # if it is, just doesn't matter, if I could just skip that one that would be kewl
						 ($a =~ /^\d+$/ && $b =~ /^\d+$/) ? # if not, then is the item a number?
						 	($a <=> $b) :               # if so, sort it that way
							($stats->{$type}->{$b}->{bytes} <=> $stats->{$type}->{$a}->{bytes}) # otherwise sort backwards by bytes
				       } keys %{ $stats->{$type} } ) {

			next if $item eq 'show_cached'; # don't try to show the show_cached item

			unless ($i % 25) {
				# Show the title
				print "<TR>\n\t<TH>&nbsp;\n";
		
				# Only show the options line if it is by_regex or by_srv
				if ($type eq 'by_regex' || $type eq 'by_srv') {
					print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>Options\n";
				}
				
				# cached_reqs - only show the cache info if we say we have it
				if ($stats->{$type}->{show_cached}) {
					print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>Cached<BR>Requests\n";
					print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>Cached<BR>Req/s\n";
					print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>Cached<BR>% of Reqs\n";
					print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>Cached<BR>Reqs Graph\n";
				
					print "\t<TH>&nbsp;\n";
				}
				
				# Requests
				print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>Requests\n";
				print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>Req/s\n";
				print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>Req %\n";
				print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>Req Graph\n";
				
				print "\t<TH>&nbsp;\n";
	
				# cached_bytes - only show the cache info if we say we have it
				if ($stats->{$type}->{show_cached}) {
					print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>Cached<BR>Bytes\n";
					print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>Cached<BR>B/s\n";
					print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>Cached<BR>% of B\n";
					print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>Cached<BR>Bytes Graph\n";
					print "\t<TH>&nbsp;\n";
				}
				
				# Bytes
				print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>kBytes\n";
				print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>B/s\n";
				print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>kB %\n";
				print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>kB Graph\n";
				
				print "\t<TH>&nbsp;\n";
				
				# Time
				print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>Time\n";
				print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>Time %\n";
				print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>Time Graph\n";
	
				print "\t<TH>&nbsp;\n";
	
				# Largest items
				print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>Largest Cached Item\n";
				print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>Largest Item\n";
			}	

			# Here we find out if the item is a all digits and if so, add the comma's. This is pretty much just for the by_size item, but it will work for any that are added
			my $item_title = $item;
			if ($item =~ /^\d+$/) {
				$item_title = Commify($item);
			}

			# Choose which color to make the row
			my $row_bg_color = $i % 2 ? COLOR_TABLE_ROW_EVEN : COLOR_TABLE_ROW_ODD;
			# make the next row different
			$i++;

			# Start the row.
			print "<TR>\n";
			
			# Row Header
			print "\t<TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><I>$item_title</I>\n";

			# Only show the options line if it is by_regex or by_srv
			if ($type eq 'by_regex' || $type eq 'by_srv') {
				print "\t<TD BGCOLOR='$row_bg_color' ALIGN=RIGHT>$stats->{$type}->{$item}->{opts}\n";
			}

			# cached_reqs - only show the cache info if it says we have it
			if ($stats->{$type}->{show_cached}) {
				#printf "\t<TD BGCOLOR='$row_bg_color' ALIGN=RIGHT>%s\n", $stats->{$type}->{$item}->{cached_elapsed};

				# cached_req's for this item
				printf "\t<TD BGCOLOR='$row_bg_color' ALIGN=RIGHT>%s\n", Commify($stats->{$type}->{$item}->{cached_req}) || 0;

				# cached_req's per second
				printf "\t<TD BGCOLOR='$row_bg_color' ALIGN=RIGHT>%s\n", Commify( 
					sprintf "%5.2f", 
						$stats->{$type}->{$item}->{cached_elapsed} ? 
						$stats->{$type}->{$item}->{cached_req} / ($stats->{$type}->{$item}->{cached_elapsed} / 1000) :
						0);

				# calculate cached_req_percent as percent of item_reqs
				my $cached_percent_req = ($stats->{$type}->{$item}->{req} ? 
								100 * $stats->{$type}->{$item}->{cached_req} / $stats->{$type}->{$item}->{req} :
								0
							); 

				# item_cached_req percent of item_reqs
				printf "\t<TD BGCOLOR='$row_bg_color' ALIGN=RIGHT>%2.2f\n", $cached_percent_req;

				# graph of item_cached_bytes percent of item_bytes
				print "\t<TD BGCOLOR='$row_bg_color' ALIGN=LEFT VALIGN=MIDDLE><FONT SIZE=-2>", ("|" x $cached_percent_req), "\n";

				# Row Header, again so it doesn't get lost
				print "\t<TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><I>$item_title</I>\n";

			}

			# total number of requests
			printf "\t<TD BGCOLOR='$row_bg_color' ALIGN=RIGHT>%s\n", Commify($stats->{$type}->{$item}->{req});

			# Requests per second
			printf "\t<TD BGCOLOR='$row_bg_color' ALIGN=RIGHT>%2.2f\n", (
				$stats->{$type}->{$item}->{elapsed} ? 
					($stats->{$type}->{$item}->{req} / ($stats->{$type}->{$item}->{elapsed} / 1000))  :
					0
				);

			# calculate percentage of item_requests to total_requests
			my $percent_req = (
				$total->{req} ? 
					(100 * $stats->{$type}->{$item}->{req} / $total->{req})  :
					0
				);

			# percentage of item_requests
			printf "\t<TD BGCOLOR='$row_bg_color' ALIGN=RIGHT>%2.2f\n", $percent_req;

			# graph of percentage of item_requests
			print "\t<TD BGCOLOR='$row_bg_color' ALIGN=LEFT VALIGN=MIDDLE><FONT SIZE=-2>", ("|" x $percent_req), "\n";

			# Row Header, again so it doesn't get lost
			print "\t<TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><I>$item_title</I>\n";

			# cached_bytes - only show cache info if we say we have it
			if ($stats->{$type}->{show_cached}) {
				# bytes cached for this item
				printf "\t<TD BGCOLOR='$row_bg_color' ALIGN=RIGHT>%s\n", Commify(sprintf "%5.2f", $stats->{$type}->{$item}->{cached_bytes} / 1024) || 0;
				
				# cached bytes per second
				printf "\t<TD BGCOLOR='$row_bg_color' ALIGN=RIGHT>%s\n", Commify(
					sprintf "%5.2f", 
						$stats->{$type}->{$item}->{cached_elapsed} ? 
						$stats->{$type}->{$item}->{cached_bytes} / ($stats->{$type}->{$item}->{cached_elapsed} / 1000) :
						0);
				
				#printf "\t<TD BGCOLOR='$row_bg_color' ALIGN=RIGHT>%s\n", $stats->{$type}->{$item}->{cached_bytes};

				# calculate cached_bytes_percent
				my $cached_percent_bytes = ($stats->{$type}->{$item}->{bytes} ? 
								100 * $stats->{$type}->{$item}->{cached_bytes} / $stats->{$type}->{$item}->{bytes} :
								0
						       ); 

				# item_cached_bytes percent of item_bytes
				printf "\t<TD BGCOLOR='$row_bg_color' ALIGN=RIGHT>%2.2f\n", $cached_percent_bytes;

				# graph of item_cached_bytes percent of item_bytes
				print "\t<TD BGCOLOR='$row_bg_color' ALIGN=LEFT VALIGN=MIDDLE><FONT SIZE=-2>", ("|" x $cached_percent_bytes), "\n";
				
				# Row Header
				print "\t<TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><I>$item_title</I>\n";
			}

			# kBytes
			printf "\t<TD BGCOLOR='$row_bg_color' ALIGN=RIGHT>%s\n", Commify(sprintf "%5.2f", $stats->{$type}->{$item}->{bytes} / 1024);
			#printf "\t<TD BGCOLOR='$row_bg_color' ALIGN=RIGHT>%s\n", $stats->{$type}->{$item}->{bytes};

			# bytes per second
			printf "\t<TD BGCOLOR='$row_bg_color' ALIGN=RIGHT>%s\n", (
				$stats->{$type}->{$item}->{elapsed} ? 
					Commify(sprintf "%2.2f", $stats->{$type}->{$item}->{bytes} / ($stats->{$type}->{$item}->{elapsed} / 1000)) : 
					0
				);

			# calculate percentage of item_bytes to total_bytes
			my $percent_bytes = (
				$total->{bytes} ? 
					100 * $stats->{$type}->{$item}->{bytes} / $total->{bytes} : 
					0
				);

			# percentage of item_bytes
			printf "\t<TD BGCOLOR='$row_bg_color' ALIGN=RIGHT>%2.2f\n", $percent_bytes;
			
			# graph of percentage of item_bytes
			print "\t<TD BGCOLOR='$row_bg_color' ALIGN=LEFT VALIGN=MIDDLE><FONT SIZE=-2>", ("|" x $percent_bytes), "\n";

			# Row Header, again so it doesn't get lost
			print "\t<TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><I>$item_title</I>\n";

			# total time elapsed on item
			printf "\t<TD BGCOLOR='$row_bg_color' ALIGN=RIGHT>%s\n", Timeify($stats->{$type}->{$item}->{elapsed});

			# calculate percentage of item_elapsed to total_elapsed
			my $percent_elapsed = (
				$total->{bytes} ? 
					100 * $stats->{$type}->{$item}->{elapsed} / $total->{elapsed} : 
					0
				);

			# percentage of item_elapsed
			printf "\t<TD BGCOLOR='$row_bg_color' ALIGN=RIGHT>%2.2f\n", $percent_elapsed;

			# graph of item_elapsed
			print "\t<TD BGCOLOR='$row_bg_color' ALIGN=LEFT VALIGN=MIDDLE><FONT SIZE=-2>", ("|" x $percent_elapsed), "\n";

			# Row Header, again so it doesn't get lost
			print "\t<TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><I>$item_title</I>\n";

			# Largest cached item in category
			printf "\t<TD BGCOLOR='$row_bg_color' ALIGN=RIGHT>%s\n", Commify($stats->{$type}->{$item}->{largest_cached_bytes});

			# Largest item in category
			printf "\t<TD BGCOLOR='$row_bg_color' ALIGN=RIGHT>%s\n", Commify($stats->{$type}->{$item}->{largest_bytes});


			# time elapsed as an epoch,  don't show unless debugging
			#printf "\t<TD BGCOLOR='$row_bg_color' ALIGN=RIGHT>%s\n", ($stats->{$type}->{$item}->{elapsed} / 1000);

# Uncomment this to show all available columns
#			foreach (sort keys %{ $stats->{$type}->{$item} } ) {
#				print "\t<TD>", $_, ": ", $stats->{$type}->{$item}->{$_}, "\n";
#			}
		}
		print "</TABLE>\n";
		print "<HR>\n";
	}
	
	# This shows the amount of system time the script has been running. This is done right at the end, it gives an idea of how many lines/s of logs we can process.
	Show_System_Profile($total->{req});
}




sub Show_General_Summary
{
#
# Show some general statistics
# 
	my ($start, $finish, $stats) = @_;

	my $total_time = $finish - $start;
	my $hours = ($total_time / 60 / 60);
	
	print "\n<H3><U>General:</U></H3>\n";

	if ($Stats_Types_Descriptions{General}) { # if there is a description, show it.
		print "<H5>", $Stats_Types_Descriptions{General}, "</H5>\n";
	}

	# Here are the dates and how much time the logs we parsed covered.
	print "<TABLE TABLE_CELL_BORDER TABLE_CELLSPACING TABLE_CELLPADDING>\n";
	print "<TR><TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><B>Start Date";
	printf    "<TD BGCOLOR='" . COLOR_TABLE_ROW_EVEN . "' ALIGN=RIGHT> %s\n", 
		scalar localtime($start);
		
	print "<TR><TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><B>End Date</B>";
	printf    "<TD BGCOLOR='" . COLOR_TABLE_ROW_ODD . "' ALIGN=RIGHT>%s\n", 
		scalar localtime($finish);
		
	print "<TR><TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><B>Total Time (hh:mm:ss)</B>";
	printf    "<TD BGCOLOR='" . COLOR_TABLE_ROW_EVEN . "' ALIGN=RIGHT>%s\n", 
		Timeify($total_time * 1000);
	
	# a summary of bytes per hour.
	print "<TR><TD COLSPAN=2 BGCOLOR='" . COLOR_TABLE_COL_HEAD . "' ALIGN=CENTER><SMALL>kBytes Per Hour</SMALL></TD></TR>\n";
	
	print "<TR><TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><I>Cached kBytes/Hour</I>";
	printf    "<TD BGCOLOR='" . COLOR_TABLE_ROW_ODD . "' ALIGN=RIGHT><I>%s</I>\n", 
		Commify(sprintf "%5.2f", $stats->{Cached_Total}->{bytes} / 1024 / $hours);
		
	print "<TR><TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><I>Direct kBytes/Hour</I>";
	printf    "<TD BGCOLOR='" . COLOR_TABLE_ROW_EVEN . "' ALIGN=RIGHT><I>%s</I>\n", 
		Commify(sprintf "%5.2f", $stats->{Direct}->{bytes} / 1024 / $hours);
		
	print "<TR><TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><B>Total kBytes/Hour</B>";
	printf    "<TD BGCOLOR='" . COLOR_TABLE_ROW_ODD . "' ALIGN=RIGHT>%s\n", 
		Commify(sprintf "%5.2f", $stats->{Total}->{bytes} / 1024 / $hours);
		
	# a summmary of requests per hour
	print "<TR><TD COLSPAN=2 BGCOLOR='" . COLOR_TABLE_COL_HEAD . "' ALIGN=CENTER><SMALL>Reqs Per Hour</SMALL></TD></TR>\n";
	
	print "<TR><TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><I>Cached Reqs/Hour</I>";
	printf    "<TD BGCOLOR='" . COLOR_TABLE_ROW_EVEN . "' ALIGN=RIGHT><I>%s</I>\n", 
		Commify(sprintf "%5.2f", $stats->{Cached_Total}->{req} / $hours);
		
	print "<TR><TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><I>Direct Reqs/Hour</I>";
	printf    "<TD BGCOLOR='" . COLOR_TABLE_ROW_ODD . "' ALIGN=RIGHT><I>%s</I>\n", 
		Commify(sprintf "%5.2f", $stats->{Direct}->{req} / $hours);
		
	print "<TR><TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><B>Total Reqs/Hour</B>";
	printf    "<TD BGCOLOR='" . COLOR_TABLE_ROW_EVEN . "' ALIGN=RIGHT>%s\n", 
		Commify(sprintf "%5.2f", $stats->{Total}->{req} / $hours);
	
	# a summary of Average Object sizes
	print "<TR><TD COLSPAN=2 BGCOLOR='" . COLOR_TABLE_COL_HEAD . "' ALIGN=CENTER><SMALL>Average Object Size</SMALL></TD></TR>\n";
	
	print "<TR><TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><I>Average Cached Object Size</I>";
	printf    "<TD BGCOLOR='" . COLOR_TABLE_ROW_ODD . "' ALIGN=RIGHT><I>%s kbytes</I>\n", 
		Commify( sprintf "%5.2f", $stats->{Cached_Total}->{req} ? ($stats->{Cached_Total}->{bytes} / 1024) / $stats->{Cached_Total}->{req} : 0 );
		
	print "<TR><TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><I>Average Direct Object Size</I>";
	printf    "<TD BGCOLOR='" . COLOR_TABLE_ROW_EVEN . "' ALIGN=RIGHT><I>%s kbytes</I>\n", 
		Commify( sprintf "%5.2f", $stats->{Direct}->{req} ? ($stats->{Direct}->{bytes} / 1024) / $stats->{Direct}->{req} : 0 );
		
	print "<TR><TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><B>Average Object Size</B>";
	printf    "<TD BGCOLOR='" . COLOR_TABLE_ROW_ODD . "' ALIGN=RIGHT>%s kbytes\n", 
		Commify( sprintf "%5.2f", $stats->{Total}->{req} ? ($stats->{Total}->{bytes} / 1024) / $stats->{Total}->{req} : 0 );
	
	# some other summary info
	print "<TR><TD COLSPAN=2 BGCOLOR='" . COLOR_TABLE_COL_HEAD . "' ALIGN=CENTER><SMALL>Other</SMALL></TD></TR>\n";

	print "<TR><TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><B>Hit Rate</B>";
	printf    "<TD BGCOLOR='" . COLOR_TABLE_ROW_ODD . "' ALIGN=RIGHT>%s%%\n", 
		Commify( sprintf "%5.2f", $stats->{Total}->{req} ? 100 * $stats->{Cached_Total}->{req} / $stats->{Total}->{req} : 0 );
	
	print "<TR><TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><B>Bandwidth Savings Total</B>";
	printf    "<TD BGCOLOR='" . COLOR_TABLE_CELL_SPECIAL . "' ALIGN=RIGHT>%s kbytes\n", 
		Commify( sprintf "%5.2f", $stats->{Cached_Total}->{bytes} / 1024 );
		
	print "<TR><TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><B>Bandwidth Savings Percent</B>";
	printf    "<TD BGCOLOR='" . COLOR_TABLE_ROW_ODD . "' ALIGN=RIGHT>%s%%\n", 
		Commify(sprintf "%5.2f", 
				($stats->{Total}->{bytes} ? 
				100 * $stats->{Cached_Total}->{bytes} / $stats->{Total}->{bytes} : 
				0) 
		);
		
	print "<TR><TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><B>Average Speed Increase</B>";
	
	# Calculating the kBytes per second for total and direct so we can find out how much faster the caching made it
	my $total_speed = $stats->{Total}->{elapsed} ? $stats->{Total}->{bytes} / $stats->{Total}->{elapsed} : 0;
	my $direct_speed = $stats->{Direct}->{elapsed} ? $stats->{Direct}->{bytes} / $stats->{Direct}->{elapsed} : 0;

	printf    "<TD BGCOLOR='" . COLOR_TABLE_CELL_SPECIAL . "' ALIGN=RIGHT>%s%%\n", Commify(sprintf "%5.2f", 
		($direct_speed ? 100 * (($total_speed / $direct_speed) - 1) : 0) );
	print "</TABLE>";
	print "<HR>\n";
}

sub Show_Cache_Summary
{
#
# Show some cache statistics
# 
	my ($start, $finish, $stats) = @_;

	# Calculate some stuff to be used later
	my $total_time = $finish - $start;
	my $hours = ($total_time / 60 / 60);
	# This is used a bunch, cuz we are comparing most of the stuff here to this
	my $direct_speed = $stats->{Direct}->{elapsed} ? $stats->{Direct}->{bytes} / ($stats->{Direct}->{elapsed} / 1000) : 0;
	
	print "\n<H3><U>Cache Statistics:</U></H3>\n";

	if ($Stats_Types_Descriptions{cache_stats}) { # if there is a description, show it.
		print "<H5>", $Stats_Types_Descriptions{cache_stats}, "</H5>\n";
	}

	# Start the table and show the headers
	print "<TABLE TABLE_CELL_BORDER TABLE_CELLSPACING TABLE_CELLPADDING>\n";
	print "\t<TH>&nbsp;\n";
	print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>Requests\n";
	print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>kBytes\n";
	print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>B/s\n";
	print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>kB %\n";
	print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>kB Graph\n";
	print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>kB Times<BR>to Direct\n";
	print "\t<TH BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'>kB Times<BR>Graph\n";
	
	my $i = 0;
	foreach my $item (sort keys %$stats) {
		$stats->{$item}->{req} ||= 0;
		$stats->{$item}->{bytes} ||= 0;
		$stats->{$item}->{elapsed} ||= 0;

		print "<TR>\n";
		# Choose the background color for the row, and then change it for next time
		my $bgcolor = ++$i % 2 ? COLOR_TABLE_ROW_EVEN : COLOR_TABLE_ROW_ODD; 
		print "<TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><I>$item</I>\n";
		printf "<TD BGCOLOR='" . $bgcolor . "' ALIGN=RIGHT> %s\n", Commify($stats->{$item}->{req}) || 0;
		printf "<TD BGCOLOR='" . $bgcolor . "' ALIGN=RIGHT> %s\n", Commify(sprintf "%5.2f", $stats->{$item}->{bytes} / 1024) || 0;
		
		# $item_speed is bytes per second for the item
		my $item_speed = $stats->{$item}->{elapsed} ? $stats->{$item}->{bytes} / ($stats->{$item}->{elapsed} / 1000) : 0;
		printf "<TD BGCOLOR='" . $bgcolor . "' ALIGN=RIGHT> %s\n", Commify(sprintf "%2.2f", $item_speed) ;

		# $percent_bytes is a percentage of item bytes to total bytes
		my $percent_bytes = $stats->{Total}->{bytes} ? 100 * $stats->{$item}->{bytes} / $stats->{Total}->{bytes} : 0;
		
		printf "<TD BGCOLOR='" . $bgcolor . "' ALIGN=RIGHT> %2.2f\n", $percent_bytes;

		print "\t<TD BGCOLOR='$bgcolor' ALIGN=LEFT VALIGN=MIDDLE><FONT SIZE=-2>", ("|" x $percent_bytes), "</FONT>\n";
		
		# change the color for the "special" case 
		$bgcolor = COLOR_TABLE_CELL_SPECIAL if ($item eq "Direct");

		# $times_to_direct is a ratio of the $item_speed to $direct_speed. It tells how much faster or slower the item is than the average of going directly to the server.
		my $times_to_direct = $direct_speed ? $item_speed / $direct_speed : 0;
		
		printf "<TD BGCOLOR='" . $bgcolor . "' ALIGN=RIGHT> %2.2f\n", $times_to_direct;

		print "\t<TD BGCOLOR='" . $bgcolor . "' ALIGN=LEFT VALIGN=MIDDLE><FONT SIZE=-2>", ("|" x (25 * $times_to_direct)), "\n";
		
		# This shows the epoch of the elapsed time.  Only used if I am debugging why one of the above doesn't seem to calculate right
		#printf "<TD BGCOLOR='" . $bgcolor . "' ALIGN=RIGHT> %s\n", $stats->{$item}->{elapsed};
	}
	print "</TABLE>";
	print "<HR>\n";
}

sub Show_System_Profile
{
#
# Print some profiling information here
# This was taken pretty much as read from the original squeezer.pl
# 
	my ($total_req) = @_;
	my ($user, $system, $cuser, $csystem)  = times;
	print "\n<H3><U>Squeezer Performance:</U></H3>\n";
	print "<TABLE TABLE_CELL_BORDER TABLE_CELLSPACING TABLE_CELLPADDING>\n";
	print "<TR><TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><B>User time";
	printf    "<TD BGCOLOR='" . COLOR_TABLE_ROW_EVEN . "' ALIGN=RIGHT> %5.2f s\n", $user;
	print "<TR><TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><B>System time</B>";
	printf    "<TD BGCOLOR='" . COLOR_TABLE_ROW_ODD . "' ALIGN=RIGHT>%5.2f s\n", $system;
	print "<TR><TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><B>Children time</B>";
	printf    "<TD BGCOLOR='" . COLOR_TABLE_ROW_EVEN . "' ALIGN=RIGHT>%5.2f s\n", $cuser;
	print "<TR><TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><B>Children system time</B>";
	printf    "<TD BGCOLOR='" . COLOR_TABLE_ROW_ODD . "' ALIGN=RIGHT>%5.2f s\n", $csystem;
	print "<TR><TD BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'><B>Together</B>";
	printf    "<TD  BGCOLOR='" . COLOR_TABLE_CELL_SPECIAL . "'ALIGN=RIGHT><B>%5.2f</B> s\n", $user + $system + $cuser + $csystem;
	print "<TR><TD BGCOLOR='" . COLOR_TABLE_ROW_HEAD . "'><B>Lines Processed<B>\n";
	printf    "<TD BGCOLOR='" . COLOR_TABLE_ROW_ODD . "' ALIGN=RIGHT>%s\n", 
	                            Commify($total_req); 
	print "<TR><TD BGCOLOR='" . COLOR_TABLE_COL_HEAD . "'><B>Speed<B>\n";
	printf    "<TD BGCOLOR='" . COLOR_TABLE_CELL_SPECIAL . "' ALIGN=RIGHT><B>%s lines/s</B>\n", 
	                            Commify(sprintf "%d", $total_req/($user + $system + $cuser + $csystem)); 
	print "</TABLE>";
	print "<HR>\n";

	my $sysid = `uname -a`;
	print "<BR><BR>\n";
	printf "running on <B>%s</B><BR>",$sysid; 
	print "<BR><BR>";

}

sub Commify
{
	# This takes a number and returns it with comma's like us american's like to see numbers
	local $_  = shift;
	return unless $_;
	1 while s/^([-+]?\d+)(\d{3})/$1,$2/;
	return $_;
}

sub Timeify
{
	# Changes an epoch time to hh:mm:ss.mili
	my $milisecond = shift;
	my ($hour, $minute, $second);
	$second	= $milisecond / 1000;
	$milisecond = $milisecond % 1000;
	$minute = $second / 60;
	$second	= $second % 60;
	$hour	= int $minute / 60;
	$minute	= $minute % 60;

	$hour = "0$hour" if ($hour < 10);
	$minute = "0$minute" if ($minute < 10);
	$second = "0$second" if ($second < 10);
	$milisecond = $milisecond . "0" if ($milisecond < 100);
	$milisecond = $milisecond . "0" if ($milisecond < 10);

	return "$hour:$minute:$second.$milisecond";
}

sub about 
{
	# This is pretty much taken as read from squeezer.pl.  I just added my name and e-mail address.
	my $whoami = $0;
	my $author = "M.K.</A> Rewrite by <a href='mailto:andrew\@mad-techies.org'>andrew fresh";
	my $email  = "maciej_kozinski\@wp.pl";
	my $homepage = "http://strony.wp.pl/wp/maciej_kozinski/squeezer.html";
	my $version = "0.5";
	my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($whoami);
	my @path = split (/\//, $whoami);
	$whoami = $path[$#path]; # Not sure why $path[-1] wasn't used, but I didn't write it so . . .
	print "<HR>";
	print "<I><A HREF=\"$homepage\">$whoami v. ",$version, "</A> by <A HREF=\"mailto:$email\">$author</A>,&nbsp  last modified: ", scalar localtime($mtime);
	print "<BR><BR> <A HREF=\"$homepage\">";
	print "Tutorial on using squeezer generated data</A>";
}
