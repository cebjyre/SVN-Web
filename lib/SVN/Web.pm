package SVN::Web;
use strict;
our $VERSION = '0.36';
use SVN::Core;
use SVN::Repos;
use YAML ();
use Template;
use File::Spec::Unix;
eval 'use FindBin';
{
no warnings 'uninitialized';
use Locale::Maketext::Simple (
    Path => (
	(-e "$FindBin::Bin/po/en.po")
	    ? "$FindBin::Bin/po"
	    : substr(__FILE__, 0, -3) . '/I18N'
    ),
    Style => 'gettext',
    Decode => 1,
);
}

require CGI;

=head1 NAME

SVN::Web - Subversion repository web frontend

=head1 SYNOPSIS

    > mkdir cgi-bin/svnweb
    > cd cgi-bin/svnweb
    > svnweb-install

Edit F<config.yaml> to set the source repository, then point your
browser to C<index.cgi/I<repos>> to browse it.

You will also need to make the svnweb directory writeable by the web
server.

=head1 DESCRIPTION

SVN::Web provides a web interface to subversion repositories. You can
browse the tree, view history of a directory or a file, see what's
changed in a specific revision, track changes with RSS, and also view
diff.

SVN::Web also tracks the branching feature (node copy) of subversion,
so you can easily see the relationship between branches.

=head1 MOD_PERL

You can enable mod_perl support of SVN::Web with the following in the
apache configuration:

    Alias /svnweb /path/to/svnweb
    <Directory /path/to/svnweb/>
      AllowOverride None
      Options None
      SetHandler perl-script
      PerlHandler SVN::Web
    </Directory>

=head1 BUGS

Note that the first time for accessing a repository might be very
slow, because the Branch plugin has to create cache for copy
information. for a large 9000-revision repository it takes 2 minutes.

=cut

my $template;
my $config;

my %REPOS;

our @PLUGINS = qw/branch browse checkout diff list log revision RSS template/;

sub load_config {
    my $file = shift || 'config.yaml';
    return $config ||= YAML::LoadFile ($file);
}

sub set_config {
    $config = shift;
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

    if ( $config->{block} ) {
        foreach my $blocked ( @{ $config->{block} } ) {
            delete $REPOS{$blocked};
        }
    }
}

sub repos_list {
    load_config('config.yaml');

    my @repos;
    if ($config->{reposparent}) {
        opendir my $dh, "$config->{reposparent}"
            or die "Cannot read $config->{reposparent}: $!";

        foreach my $dir (grep { -d "$config->{reposparent}/$_" && ! /^\./ } readdir $dh) {
            push @repos, $dir;
        }
    } else {
        @repos = keys %{ $config->{repos} };
    }

    my %blocked = map { $_ => 1 } @{ $config->{block} };

    return sort grep { ! $blocked{$_} } @repos;
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
    my $repos = $cfg->{repos} ? $REPOS{$cfg->{repos}} : undef;
    return $pkg->new (%$cfg, reposname => $cfg->{repos},
		      repos => $repos,
                      config => $config);

}

sub run {
    my $cfg = shift;

    my $pool = SVN::Pool->new_default_sub;

    my $obj;
    my $html;
    if (defined $cfg->{repos} && length $cfg->{repos}) {
        get_repos ($cfg->{repos});
    }

    if ($cfg->{repos} && $REPOS{$cfg->{repos}}) {
        @{$cfg->{navpaths}} = File::Spec::Unix->splitdir ($cfg->{path});
        shift @{$cfg->{navpaths}};
        # should use attribute or things alike

        my $branch = get_handler ({%$cfg, action => 'branch'});
        $obj = get_handler ({%$cfg, branch => $branch});
    } else {
        $obj = get_handler ({%$cfg, action => 'list'});
    }

    loc_lang($cfg->{lang} ? $cfg->{lang} : ());
    $html = eval { $obj->run };

    die "operation failed: $@" if $@;

    $cfg->{output_sub}->($cfg, $html);
}

sub cgi_output {
    my ($cfg, $html) = @_;

    if (ref ($html)) {
	print $cfg->{cgi}->header(-charset => $html->{charset} || 'UTF-8',
				  -type => $html->{mimetype} || 'text/html');
	if ($html->{template}) {
	    $template->process ($html->{template},
				{ %$cfg,
				  %{$html->{data}}})
		or die $template->error;
	}
	else {
	    print $html->{body};
	}
    }
    else {
	print $cfg->{cgi}->header(-charset => 'UTF-8',
				  -type => 'text/html');
	print $html;
    }
}

sub mod_perl_output {
    my ($cfg, $html) = @_;

    if (ref ($html)) {
        my $content_type = $html->{mimetype} || 'text/html';
        $content_type .= '; ';
        $content_type .= $html->{charset} ? $html->{charset} : 'UTF-8';
	$cfg->{request}->content_type($content_type);

	if ($html->{template}) {
	    $template ||= get_template ();
	    $template->process ($html->{template},
				{ %$cfg,
				  %{$html->{data}}},
                                $cfg->{request})
		or die $template->error;
	}
	else {
	    $cfg->{request}->print($html->{body});
	}
    }
    else {
	$cfg->{request}->content_type('text/html; charset=UTF-8');

	$cfg->{request}->print($html);
    }
}

my $pool; # global pool for holding opened repos

sub get_template {
    Template->new ({ INCLUDE_PATH => ($config->{templatedir} || 'template/'),
		     PRE_PROCESS => 'header',
		     POST_PROCESS => 'footer',
		     FILTERS => { l => ([\&loc_filter, 1]) } });
}

sub run_cgi {
    die $@ if $@;

    my $cgi_class = (eval { require CGI::Fast; 1 } ? 'CGI::Fast' : 'CGI');
    eval "use CGI::Carp qw(fatalsToBrowser)";
    $pool ||= SVN::Pool->new_default;
    load_config ('config.yaml');
    $template = get_template ();

    while (my $cgi = $cgi_class->new) {
	# /<repository>/<action>/<path>/<file>?others
	my (undef, $repos, $action, $path) = split ('/', $cgi->path_info, 4);
	$action ||= 'browse';
	$path ||= '';

	run ({ repos => $repos,
	       action => $action,
	       path => '/'.$path,
	       script =>$ENV{SCRIPT_NAME},
               output_sub => \&cgi_output,
	       cgi => $cgi});
	last if $cgi_class eq 'CGI';
    }
}

sub loc_filter {
    my $context = shift;
    my @args = @_;
    return sub { loc($_[0], @args) };
}

sub handler {
    eval "
	use Apache::RequestRec ();
	use Apache::RequestUtil ();
	use Apache::RequestIO ();
	use Apache::Response ();
	use Apache::Const;
	use Apache::Constants;
        use Apache::Request;
    ";

    my $r = shift;
    eval "$r = Apache::Request->new($r)";
    my $base = $r->location;
    my $repos = $r->filename;
    my $script = $r->uri;
    $script =~ s|/$||;
    $repos =~ s|^$base/?||;
    $repos ||= '';

    if ($repos) {
        $script = $1 if $r->uri =~ m|^((?:/\w+)+?)/\Q$repos\E| or die "can't find script";
    }
    chdir ($base);
    $pool ||= SVN::Pool->new_default;
    load_config ('config.yaml');

    my (undef, $action, $path) = split ('/', $r->path_info, 3);
    $action ||= 'browse';
    $path ||= '';

    run ({ repos => $repos,
	   action => $action,
	   script => $script,
	   path => '/'.$path,
           output_sub => \&mod_perl_output,
	   request => $r,
           cgi     => ref ($r) eq 'Apache::Request' ? $r : CGI->new});

   return &Apache::OK;
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
