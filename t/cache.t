#!/usr/bin/perl -w
use strict;

use Test::More;
use File::Path;
use File::Spec;

use SVN::Web;

my $repospath;

BEGIN {
    plan skip_all => "Test::WWW::Mechanize not installed"
        unless eval { require Test::WWW::Mechanize; 1 };

    plan skip_all => "Test::Differences not installed"
        unless eval { require Test::Differences; 1 };

    plan skip_all => "Cache::Cache not installed"
        unless eval { require Cache::MemoryCache; 1 };

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
my %store;

# First, make sure that caching is turned off, and walk the whole tree.
# Build a hash that maps URLs to contents.  We'll check this later.
diag('First walk');
$mech->get($url);
walk_site($mech, \&store_content);

plan tests => keys(%store) * 3 + 3;

# Now, without turning caching on, do it again, to verify that the
# results are the same without caching.
diag('Second walk, no caching');
$mech->get($url);
walk_site($mech, \&check_content);

# Now turn caching on, walk the site once more to prime the cache
diag('Third walk, priming cache');

my $config = SVN::Web::get_config();
$config->{cache} = { class => 'Cache::MemoryCache' };
SVN::Web::set_config($config);

$mech->get($url);
walk_site($mech, \&check_content);

# Walk the site for a final time.  Most requests should hit the cached
# copy, and there should be content changes
diag('Fourth walk, using cache');
$mech->get($url);
walk_site($mech, \&check_content);

sub store_content {
    my $mech = shift;

    $store{$mech->uri()} = $mech->content();
}

sub check_content {
    my $mech = shift;

    Test::Differences::eq_or_diff($mech->content(), $store{$mech->uri()}, $mech->uri());
}

sub walk_site {
    my $mech = shift;
    my $test = shift;
    my $seen = shift || {};

    $test->($mech);

    my @links = $mech->links;
    diag 'Found ' . (scalar @links) . ' links' if $ENV{TEST_VERBOSE};
    for my $i (0 .. $#links) {
        my $link_url = $links[$i]->url_abs;
        diag "Link $i/$#links: $link_url" if $ENV{TEST_VERBOSE};
        next                              if $seen->{$link_url};
        ++$seen->{$link_url};
        diag "Following $link_url" if $ENV{TEST_VERBOSE};

        $mech->get($link_url);
        walk_site($mech, $test, $seen);
        diag "--- Back" if $ENV{TEST_VERBOSE};
        $mech->back;
    }
}

