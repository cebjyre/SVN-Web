# -*- Mode: cperl; cperl-indent-level: 4 -*-
package SVN::Web;
use strict;
our $VERSION = '0.42';
use SVN::Core;
use SVN::Repos;
use YAML ();
use Template;
use URI;
use File::Spec::Unix;
use SVN::Web::X;
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
    Decode => 0,
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

See
L<http://jc.ngo.org.uk/~nik/cgi-bin/svnweb/index.cgi/jc/browse/nik/CPAN/SVN-Web/trunk/>
for the SVN::Web source code, browsed using SVN::Web.

=head1 DESCRIPTION

SVN::Web provides a web interface to subversion repositories. You can
browse the tree, view history of a directory or a file, see what's
changed in a specific revision, track changes with RSS, and also view
diff.

=head1 CONFIGURATION

Various aspects of SVN::Web's behaviour can be controlled through the
configuration file F<config.yaml>.  See the C<YAML> documentation for
information about writing YAML format files.

=head2 Repositories

SVN::Web can show information from one or more Subversion repositories.

To specify them use C<repos> or C<reposparent>.

If you have a single Subversion repository, or multiple repositories that
are not under a single parent directory then use C<repos>.

  repos:
    first_repo: '/path/to/the/first/repo'
    second_repo: '/path/to/the/second/repo'

If you have multiple repositories that are all under a single parent
directory then use C<reposparent>.

  reposparent: '/path/to/parent/directory'

If you set C<reposparent> then you can selectively block certain repositories
from being browseable by specifying the C<block> setting.

  block:
    - 'first_subdir_to_block'
    - 'second_subdir_to_block'

=head2 Diffs

When showing differences between files, SVN::Web can show a customisable
amount of context around the changes.

The default number of lines to show is 3.  To change this globally set
C<diff_context>.

  diff_context: 4

=head2 Templates

SVN::Web's output is entirely template driven.  SVN::Web ships with a
number of different template styles, installed in to the F<templates/>
subdirectory of wherever you ran C<svnweb-install>.

The default templates are installed in F<templates/trac>.  These implement
a look and feel similar to the Trac (L<http://www.edgewall.com/trac/>)
output.

To change to another set, use the C<templatedirs> configuration directive.

For example, to use a set of templates that implement a much plainer look
and feel:

  templatedirs:
    - 'template/plain'

Alternatively, if you have your own templates elsewhere you can
specify a full path to the templates.

  templatedirs:
    - '/full/path/to/template/directory'

You can specify more than one directory in this list, and templates
will be searched for in each directory in turn.  This makes it possible for
actions that are not part of the core SVN::Web to ship their own templates.
The documentation for these actions should explain how to adjust
C<templatedirs> so their templates are found.

For more information about writing your own templates see
L</"ACTIONS, SUBCLASSES, AND URLS">.

=head2 Log message filters

Many of the templates shipped with SVN::Web include log messages from
the repository.  It's likely that these log messages contain e-mail
addresses, links to other web sites, and other rich information.

The Template::Toolkit makes it possible to filter these messages through
one or more plugins and/or filters that can recognise these and insert
additional markup to make them active.

There are two drawbacks with this approach:

=over 4

=item 1.

For consistency you need to make sure that all log messages are passed
through the same filters in the same order in all the templates that
display log messages.

=item 2.

If you move the templates from a machine that has a particular filter
installed to a machine that doesn't have that filter installed you need
to remove it from the template, otherwise you will receive a run-time
error.

=back

SVN::Web provides a special Template::Toolkit filter called C<log_msg>.
Use it like so (assume C<msg> contains the SVN log message).

  [% msg | log_msg %]

The filters to run for C<log_msg>, their order, and any options, are
specified in the C<log_msg_filters> configuration directive.  This contains
a list of filters and key,value pairs.

=over 4

=item name

Specifies the name of the class of the filtering object or plugin.  If
the object is in the Template::Plugin::* namespace then you can omit
the leading C<Template::Plugin::>.

If the name is C<standard> then filters from the standard
L<Template::Filters> collection can be used.

=item filter

The name of the filter to run.  This is taken from whatever the plugin's
documentation says would go in the C<[% FILTER ... %]> directive.

For example, the L<Template::Plugin::Clickable> documentation gives this
example;

  [% USE Clickable %]
  [% FILTER clickable %]
  ...

So the correct value for C<name> is C<Clickable>, and the correct value for
C<filter> is C<clickable>.

=item opts

Any options can be passed to the filter using C<opts>.  This specifies a
list of hash key,value pairs.

  ...
  opts:
    first_opt: first_value
    second_opt: second_value
  ...

=back

Filters are run in the order they are listed.  Any filters that do not exist
on the system are ignored.

The configuration file includes a suggested list of default filters.

You can write your own plugins to recognise certain information in your
local log messages and automatically turn them in to links.  For example,
if you have a web-based issue tracking system, you might write a plugin
that recognises text of the form C<t#1234> and turns it in to a link to
ticket #1234 in your ticketing system.

=head2 Actions, action classes, and action options

Each action that SVN::Web can carry out is implemented as a class (see
L</"ACTIONS, SUBCLASSES, AND URLS"> for more).  You can specify your own
class for a particular action.  This lets you implement your own actions,
or override the behaviour of existing actions.

The complete list of actions is listed in the C<actions> configuration
directive.

If you delete items from this list then the corresponding action becomes
unavailable.  For example, if you would like to prevent people from retrieving
an RSS feed of changes, just delete the C<- RSS> entry from the list.

To provide your own behaviour for standard actions just specify a
different value for the C<class> key.  For example, to specify your
own class that implements the C<view> action;

  actions:
    ...
    view:
      class: My::View::Class
    ...

If you wish to implement your own action, give the action a name, add
it to the C<actions> list, and then specify the class that carries out
the action.

For example, SVN::Web currently provides no equivalent to the
Subversion C<annotate> command.  If you implement this, you would write:

  actions:
    ...
    annotate:
      class: My::Class::That::Implements::Annotate
    ...

Please feel free to submit any classes that implement additional
functionality back to the maintainers, so that they can be included in
the distribution.

Actions may have configurable options specified in F<config.yaml> under
the C<opts> key.  Continuing the C<annotate> example, the action may be
written to provide basic output by default, but feature a C<verbose>
flag that you can enable globally.  That would be configured like so:

  actions:
    ...
    annotate:
      class: My::Class::That::Implements::Annotate
      opts:
        verbose: 1
    ...

The documentation for each action should explain in more detail how it
should be configured.  See L<SVN::Web::action> for more information 
about writing actions.

If an action is listed in C<actions> and there is no corresponding
C<class> directive then SVN::Web takes the action name, converts the
first character to uppercase, and then looks for an
C<<SVN::Web::<Action> >> package.

=head2 CGI class

SVN::Web can use a custom CGI class.  By default SVN::Web will use CGI::Fast
if it is installed, and fallback to using CGI otherwise.

If you have your own CGI subclass you can specify it here.

   cgi_class: 'My::CGI::Subclass'

This option is somewhat specialised.

=head1 ACTIONS, SUBCLASSES, AND URLS

SVN::Web URLs are broken down in to four components.

  .../index.cgi/<repo>/<action>/<path>?<arguments>

=over 4

=item I<repo>

The repository the action will be performed on.  SVN::Web can be
configured to operate on multiple Subversion repositories.

=item I<action>

The action that will be run.

=item I<path>

The path within the <repository> that the action is performed on.

=item I<arguments>

Any arguments that control the behaviour of the I<action>.

=back

Each action is implemented as a Perl module.  By convention, each module
carries out whatever processing is required by the action, and returns a
reference to a hash of data that is used to fill out a C<Template::Toolkit>
template that displays the action's results.

The standard actions, and the Perl modules that implement them, are:

=over 4

=item I<browse>, I<SVN::Web::Browse>

Shows the files and directories in a given repository path.  This is
the default command if no path is specified in the URL.

=item I<checkout>, I<SVN::Web::Checkout>

Returns the raw data for the file at a given repository path and revision.

=item I<diff>, I<SVN::Web::Diff>

Shows the difference between two revisions of the same file.

=item I<list>, I<SVN::Web::List>

Lists the available Subversion repositories.  This is the default
command if no repository is specified in the URL.

=item I<log>, I<SVN::Web::Log>

Shows log information (commit messages) for a given repository path.

=item I<revision>, I<SVN::Web::Revision>

Shows information about a specific repository revision.

=item I<rss>, I<SVN::Web::RSS>

Generates an RSS feed of changes to the repository path.

=item I<view>, I<SVN::Web::View>

Shows the commit message and file contents for a specific repository path
and revision.

=back

See the documentation for each of these modules for more information
about the data that they provide to each template, and for information
about customising the templates used for each module.

=over 4

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

=cut

my $template;
my $config;

my %REPOS;

sub load_config {
    my $file = shift || 'config.yaml';
    $config ||= YAML::LoadFile ($file);

    # Deal with possibly conflicting 'templatedir' and 'templatedirs' settings.

    # If neither of them are set, use 'templatedirs'
    if(! exists $config->{templatedir} and ! exists $config->{templatedirs}) {
	$config->{templatedirs} = [ 'template/trac' ];
    }

    # If 'templatedir' is the only one set, use it.
    if(exists $config->{templatedir} and ! exists $config->{templatedirs}) {
	$config->{templatedirs} = [ $config->{templatedir} ];
	delete $config->{templatedir};
    }

    # If they're both set then throw an error
    if(exists $config->{templatedir} and exists $config->{templatedirs}) {
        die "templatedir and templatedirs both defined in config.yaml";
    }

    return;
}

sub set_config {
    $config = shift;
}

my $repospool = SVN::Pool->new;

sub get_repos {
    my ($repos) = @_;

    SVN::Web::X->throw(error => '(unconfigured repository)',
		       vars => [])
	unless $config->{repos} || $config->{reposparent};

    my $repo_path = 
      $config->{reposparent} ? "$config->{reposparent}/$repos"
	: $config->{repos}{$repos};

    SVN::Web::X->throw(error => '(no such repo %1 %2)',
		       vars => [$repos, $repo_path])
	unless ($config->{reposparent} &&
		-d "$config->{reposparent}/$repos")
	    || exists $config->{repos}{$repos} && -d $config->{repos}{$repos};

    eval {
	$REPOS{$repos} ||= SVN::Repos::open($repo_path, $repospool);
    };

    if($@) {
	my $e = $@;
	SVN::Web::X->throw(error => '(SVN::Repos::open failed: %1 %2)',
			   vars => [$repo_path, $e]);
    }

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
            or SVN::Web::X->throw(error => '(opendir reposparent %1 %2)',
				  vars => [$config->{reposparent}, $!]);

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
    my $pkg;

    if(exists $config->{actions}{$cfg->{action}}) {
	if(ref($config->{actions}{$cfg->{action}}) eq 'HASH') {
	    if(exists $config->{actions}{$cfg->{action}}{class}) {
		$pkg = $config->{actions}{$cfg->{action}}{class};
	    }
	}
    }

    unless ($pkg) {
	$pkg = $cfg->{action};
	$pkg =~ s/^(\w)/\U$1/;
	$pkg = __PACKAGE__."::$pkg";
    }
    eval "require $pkg && $pkg->can('run')" or
      SVN::Web::X->throw(error => '(missing package %1 for action %2: %3)',
			 vars => [$pkg, $cfg->{action}, $@]);
    my $repos = $cfg->{repos} ? $REPOS{$cfg->{repos}} : undef;
    return $pkg->new (%$cfg, reposname => $cfg->{repos},
		      repos => $repos,
                      config => $config);
}

sub run {
    my $cfg = shift;

    my $pool = SVN::Pool->new_default;

    my $obj;
    my $html;

    if (defined $cfg->{repos} && length $cfg->{repos}) {
	get_repos ($cfg->{repos});
    }

    if ($cfg->{repos} && $REPOS{$cfg->{repos}}) {
	@{$cfg->{navpaths}} = File::Spec::Unix->splitdir ($cfg->{path});
	shift @{$cfg->{navpaths}};
	# should use attribute or things alike
	$obj = get_handler ({%$cfg,
       			     opts => exists $config->{actions}{$cfg->{action}}{opts} ?
			                    $config->{actions}{$cfg->{action}}{opts} :
			                    { },
			    });
    } else {
	$cfg->{action} = 'list';
	$obj = get_handler ({%$cfg,
       			     opts => exists $config->{actions}{$cfg->{action}}{opts} ?
			                    $config->{actions}{$cfg->{action}}{opts} :
			                    { },
			    });
    }

    loc_lang($cfg->{lang} ? $cfg->{lang} : ());
    $html = $obj->run();

    return $html;
}

sub cgi_output {
    my ($cfg, $html) = @_;

    return unless defined $html;

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
        $content_type .= '; charset=';
        $content_type .= $html->{charset} || 'UTF-8';
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

our $pool; # global pool for holding opened repos

sub get_template {
    Template->new ({ INCLUDE_PATH => $config->{templatedirs},
		     PRE_PROCESS => 'header',
		     POST_PROCESS => 'footer',
		     FILTERS => { l => ([\&loc_filter, 1]),
				  log_msg => \&log_msg_filter, } });
}

sub run_cgi {
    die $@ if $@;
    $pool ||= SVN::Pool->new_default;
    load_config ('config.yaml');
    $template ||= get_template ();
    $config->{diff_context} ||= 3;

    my $cgi_class = $config->{cgi_class} || (eval { require CGI::Fast; 1 } ? 'CGI::Fast' : 'CGI');

    while (my $cgi = $cgi_class->new) {
	my($html, $cfg);
	eval {
	    # /<repository>/<action>/<path>/<file>?others
	    my (undef, $repos, $action, $path) = split ('/', $cgi->path_info, 4);
	    $action ||= 'browse';
	    $path ||= '';

	    my $base_uri = URI->new($cgi->url())->as_string();
	    $base_uri =~ s{/index.cgi}{};

	    $cfg = { repos => $repos,
		     action => $action,
		     path => "/$path",
		     script => $ENV{SCRIPT_NAME},
		     base_uri => $base_uri,
		     style => $config->{style},
		     cgi => $cgi,
		   };
	
	    SVN::Web::X->throw(error => '(action %1 not supported)',
			       vars => [$action])
		unless exists $config->{actions}{lc($action)};
	
	    $html = run($cfg);
	};

	my $e;
	if($e = SVN::Web::X->caught()) {
	    $html->{template} = 'x';
	    $html->{data}{error_msg} = loc($e->error(), @{ $e->vars() });
	} else {
	    if($@) {
		$html->{template} = 'x';
		$html->{data}{error_msg} = $@;
	    }
	}

	cgi_output($cfg, $html);
	last if $cgi_class eq 'CGI';
    }
}

sub loc_filter {
    my $context = shift;
    my @args = @_;
    return sub { loc($_[0], @args) };
}

# A meta-filter for log messages.  Processes a list of hashes.  Each hash
# has (at least) 'name' and 'filter' keys.  The 'name' is the Perl module
# that implements the plugin.  The 'filter' key is the name of the plugin's
# method that does the filtering.
#
# The optional 'opts' key is a list of option key/value pairs to pass
# to the filter.
sub log_msg_filter {
  my $text = shift;

  return $text if ! defined $config->{log_msg_filters};

  my $plugin;
  my @filters = @{ $config->{log_msg_filters} };
  my $context = $template->context();

  foreach my $filter_spec (@filters) {
    if($filter_spec->{name} ne 'standard') {
      eval {			# Make sure plugin is available, skip if not
	$plugin = $context->plugin($filter_spec->{name});
      };
      if($@) {
	warn "Plugin $filter_spec->{name} is not available\n";
	next;
      }
    }

    if(defined $plugin and $plugin->can('filter')) {
      $text = $plugin->filter($text, [], $filter_spec->{opts});
    } else {
      my $filter = $context->filter($filter_spec->{filter},
				    $filter_spec->{opts}) || next;
      $text = $filter->($text);
    }
  }
  return $text;
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
        $script = $1 if $r->uri =~ m|^((?:/\w+)+?)/\Q$repos\E| or
	  SVN::Web::X->throw(error => '(can\'t find script in %1)',
			     vars => [$r->uri]);
    }
    chdir ($base);
    $pool ||= SVN::Pool->new_default;
    load_config ('config.yaml');

    my($html, $cfg);
    eval {
	my (undef, $action, $path) = split ('/', $r->path_info, 3);
	$action ||= 'browse';
	$path ||= '';

	$cfg = { repos => $repos,
		 action => $action,
		 script => $script,
		 path => "/$path",
		 request => $r,
		 style => $config->{style},
		 cgi => ref($r) eq 'Apache::Request' ? $r : CGI->new(),
		 opts => exists $config->{actions}{$action}{opts} ?
		                $config->{actions}{$action}{opts} :
       		                { },
	       };

	SVN::Web::X->throw(error => '(action %1 not supported)',
			   vars => [$action])
	    unless exists $config->{actions}{lc($action)};

	$html = run($cfg);
    };

    my $e;
    if($e = SVN::Web::X->caught()) {
	$html->{template} = 'x';
	$html->{data}{error_msg} = loc($e->error(), @{ $e->vars() });
    }

    mod_perl_output($cfg, $html);
    return &Apache::OK;
}

=head1 SEE ALSO

L<SVN::Web::action>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-svn-web@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=SVN-Web>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 AUTHORS

Chia-liang Kao C<< <clkao@clkao.org> >>

Nik Clayton C<< <nik@FreeBSD.org> >>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao C<< <clkao@clkao.org> >>.

Copyright 2005 by Nik Clayton C<< <nik@FreeBSD.org> >>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

1;
