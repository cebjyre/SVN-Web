package SVN::Web;
$VERSION = '0.2';

use strict;
use SVN::Core '0.28';
use SVN::Repos;
use YAML ();
use Template;
use File::Spec::Unix;

=head1 NAME

SVN::Web - Subversion repository web frontend

=head1 SYNOPSIS

> mkdir cgi-bin/svnweb
> cd cgi-bin/svnweb
> svnweb-install

Edit your config.yaml to set repository to browse, then point your
browser to index.cgi/<repos>

=head1 DESCRIPTION

SVN::Web provides a web interface to subversion repositories. You can
browse the tree, view history of a directory or a file, see what's
changed in a specific revision, track changes with RSS, and also view
diff.

SVN::Web also tracks the branching feature (node copy) of subversion,
so you can easily see the relationship between branches.

=cut

my $template;
my $config;

my %REPOS;

our @PLUGINS = qw/branch browse checkout diff log revision RSS template/;

sub load_config {
    my $file = shift;
    return YAML::LoadFile ($file);
}

sub get_repos {
    my ($repos) = @_;

    die "please configure your repository"
	unless $config->{repos} || $config->{reposparent};

    die "no such repository $repos"
	unless ($config->{reposparent} &&
		-d "$config->{reposparent}/$repos")
	    || exists $config->{repos}{$repos};

    $REPOS{$repos} ||=  SVN::Repos::open
	($config->{reposparent} ? "$config->{reposparent}/$repos"
	 : $config->{repos}{$repos}) or die $!;
}

sub get_handler {
    my $cfg = shift;
    my $pkg = $config->{"$cfg->{action}_class"};
    unless ($pkg) {
	$pkg = $cfg->{action};
	$pkg =~ s/^(\w)/\U$1/;
	$pkg = __PACKAGE__."::$pkg";
    }
    die "no such plugin $pkg" unless $pkg;
    eval "require $pkg && $pkg->can('run')" or die $@;
    return $pkg->new (%$cfg, reposname => $cfg->{repos},
		      repos => $REPOS{$cfg->{repos}});

}

sub run {
    my $cfg = shift;

    my $pool = SVN::Pool->new_default;

    get_repos ($cfg->{repos});

    @{$cfg->{navpaths}} = File::Spec::Unix->splitdir ($cfg->{path});
    shift @{$cfg->{navpaths}};
    # should use attribute or things alike
    my $branch = get_handler ({%$cfg, action => 'branch'});
    my $obj = get_handler ({%$cfg, branch => $branch});
    my $html = $obj->run;

    if (ref ($html)) {
	print $cfg->{cgi}->header(-charset => $html->{charset} || 'UTF-8',
				  -type => $html->{mimetype} || 'text/html');
	if ($html->{template}) {
	    $template->process ($html->{template},
				{ %$cfg,
				  script => $ENV{SCRIPT_NAME},
				  %{$html->{data}}})
		or die $template->error;
	}
	else {
	    print $html->{body};
	}
    }
    else {
	print $cfg->{cgi}->header(-charset => 'UTF-8');
	print $html;
    }
}

sub run_cgi {
    eval "use CGI::Carp qw(fatalsToBrowser)";
    die $@ if $@;

    my $cgi_class = (eval { require CGI::Fast; 1 } ? 'CGI::Fast' : 'CGI');
    $config = load_config ('config.yaml');
    $template = Template->new ({ INCLUDE_PATH => 'template/',
				 PRE_PROCESS => 'header',
				 POST_PROCESS => 'footer' });

    while (my $cgi = $cgi_class->new) {
	# /<repository>/<action>/<path>/<file>?others
	my (undef, $repos, $action, $path) = split ('/', $ENV{PATH_INFO}, 4);
	$action ||= 'browse';
	$path ||= '';

	run ({ repos => $repos,
	       action => $action,
	       path => '/'.$path,
	       cgi => $cgi});
	last if $cgi_class eq 'CGI';
    }
}

sub handler {

}

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

1;
