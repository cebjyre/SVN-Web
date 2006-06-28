#!/usr/bin/perl

use strict;
use warnings;

use Module::Build;

# $SVN::Core::VERSION is set in a manner that confuses Module::Build, so
# do an explicit version check here.
my $required_svn = '1.0.4';

die << "." unless eval { require SVN::Core; SVN::Core->VERSION ge $required_svn; };
===> Warning: SVN::Core is missing or outdated.

Please manually install SVN::Core by compiling Subversion
(version $required_svn or above) with SWIG/Perl bindings,
and try this installation process again.
.

my $class = Module::Build->subclass(code => <<'EOCODE');
    sub ACTION_code {
        my $self = shift;
	my $rc   = $self->SUPER::ACTION_code(@_);

	warn "Copying additional files\n";

	open(MAN, 'MANIFEST') or die 'Could not open MANIFEST';
	my @files = map { chomp; $_ } 
          grep { $_ =~ m{^lib/SVN/Web/(Style|Template|I18N)} } <MAN>;
        close(MAN);

        $self->copy_if_modified(from => $_, 
                                to   => File::Spec->catfile($self->blib(), $_))
          for map { $self->localize_file_path($_) } @files;

	return $rc;
    }
EOCODE

my %feature     = ();
my %config_data = ();
my %requires    = ('Template'                           => 0,
		   'YAML'                               => 0,
		   'Text::Diff'                         => 0,
		   'Text::Diff::HTML'                   => 0,
		   'Template::Plugin::Number::Format'   => 0,
		   'Locale::Maketext::Lexicon'          => 0,
		   'Locale::Maketext::Simple'           => 0,
		   'Exception::Class'                   => 1.22,
		   'List::Util'                         => 0,
		   'URI'                                => 0,
		   'Time::Zone'                         => 0,
		   'Test::WWW::Mechanize'               => 0,
		  );

# ------------------------------------------------------------------------

print <<EOM;

Welcome to SVN::Web.  The installer will now ask you a few questions to
make sure that the list of modules that SVN::Web requires is correct.

EOM

# ------------------------------------------------------------------------

print <<EOM;

SVN::Web can be used as a mod_perl handler.  This is much more
efficient than running it as a CGI script.

If you would like to use mod_perl support Apache::Request must be
installed.  If you answer yes to this question Apache::Request will be
added to the list of modules that SVN::Web requires.

Answering "no" to this question does not stop you running SVN::Web
under mod_perl at a later date, it just stops the installer from
looking for the necessary Perl modules.

EOM

if(Module::Build->y_n('==> Will you be using mod_perl?', 'n')) {
    $requires{'Apache::Request'} = 0;
}

# ------------------------------------------------------------------------

print <<EOM;

The test suite includes tests to check that SVN::Web works correctly
when installed under Apache.  You do not have to run these tests, but
if you intend to use SVN::Web with Apache then they may highlight
issues that were not encountered in the author's development
environment.

EOM

$feature{run_apache_tests} =
      Module::Build->y_n(q{==> Do you want to run the Apache tests?}, 'n');

while($feature{run_apache_tests}) {
    $config_data{apache_path} =
      Module::Build->prompt('==> Please enter the full path to your Apache httpd binary', '/usr/local/sbin/httpd');

    if(! -x $config_data{apache_path}) {
        print "The path\n\n";
	print "  '", $config_data{apache_path}, "'\n\n";
	print "is not executable.\n\n";
	next;
    }

    last;
} continue {
    $feature{run_apache_tests} =
      Module::Build->y_n('==> Do you still want to run the Apache tests?', 'n');
}

# ------------------------------------------------------------------------

if($feature{run_apache_tests}) {
    print <<EOM;

SVN::Web can be run under Apache as a CGI script.

EOM

    $feature{run_apache_cgi_tests} =
      Module::Build->y_n('==> Do you want to test that SVN::Web works with Apache as a CGI script', 'y');
}

# ------------------------------------------------------------------------

if($feature{run_apache_tests} and exists $requires{'Apache::Request'}) {
    print <<EOM;

You have said you want to run SVN::Web under mod_perl.

EOM

    $feature{run_mod_perl_tests} =
      Module::Build->y_n(q{==> Do you want to test mod_perl support?}, 'y');
} else {
    $feature{run_mod_perl_tests} = 0;
}

$requires{'Apache::Request'} = 0 if $feature{run_mod_perl_tests};

# ------------------------------------------------------------------------

print <<EOM;

SVN::Web includes a simple web server (called "svnweb-server") that
uses the HTTP::Server::Simple module.

Would you like to use this server?  If so, HTTP::Server::Simple will
be added to the list of modules that SVN::Web requires and tests will
be run before installation to make sure that it is working correctly.

EOM

$feature{'run_svnweb-server_tests'} =
      Module::Build->y_n(q{==> Do you want to test svnweb-server?}, 'y');

$requires{'HTTP::Server::Simple'} = 0 if $feature{'run_svnweb-server_tests'};

if($feature{run_apache_tests} or $feature{'run_svnweb-server_tests'}) {
    print <<EOM;

The httpd server will be started listening on the loopback address
(127.0.0.1).  However, it must be bound to a network port that is not
currently being used by another service.

EOM

    until(defined $config_data{httpd_port}) {
        $config_data{httpd_port} =
	  Module::Build->prompt('==> Please enter a spare port', 8080);

	if($config_data{httpd_port} !~ /^\d+$/) {
	    print "The port must contain only digits.\n\n";
	    next;
	}

	if($config_data{httpd_port} < 1024 and $> != 0) {
	    print <<EOM;

You have entered a port number that is less than a 1024, and you are
not the root user.  Please enter a different port number.

EOM

	    next;
	}

	if($config_data{httpd_port} < 1) {
	    print "Ports less than 1 are not allowed\n\n";
	    next;
	}

	if($config_data{httpd_port} > 65535) {
	    print "Ports greater than 65535 are not allowed\n\n";
	    next;
	}

	last;
    } continue {
	$config_data{httpd_port} = undef;
    }
}

# ------------------------------------------------------------------------

print <<EOM;

SVN::Web can use plugins to turn e-mail addresses and URLs in
Subversion commit messages in to clickable hyperlinks.

EOM

if(Module::Build->y_n('==> Do you want to install these plugins?', 'y')) {
    $requires{'Template::Plugin::Clickable'} = 0;
    $requires{'Template::Plugin::Clickable::Email'} = 0;
}

# ------------------------------------------------------------------------

$b = $class->new(
    dist_name          => 'SVN-Web',
    dist_author        => 'Nik Clayton <nik@FreeBSD.org>',
    license            => 'perl',
    module_name        => 'SVN::Web',
    create_makefile_pl => 'passthrough',
    create_readme      => 0,
    sign               => 1,
    script_files       => [ 'bin/svnweb-install', 'bin/svnweb-server' ],
    requires           => \%requires,
    recommends         => { 'Cache::Cache',                      => 0,
	                    'Template::Plugin::Subst'            => 0,
                            'Test::Benchmark'                    => 0,
                            'Test::HTML::Tidy'                   => 0,
                            'XML::RSS::Parser'                   => 0, },
    add_to_cleanup     => [ qw't/repos*' ],
);

$b->config_data($_ => $config_data{$_}) foreach keys %config_data;
$b->feature($_ => $feature{$_})         foreach keys %feature;

$b->create_build_script();
