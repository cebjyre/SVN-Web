# -*- Mode: cperl; cperl-indent-level: 4 -*-
package SVN::Web;

use strict;
use warnings;

use URI::Escape;
use SVN::Core;
use SVN::Repos;
use YAML ();
use Template;
use File::Spec;
use POSIX ();

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
        Style  => 'gettext',
        Decode => 0,
    );
}

use constant mod_perl_2 =>
    (exists $ENV{MOD_PERL_API_VERSION} and $ENV{MOD_PERL_API_VERSION} >= 2);

our $VERSION = 0.48;

my $template;
my $config;

my %REPOS;

sub load_config {
    my $file = shift || 'config.yaml';
    $config ||= YAML::LoadFile($file);

   # Deal with possibly conflicting 'templatedir' and 'templatedirs' settings.

    # If neither of them are set, use 'templatedirs'
    if(!exists $config->{templatedir} and !exists $config->{templatedirs}) {
        $config->{templatedirs} = ['template/trac'];
    }

    # If 'templatedir' is the only one set, use it.
    if(exists $config->{templatedir} and !exists $config->{templatedirs}) {
        $config->{templatedirs} = [$config->{templatedir}];
        delete $config->{templatedir};
    }

    # If they're both set then throw an error
    if(exists $config->{templatedir} and exists $config->{templatedirs}) {
        die "templatedir and templatedirs both defined in config.yaml";
    }

    # Handle tt_compile_dir.  If it doesn't exist then set it to undef.
    # If it does exist, and is defined, append a '.' and the current
    # real UID, to help ensure uniqueness.
    if(!exists $config->{tt_compile_dir}) {
        $config->{tt_compile_dir} = undef;    # undef == no compiling
    } else {
        if(defined $config->{tt_compile_dir}) {
            $config->{tt_compile_dir} .= '.' . $<;
        }
    }

    # Handle timedate_format
    if(! exists $config->{timedate_format}) {
	$config->{timedate_format} = '%Y/%m/%d %H:%M:%S';
    }

    # Set the timezone, if not already specified.
    $config->{timezone} = '' unless exists $config->{timezone};

    # If cache/opts/directory_umask is configured, and it has a leading
    # 0 then ensure it's treated as an octal number.
    $config->{cache}{opts}{directory_umask} =
      oct($config->{cache}{opts}{directory_umask})
	if exists $config->{cache}{opts}{directory_umask}
	  and $config->{cache}{opts}{directory_umask} =~ /^0/;;

    return;
}

sub set_config {
    $config = shift;
}

sub get_config {
    return $config;
}

my $repospool = SVN::Pool->new;

sub get_repos {
    my($repos) = @_;

    SVN::Web::X->throw(
        error => '(unconfigured repository)',
        vars  => []
        )
        unless $config->{repos} || $config->{reposparent};

    my $repo_path =
        $config->{reposparent}
        ? "$config->{reposparent}/$repos"
        : $config->{repos}{$repos};

    SVN::Web::X->throw(
        error => '(no such repo %1 %2)',
        vars  => [$repos, $repo_path]
        )
        unless($config->{reposparent}
        && -d "$config->{reposparent}/$repos")
        || exists $config->{repos}{$repos} && -d $config->{repos}{$repos};

    $repo_path =~ s{/$}{}g;	# Trim trailing '/', SVN::Repos::open fails
				# otherwise

    eval { $REPOS{$repos} ||= SVN::Repos::open($repo_path, $repospool); };

    if($@) {
        my $e = $@;
        SVN::Web::X->throw(
            error => '(SVN::Repos::open failed: %1 %2)',
            vars  => [$repo_path, $e]
        );
    }

    if($config->{block}) {
        foreach my $blocked (@{ $config->{block} }) {
            delete $REPOS{$blocked};
        }
    }
}

sub repos_list {
    load_config('config.yaml');

    my @repos;
    if($config->{reposparent}) {
        opendir my $dh, "$config->{reposparent}"
            or SVN::Web::X->throw(
            error => '(opendir reposparent %1 %2)',
            vars  => [$config->{reposparent}, $!]
            );

        foreach my $dir (grep { -d "$config->{reposparent}/$_" && !/^\./ }
            readdir $dh) {
            push @repos, $dir;
        }
    } else {
        @repos = keys %{ $config->{repos} };
    }

    my %blocked = map { $_ => 1 } @{ $config->{block} };

    return sort grep { !$blocked{$_} } @repos;
}

sub get_handler {
    my $cfg = shift;
    my $pkg;

    if(exists $config->{actions}{ $cfg->{action} }) {
        if(ref($config->{actions}{ $cfg->{action} }) eq 'HASH') {
            if(exists $config->{actions}{ $cfg->{action} }{class}) {
                $pkg = $config->{actions}{ $cfg->{action} }{class};
            }
        }
    }

    unless($pkg) {
        $pkg = $cfg->{action};
        $pkg =~ s/^(\w)/\U$1/;
        $pkg = __PACKAGE__ . "::$pkg";
    }
    eval "require $pkg && $pkg->can('run')"
        or SVN::Web::X->throw(
        error => '(missing package %1 for action %2: %3)',
        vars  => [$pkg, $cfg->{action}, $@]
        );
    my $repos = $cfg->{repos} ? $REPOS{ $cfg->{repos} } : undef;
    return $pkg->new(
        %$cfg,
        reposname => $cfg->{repos},
        repos     => $repos,
        config    => $config
    );
}

sub run {
    my $cfg = shift;

    my $pool = SVN::Pool->new_default;

    my $obj;
    my $html;

    my $cache;

    if(defined $config->{cache}{class}) {
	eval "require $config->{cache}{class}"
	  or SVN::Web::X->throw(error => '(require %1 failed: %2)',
				vars  => [$config->{cache}{class}, $@]
			       );

	$config->{cache}{opts} = {}  unless exists $config->{cache}{opts};
	$config->{cache}{opts}{namespace} = $cfg->{repos};
	$cache = $config->{cache}{class}->new($config->{cache}{opts});
    }

    if(defined $cfg->{repos} && length $cfg->{repos}) {
        get_repos($cfg->{repos});
    }

    if($cfg->{repos} && $REPOS{ $cfg->{repos} }) {
        @{ $cfg->{navpaths} } = File::Spec::Unix->splitdir($cfg->{path});
        shift @{ $cfg->{navpaths} };

        # should use attribute or things alike
        $obj = get_handler(
            {   %$cfg,
                opts => exists $config->{actions}{ $cfg->{action} }{opts}
                ? $config->{actions}{ $cfg->{action} }{opts}
                : {},
            }
        );
    } else {
        $cfg->{action} = 'list';
        $obj = get_handler(
            {   %$cfg,
                opts => exists $config->{actions}{ $cfg->{action} }{opts}
                ? $config->{actions}{ $cfg->{action} }{opts}
                : {},
            }
        );
    }

    # Determine the language to use
    my $lang = get_language($cfg->{cgi}, $config->{languages},
			    $config->{default_language});

    $cfg->{lang} = $lang;	# Note the preference, stored in a cookie
				# later

    loc_lang($lang);		# Set the localisation language

    # Generate output, from the cache if necessary.

    # Does the object support caching?  If so, get the cache key
    my $cache_key;
    if(defined $cache and $obj->can('cache_key')) {
	$cache_key = join(':', $cfg->{action}, $lang) . ':' . $obj->cache_key();
    }

    # If there's a key, retrieve the data from the cache
    $html = $cache->get($cache_key) if defined $cache_key;

    # No data?  Get the object to generate it, then cache it
    if(! defined $html) {
	$html = $obj->run();

	if(defined $cache_key) {
	    $cache->set($cache_key, $html, $cfg->{cache}{expires_in});
	}
    }

    $pool->clear;
    return $html;
}

sub get_language {
    my $obj          = shift;	# CGI or Apache instance
    my $languages    = shift;	# Hash ref of valid langauges
    my $default_lang = shift;	# Default language

    my $lang = $obj->param('lang');

    # If lang was included in the query string then delete it now we've
    # got it.  This stops it showing up in from calls to self_url().  Have
    # to do this in two different ways, depending on whether this is an
    # Apache::Request or a CGI object.
    if(defined $lang) {
	if(ref($obj) eq 'Apache::Request') {
	    my $table = $obj->parms();
	    delete $table->{lang};
	} else {
	    $obj->delete('lang'); # Remove from self_url() invocations
	}
    }

    # If no valid lang=.. param was found then check the user's cookies
    if(! defined $lang) {
	if(ref($obj) eq 'Apache::Request') {
	    my $cookies = Apache::Cookie->fetch();
	    if(defined $cookies->{'svnweb-lang'}) {
		$lang = $cookies->{'svnweb-lang'}->value();
	    }
	} else {
	    $lang = $obj->cookie('svnweb-lang');
	}
    }

    # If $lang is not defined, or if it's not in the hash of valid languages
    # then use the default configured language, falling back to English as
    # a last resort.
    if(! defined $lang or ! exists $languages->{$lang}) {
	$lang = $default_lang;
	$lang = 'en' unless defined $lang;
    }

    die "lang is not defined" unless defined $lang;

    return $lang;
}

sub cgi_output {
    my($cfg, $html) = @_;

    return unless defined $html;

    my @cookies = ();
    push @cookies, $cfg->{cgi}->cookie(-name  => 'svnweb-lang',
				       -value => $cfg->{lang},
				      );

    if(ref($html)) {
        print $cfg->{cgi}->header(
            -charset => $html->{charset}  || 'UTF-8',
            -type    => $html->{mimetype} || 'text/html',
	    -cookie  => \@cookies,
        );

        if($html->{template}) {
            $template->process($html->{template},
                { %$cfg, %{ $html->{data} } })
                or die "Template::process() error: " . $template->error;
        } else {
            print $html->{body};
        }
    } else {
        print $cfg->{cgi}->header(
            -charset => 'UTF-8',
            -type    => 'text/html',
	    -cookie  => \@cookies,
        );
        print $html;
    }
}

sub mod_perl_output {
    my($cfg, $html) = @_;

    my @cookies = ();

    push @cookies, Apache::Cookie->new($cfg->{request},
				       -name  => 'svnweb-lang',
				       -value => $cfg->{lang},
				      );

    $_->bake() foreach @cookies;

    if(ref($html)) {
        my $content_type = $html->{mimetype} || 'text/html';
        $content_type .= '; charset=';
        $content_type .= $html->{charset} || 'UTF-8';
        $cfg->{request}->content_type($content_type);

	if(mod_perl_2) {
	    $cfg->{request}->headers_out();
	} else {
	    $cfg->{request}->send_http_header();
	}

        if($html->{template}) {
            $template ||= get_template();
            $template->process($html->{template},
                { %$cfg, %{ $html->{data} } },
                $cfg->{request})
                or die $template->error;
        } else {
            $cfg->{request}->print($html->{body});
        }
    } else {
        $cfg->{request}->content_type('text/html; charset=UTF-8');

	if(mod_perl_2) {
	    $cfg->{request}->headers_out();
	} else {
	    $cfg->{request}->send_http_header();
	}

        $cfg->{request}->print($html);
    }
}

our $pool;    # global pool for holding opened repos

sub get_template {
    Template->new(
        {   INCLUDE_PATH => $config->{templatedirs},
            COMPILE_DIR  => $config->{tt_compile_dir},
            FILTERS      => {
                l       => ([\&loc_filter, 1]),
                log_msg => \&log_msg_filter,
            }
        }
    );
}

sub run_cgi {
    my %opts = @_;
    die $@ if $@;
    $pool ||= SVN::Pool->new_default;
    load_config('config.yaml');
    $config->{$_} = $opts{$_} foreach keys %opts;
    $template               ||= get_template();
    $config->{diff_context} ||= 3;

    # Pull in the configured CGI class.  Propogate any errors back, and
    # call the correct import() routine.
    #
    # This is more complicated than it should be.  If $config->{cgi_class}
    # is defined then use that.  If not, use CGI::Fast.  If that can't be
    # loaded then use CGI.
    #
    # There's a problem with (at least) CGI::Fast.  It's possible for the
    # require() to fail, but for CGI::Fast's entry in %INC to be populated.
    # This seems to happen when CGI::Fast loads, but its dependency (such
    # as FCGI) fails to load.  So if the require() fails for any reason
    # we explicitly remove the %INC entry.

    my $cgi_class;
    my $eval_result;

    if(exists $config->{cgi_class}) {
        $eval_result = eval "require $config->{cgi_class}";
        die $@ if $@;
        $cgi_class = $config->{cgi_class};
    } else {
        foreach('CGI::Fast', 'CGI') {
            $eval_result = eval "require $_";
            if($@) {
                my $path = $_;
                $path =~ s{::}{/}g;
                $path .= '.pm';
                delete $INC{$path};
            } else {
                $cgi_class = $_;
                last;
            }
        }
    }

    die "Could not load a CGI class" unless $eval_result;
    $cgi_class->import();

    # Save the selected module so that future calls to this routine
    # don't waste time trying to find the correct class.
    $config->{cgi_class} = $cgi_class unless exists $config->{cgi_class};

    while(my $cgi = $cgi_class->new) {
        my($html, $cfg);

	$cfg = { style     => $config->{style},
		 cgi       => $cgi,
		 languages => $config->{languages},
	       };

        eval {
	    my($action, $base, $repo, $script, $path) = crack_url($cgi);

            SVN::Web::X->throw(
                error => '(action %1 not supported)',
                vars  => [$action]
                )
                unless exists $config->{actions}{ lc($action) };

            $cfg->{repos}    = $repo;
	    $cfg->{action}   = $action;
	    $cfg->{path}     = $path;
	    $cfg->{script}   = $script;
	    $cfg->{base_uri} = $base;

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
    my @args    = @_;
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

    return $text if !defined $config->{log_msg_filters};

    my $plugin;
    my @filters = @{ $config->{log_msg_filters} };
    my $context = $template->context();

    foreach my $filter_spec (@filters) {
        if($filter_spec->{name} ne 'standard') {
            eval {    # Make sure plugin is available, skip if not
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
                $filter_spec->{opts})
                || next;
            $text = $filter->($text);
        }
    }
    return $text;
}

# Crack a URL and determine the components we need.  Takes either a CGI
# or Apache object as the only argument, so this is misnamed.
sub crack_url {
    my $obj = shift;

#    warn "REF: ", ref($obj), "\n";

    my($location, $filename, $path_info, $uri);

    if(ref($obj) eq 'Apache') {
	$location  = $obj->location();
	$filename  = $obj->filename();
	$path_info = $obj->path_info();
	$uri       = $obj->uri();
    } else {
	# For compatability with Apache::Request->filename():
	# 1. $location is the current working directory
	# 2. $filename is $location + the first component of path_info()
	$location  = POSIX::getcwd();
	
	# Split path_info, keeping trailing fields
	my @path = split('/', $obj->path_info(), -1);
	$filename = $location;
	if($#path) {
	    shift @path;	# Leading empty null field
	    if(defined $path[0]) {
		$filename .= '/' . shift @path;
	    }
	}

	$path_info = '/' . join('/', @path);
	$uri       = $obj->url(-relative => 1, -path_info => 1);
    }

#    warn "LOCATION: $location\n";
#    warn "FILENAME: $filename\n";
#    warn "PATH_INFO: $path_info\n";
#    warn "URI: $uri\n";

    my($action, $base, $repo, $script, $path);

    # Determine $repo.
    #
    # This is used as the key in to the hash of configured repositories.
    # It may be the empty string, in which case the action to run is
    # the 'list repositories' action.
    if($location eq $filename) {
	$repo   = '';		# No repo, show repo list
	$action = 'list';
    } else {
	$repo = $filename;
	$repo =~ s{^$location/}{}; # Remove the location
    }

#    warn "REPO: $repo\n";

    # Determine $action
    #
    # This will be used as the key in to the hash of configured actions
    # and their classes.  If no action is included in the URL then the
    # default action is 'browse'.
    if(! defined $action) {
	if($path_info eq '/' or $path_info eq '') {
	    $action = 'browse';
	} else {
	    my @path = split('/', $path_info);
	    $action = $path[1];
	}
    }

#    warn "ACTION: $action\n";

    # Determine $path
    #
    # This is the path in the repository that we will be acting on.  Some
    # actions don't need this set.
    if($action eq 'list') {
	$path = '/';
    } else {
	if($path_info eq '' or $path_info eq '/') {
	    $path = '/';
	} else {
	    $path = $path_info;
	    $path =~ s{^/$action}{};
	}
    }

    # Unescape it, as it will have been escaped on the web page
    $path = uri_unescape($path);

#    warn "PATH: $path\n";

    # Determine $script
    #
    # $script is the URI that points to the SVN::Web script.  If this is
    # CGI then it's something like '/svnweb/index.cgi'.  If it's an Apache
    # handler then it will be a directory reference, like '/svnweb', or
    # possibly '/'.
    #
    # In the CGI case this is just the SCRIPT_NAME environment variable.
    # There's no Apache equivalent, so take the URI, and starting from the
    # right end, remove the path, the action, and the repository name.  The
    # result is the root URI for the handler.
    if(ref($obj) eq 'Apache') {
	$script = $uri;
	$script =~ s/$path$//;
	$script =~ s{/$action$}{};
	$script =~ s{/$repo$}{};
    } else {
	$script = $ENV{SCRIPT_NAME};
    }

    $script =~ s{/$}{};		# Remove trailing slash

#    warn "SCRIPT: $script\n";

    # Determine $base
    #
    # $base is the URI that points to the directory that contains index.cgi,
    # config.yaml, css/, etc.  It's needed to generate links to the .css
    # files.

    # In all cases, $base is a substring of $script.  In the mod_perl and
    # svnweb-server cases it's identical
    $base = $script;		# Only in mod_perl case

    # If we're running as a CGI then SCRIPT_FILENAME will (or should)
    # be set in the environment.  If it is, find the filename component,
    # which should be the name of this script, and remove that component
    # from $base.
    #
    # This turns '/svnweb/index.cgi' into '/svnweb/'.  We go through these
    # shenanigans so that the script can be called something other than
    # index.cgi.
    if(ref($obj) ne 'Apache') {
	if(exists $ENV{SCRIPT_FILENAME}) {
	    my $path = $ENV{SCRIPT_FILENAME};
	    my(undef, undef, $file) = File::Spec->splitpath($path);
	    $base =~ s/$file$//;
	} else {
#	    warn 'SCRIPT_FILENAME not set in environment, assuming script is called index.cgi';
	    $base =~ s/index.cgi$//;
	}
    }
    $base =~ s{/$}{};		# Remove trailing slash

#    warn "BASE: $base\n";

    return($action, $base, $repo, $script, $path);
}

sub handler {
    my $ok;
    require CGI;

    eval {
        if(mod_perl_2) {
            require Apache2::RequestRec;
            require Apache2::RequestUtil;
            require Apache2::RequestIO;
            require Apache2::Response;
            require Apache2::Request;
            require Apache2::Const;
            Apache2::Const->import(-compile => qw(OK DECLINED));
            $ok = &Apache2::Const::OK;
        } else {
            require Apache::Request;
            require Apache::Constants;
	    require Apache::Cookie;
            Apache::Constants->import(qw(OK DECLINED));
            $ok = &Apache::Constants::OK;
        }
    };

    die $@ if $@;		# Fail if the mod_perl imports failed

    my $r = shift;

    my $apr = Apache::Request->new($r);

    my($action, $base, $repo, $script, $path) = crack_url($r);

    chdir($r->location());
    $pool ||= SVN::Pool->new_default;
    load_config('config.yaml');

    my($html, $cfg);

    $cfg = { style     => $config->{style},
	     cgi       => $apr,
	     languages => $config->{languages},
	     request   => $r,
	   };

    eval {
	SVN::Web::X->throw(
	    error => '(action %1 not supported)',
            vars  => [$action]
            )
	    unless exists $config->{actions}{ lc($action) };

	$cfg->{repos}    = $repo;
	$cfg->{action}   = $action;
	$cfg->{path}     = $path;
	$cfg->{script}   = $script;
	$cfg->{base_uri} = $base;

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

    mod_perl_output($cfg, $html);
    return $ok;
}

1;

__END__

=head1 NAME

SVN::Web - Subversion repository web frontend

=head1 SYNOPSIS

To get started with SVN::Web.

=over

=item 1.

Create a directory for SVN::Web's configuration files, templates,
stylesheets, and other data.

  mkdir svnweb

=item 2.

Run C<svnweb-install> in this directory to configure the environment.

  cd svnweb
  svnweb-install

=item 3.

Edit the file F<config.yaml> that's been created, and add the following
two lines:

  repos:
    test: '/path/to/repo'

C</path/to/repo> should be the path to an existing Subversion repository
on the local disk.

=item 4.

Either configure your web server (see L</"WEB SERVERS">) to use SVN::Web,
or run C<svnweb-server> to start a simple web server for testing.

  svnweb-server

Note: C<svnweb-server> requires HTTP::Server::Simple to run, which is not
a requirement of SVN::Web.  You may have to install HTTP::Server::Simple
first.

=item 5.

Point your web browser at the correct URL to browse your repository.
If you've run C<svnweb-server> then this is L<http://localhost:8080/>.

=back

See
L<http://jc.ngo.org.uk/svnweb/jc/browse/nik/CPAN/SVN-Web/trunk/>
for the SVN::Web source code, browsed using SVN::Web.

=head1 DESCRIPTION

SVN::Web provides a web interface to subversion repositories. SVN::Web's
features include:

=over

=item *

Viewing multiple Subversion repositories.

=item *

Browsing every revision of the repository.

=item *

Viewing the contents of files in the repository at any revision.

=item *

Viewing diffs of arbitrary revisions of any file.  Diffs can be viewed
as plain unified diffs, or HTML diffs that use colour to more easily
show what's changed.

=item *

Viewing the revision log of files and directories, see what was changed
when, by who.

=item *

Generating RSS feeds of commits, down to the granularity of individual
files.  The RSS feeds are auto-discoverable in modern web browsers.

=item *

Viewing everything that was changed in a revision, and step through revisions
one at a time, viewing the history of the repository.

=item *

Viewing the interface in a number of different languages.  SVN::Web's
interface is fully templated and localised, allowing you to change the
look-and-feel without writing any code; all strings in the interface
are stored in a separate file, to make localising to different
languages easier.

=item *

Rich log message linking.  You can configure SVN::Web to recognise
patterns in your log messages and automatically generate links to other
web based systems.  For example, if your log messages often refer to
tickets in your request tracking system:

  Reported in: t#1234

then SVN::Web can turn C<t#1234> in to a link to that ticket.  SVN::Web
can also be configured to recognise e-mail addresses, URLs, and anything
else you wish to make clickable.

=item *

Caching.  Internally, SVN::Web caches most of the data it gets from
the repository, helping to speed up repeated visits to the same page,
and reducing the impact on your repository server.

=item *

As L<SVK> repositories are also Subversion repositories, you can do all of
the above with those too.

=back

Additional actions can easily be added to the base set supported by the
core of SVN::Web.

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

=head2 Languages

SVN::Web's interface is fully localised and ships with a number of
translations.  The default web interface allows the user to choose
from the available localisations at will, and the user's choice is
saved in a cookie.

Two options control SVN::Web's localisations.

The first, C<languages>, specifies the localisations that are considered
I<available>.  This is a hash.  The keys are the basenames of available
localisation files, the values are the language name as it should appear
in the interface.  C<svnweb-install> will have set this to a default
value.

To find the available localisation files look in the F<po/> directory
that was created in the directory in which you ran C<svnweb-install>.
For example, the default (as of SVN::Web 0.48) is:

  languages:
    en: English
    fr: Fran&ccedil;ais
    zh_cn: Chinese (Simplified)
    zh_tw: Chinese (Traditional)

The second, C<default_language>, specifies the language to use if the
user has not selected one.  The value for this option should be one of
the keys defined in C<languages>.  For example;

  default_language: fr

=head2 Data cache

SVN::Web can use any module implementing the L<Cache::Cache> interface
to cache the data it retrieves from the repository.  Since this data does
not normally change this reduces the time it takes SVN::Web to generate
results.

This cache is B<not> enabled by default.

To enable the cache you must specify a class that implements a
L<Cache::Cache> interface.  L<Cache::SizeAwareFileCache> is a good
choice.

  cache:
    class: Cache::SizeAwareFileCache

The class' constructor may take various options.  Specify those under
the C<opts> key.

For example, L<Cache::SizeAwareFileCache> supports (among others)
options called C<max_size>, C<cache_root>, and C<directory_umask>.
These could be configured like so:

  # Use the SizeAwareFileCache.  Place it under /var/tmp instead of
  # the default (/tmp), use a custom umask, and limit the cache size to
  # 1MB
  cache:
    class: Cache::SizeAwareFileCache
    opts:
      max_size: 1000000
      cache_root: /var/tmp/svn-web-cache
      directory_umask: 077

B<Note:> The C<namespace> option, if specified, is ignored, and is always
set to the name of the repository being accessed.

=head2 Template cache

Template Toolkit can cache the results of template processing to make
future processing faster.

By default the cache is not enabled.  Use C<tt_compile_dir> to enable it.
Set this directive to the name of a directory where the UID that SVN::Web is
being run as can create files.

For example:

   tt_compile_dir: /var/tmp/tt-cache

A literal C<.> and the UID of the process running SVN::Web will be appended
to this string to generate the final directory name.  For example, if
SVN::Web is being run under UID 80 then the final directory name is
F</var/tmp/tt-cache.80>.  Since the cached templates are always created
with mode 0600 this ensures that different users running SVN::Web can not
overwrite one another's cached templates.

This directive has no default value.  If it is not defined then no caching
will take place.

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
ticket #1234 in your ticketing system.  L<Template::Plugin::Subst> might
be helpful if you do this.

=head2 Time and date formatting

There are a number of places in the web interface where SVN::Web will
display a timestamp from Subversion.

Internally, Subversion stores times in UTC.  You may wish to show them in
your local timezone (or some other timezone).  You may also wish to change
the formatting of the timestamp.

To do this use the C<timezone> and C<timedate_format> configuration options.

C<timezone> takes one of three settings.

=over

=item 1.

If not set, or set to the empty string, SVN::Web will show all times in
UTC.  This is the default behaviour.

=item 2.

If set to the string C<local> then SVN::Web will adjust all timestamps to
the server's local timezone.

=item 3.

If set to a timezone name, such as C<BST> or C<EST>, then SVN::Web will
adjust all timestamps to that timezone.

=back

When displaying timestamps SVN::Web uses the L<POSIX> C<strftime()>
function.  You can change the format string that is provided, thereby
changing how the timestamp is formatted.  Use the C<timedate_format>
configuration directive for this.

The default value is:

  timedate_format: '%Y/%m/%d %H:%M:%S'

Using this format, a quarter past one in the afternoon on the 15th of
May 2006 would appear as:

  2006/05/15 13:15:00

If instead that was:

  timedate_format: '%a. %b %d, %l:%M%p'

then the same timestamp would appear as:

  Mon. May 15, 1:15pm

Note that strftime(3) on different operating systems supports different
format specifiers, so consult your system's strftime(3) manual page to
see which specifiers are available.

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
C<< SVN::Web::<Action> >> package.

=head2 CGI class

SVN::Web can use a custom CGI class.  By default SVN::Web will use
L<CGI::Fast> if it is installed, and fallback to using L<CGI> otherwise.

Of course, if you have your own class that implements the CGI interface
you may specify it here too.

  cgi_class: 'My::CGI::Subclass'

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

=head1 WEB SERVERS

This section explains how to configure some common webservers to run
SVN::Web.  In all cases, C</path/to/svnweb> in the examples is the
directory you ran C<svnweb-install> in, and contains F<config.yaml>.

If you've configured a web server that isn't listed here for SVN::Web,
please send in the instructions so they can be included in a future
release.

=head2 svnweb-server

C<svnweb-server> is a simple web server that runs SVN::Web, and is
included and installed by this module.  It may be all you need to
productively use SVN::Web without needing to install a larger server.
To use it, run:

  svnweb-server --root /path/to/svnweb

See C<perldoc svnweb-server> for details about additional options you can
use.

=head2 Apache as CGI

Apache must be configured to support CGI scripts in the directory in which
you ran C<svnweb-install>

  <Directory /path/to/svnweb>
    Options All ExecCGI
  </Directory>

If F</path/to/svnweb> is not under your normal Apache web hosting root then
you will need to alias a URL to that path too.

  Alias /svnweb /path/to/svnweb

With that configuration the full path to browse the repository would be:

  http://server/svnweb/index.cgi

=head2 Apache with mod_perl or mod_perl2

You can use mod_perl or mod_perl2 with SVN::Web.  You must install
L<Apache::Request|Apache::Request> (for mod_perl) or
L<Apache::Request2|Apache::Request2> (for mod_perl2) to enable this support.

The following Apache configuration is suitable.

    <Directory /path/to/svnweb>
      AllowOverride None
      Options None
      SetHandler perl-script
      PerlHandler SVN::Web
    </Directory>

    <Directory /path/to/svnweb/css>
      SetHandler default-handler
    </Directory>

If F</path/to/svnweb> is not under your normal Apache web hosting root then
you will need to alias a URL to that path too.

  Alias /svnweb /path/to/svnweb

With that configuration the full path to browse the repository would be:

  http://server/svnweb/

=head2 Apache with FastCGI

SVN::Web works with Apache and FastCGI.  The following Apache configuration
is suitable.

  FastCgiServer /path/to/svnweb/index.cgi
  ScriptAlias /svnweb /path/to/svnweb/index.cgi

  Alias /svnweb/css /path/to/svnweb/css
  <Directory /path/to/svnweb/css>
     SetHandler default-handler
  </Directory>

=head1 MAILING LIST

There is a mailing list for SVN::Web users and developers.  The address
is svnweb@ngo.org.uk.  To subscribe please visit
L<http://jc.ngo.org.uk/mailman/listinfo/svnweb>.

=head1 SEE ALSO

L<SVN::Web::action>, svnweb-install(1), svnweb-server(1)

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

Copyright 2005-2006 by Nik Clayton C<< <nik@FreeBSD.org> >>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
