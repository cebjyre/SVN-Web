package SVN::Web;
$VERSION = '0.1';

use strict;
use SVN::Core '0.28';
use SVN::Repos;
use YAML ();
use Template;

=head1 NAME

SVN::Web - Subversion repository web frontend

=head1 SYNOPSIS

> mkdir cgi-bin/svnweb
> cd cgi-bin/svnweb
> svnweb-install

edit your config.yaml to set repository to browse, then point your
browser to index.cgi/<repos>

=head1 DESCRIPTION



=cut

my $template;
my $config;

my %REPOS;

our @PLUGINS = qw/browse checkout log revision template/;

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

sub run {
    my $cfg = shift;
    my $pkg = $config->{"$cfg->{action}_class"};
    unless ($pkg) {
	$pkg = $cfg->{action};
	$pkg =~ s/^(\w)/\U$1/;
	$pkg = __PACKAGE__."::$pkg";
    }
    die "no such plugin $pkg" unless $pkg;
    eval "require $pkg && $pkg->can('run')" or die $@;

    my $pool = SVN::Pool->new_default;

    get_repos ($cfg->{repos});

    my $obj = $pkg->new (%$cfg, repos => $REPOS{$cfg->{repos}});
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
	       path => $path,
	       cgi => $cgi});
	last if $cgi_class eq 'CGI';
    }
}

sub handler {

}

1;
