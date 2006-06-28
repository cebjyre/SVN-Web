#!/usr/bin/perl -w
use strict;
use SVN::Web::Test;
use Test::More;

my $can_tidy = eval { require Test::HTML::Tidy; 1 };
my $can_parse_rss = eval { require XML::RSS::Parser; 1 };

plan 'no_plan';

my $tidy;
if($can_tidy) {
    $tidy = new HTML::Tidy;
    $tidy->ignore(text => qr/trimming empty <span>/);
}

my $rss;
if($can_parse_rss) {
    $rss = XML::RSS::Parser->new();
}

my $repos = 't/repos';

my $test = SVN::Web::Test->new(repo_path => $repos,
			       repo_dump => 't/test_repo.dump');

$test->set_config({ uri_base => 'http://localhost',
		    script   => '/svnweb',
		    config   => { repos => { repos => $repos } },
		    });

my $mech = $test->mech();
$mech->get_ok('http://localhost/svnweb/repos/browse/');
$mech->title_is('browse: /repos/ (Rev: HEAD, via SVN::Web)',
			"'browse' has correct title") or diag $mech->content();

$mech->get('http://localhost/svnweb/repos/browse/?rev=1');
$mech->title_is(
    'browse: /repos/ (Rev: 1, via SVN::Web)',
    "'browse' with rev has correct title"
);

$mech->get('http://localhost/svnweb/repos/revision/?rev=2');
$mech->title_is('revision: /repos/ (Rev: 2, via SVN::Web)',
    "'revision' has correct title");

$mech->get('http://localhost/svnweb/');
$mech->title_is('Repository List (via SVN::Web)', "'list' has correct title");

diag "Recursively checking all links";

my $test_sub = sub {
    is($mech->status, 200, 'Fetched ' . $mech->uri());
    $mech->content_unlike(qr'An error occured', '  and content was correct');
    if($can_tidy 
       and ($mech->uri() !~ m{ (?:
			           / (?: rss | checkout ) /
                                 | mime=text/plain
			       )}x)) {
	Test::HTML::Tidy::html_tidy_ok($tidy, $mech->content(),
				       '  and is valid HTML')
	    or diag($mech->content());
    }

    if($can_parse_rss and ($mech->uri() =~ m{/rss/})) {
	my $parse_result = $rss->parse_string($mech->content());
	ok(defined $parse_result, 'RSS parsed successfully')
	  or diag $rss->errstr(), diag $mech->content();
    }
};

$test->walk_site($test_sub);
