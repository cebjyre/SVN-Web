#!/usr/bin/perl -w
#
# Make sure that using the cache functionality is actually faster

use strict;

use File::Path;
use File::Spec;
use Test::More;
use Benchmark;

use SVN::Web;

my $repospath;

BEGIN {
    plan skip_all => 'Test::Benchmark not installed'
        unless eval { require Test::Benchmark; import Test::Benchmark; 1 };

    plan skip_all => 'Cache::MemoryCache not installed'
        unless eval { require Cache::MemoryCache; 1 };

    plan skip_all => "Test::WWW::Mechanize not installed"
        unless eval { require Test::WWW::Mechanize; 1 };

    plan skip_all => 'Skipping benchmark, set $TEST_VERBOSE or $TEST_BENCHMARK'
        unless exists $ENV{TEST_VERBOSE} or exists $ENV{TEST_BENCHMARK};

    plan skip_all => "can't find svnadmin"
        unless `svnadmin --version` =~ /version/;

    $repospath = File::Spec->rel2abs("t/repos");

    rmtree([$repospath]) if -d $repospath;
    $ENV{SVNFSTYPE} ||= (($SVN::Core::VERSION =~ /^1\.0/) ? 'bdb' : 'fsfs');

    `svnadmin create --fs-type=$ENV{SVNFSTYPE} $repospath`;
    `svnadmin load $repospath < t/test_repo.dump`;
}

my $url = 'http://localhost/svnweb';
use SVN::Web::Test ('http://localhost', '/svnweb', repos => $repospath);

my $mech   = SVN::Web::Test->new;

# Do 10 runs with caching turned off
my $config = SVN::Web::get_config();
delete $config->{cache};
SVN::Web::set_config($config);

my $walk = sub { $mech->get($url); walk_site($mech, sub { 1; }) };

my $benchmark_1 = timethis(10, $walk);

# Do 10 runs with caching turned on
$config->{cache} = { class => 'Cache::MemoryCache' };
SVN::Web::set_config($config);

my $benchmark_2 = timethis(10, $walk);

# Only run one test.  Make sure that the second benchmark
# is faster than the first
plan tests => 1;
is_faster(0, $benchmark_2, $benchmark_1, 'Caching makes things faster');

sub walk_site {
    my $mech = shift;
    my $test = shift;
    my $seen = shift || {};

    $test->($mech);

    my @links = $mech->links;
    for my $i (0 .. $#links) {
        my $link_url = $links[$i]->url_abs;
        next                              if $seen->{$link_url};
        ++$seen->{$link_url};

        $mech->get($link_url);
        walk_site($mech, $test, $seen);
        $mech->back;
    }
}

