#!/usr/bin/perl -w
use strict;
use SVN::Web;
use Test::More;
use File::Path;
use File::Spec;
my $repospath;

my($can_tidy, $tidy);

BEGIN {
plan skip_all => "Test::WWW::Mechanize not installed"
    unless eval { require Test::WWW::Mechanize; 1 };

plan skip_all => "can't find svnadmin"
    unless `svnadmin --version` =~ /version/;

$can_tidy = eval { require Test::HTML::Tidy; 1 };

plan 'no_plan';
$repospath = File::Spec->rel2abs("t/repos");

rmtree ([$repospath]) if -d $repospath;
$ENV{SVNFSTYPE} ||= (($SVN::Core::VERSION =~ /^1\.0/) ? 'bdb' : 'fsfs');

`svnadmin create --fs-type=$ENV{SVNFSTYPE} $repospath`;
`svnadmin load $repospath < t/test_repo.dump`;

}

if($can_tidy) {
  $tidy = new HTML::Tidy;
  $tidy->ignore(text => qr/trimming empty <span>/);
}

my $url = 'http://localhost/svnweb';
use SVN::Web::Test ('http://localhost', '/svnweb',
		    repos => $repospath);
my $mech = SVN::Web::Test->new;

$mech->get ('http://localhost/svnweb/repos/browse/');
$mech->title_is ('browse: /repos/ (Rev: HEAD, via SVN::Web)', "'browse' has correct title");

$mech->get ('http://localhost/svnweb/repos/browse/?rev=1');
$mech->title_is ('browse: /repos/ (Rev: 1, via SVN::Web)', "'browse' with rev has correct title");

$mech->get ('http://localhost/svnweb/repos/revision/?rev=2');
$mech->title_is ('revision: /repos/ (Rev: HEAD, via SVN::Web)', "'revision' has correct title");

$mech->get ('http://localhost/svnweb/');
$mech->title_is ('Repository List (via SVN::Web)', "'list' has correct title");

my %seen;

diag "Recusrively checking all links";

check_links();

sub check_links {
    diag "---" if $ENV{TEST_VERBOSE};
    is ($mech->status, 200, 'Fetched: ' . $mech->uri());
    $mech->content_unlike (qr'operation failed', '   and content was correct');
    if($can_tidy and ($mech->uri() !~ m{ /(?:rss|checkout)/ }x)) {
      Test::HTML::Tidy::html_tidy_ok($tidy, $mech->content(), '   and is valid HTML')
	or diag($mech->content());
    }

#    diag $mech->content() if $mech->uri() !~ m{ /(?:rss|checkout)/ }x;
    my @links = $mech->links;
    diag 'Found ' . (scalar @links) . ' links' if $ENV{TEST_VERBOSE};
    for my $i (0..$#links) {
        my $link_url = $links[$i]->url_abs;
        diag "Link $i/$#links: $link_url" if $ENV{TEST_VERBOSE};
        next if $seen{$link_url};
        ++$seen{$link_url};
        next if $link_url =~ m/diff/;
        next if $link_url !~ /localhost/;
        diag "Following $link_url" if $ENV{TEST_VERBOSE};
#        $mech->follow_link ( n => $i+1 );
	$mech->get($link_url);
        check_links();
        diag "--- Back" if $ENV{TEST_VERBOSE};
        $mech->back;
    }
}


#warn join("\n", map {$_->url_abs} @links);

#$mech->link_status_is( [ grep {$_->url_abs =~ m|^$url.+| } @links ], 200);
