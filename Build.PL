#!/usr/bin/perl

use strict;
use warnings;

use Module::Build;

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

$class->new(
    dist_name          => 'SVN-Web',
    dist_author        => 'Nik Clayton <nik@FreeBSD.org>',
    license            => 'perl',
    module_name        => 'SVN::Web',
    create_makefile_pl => 'passthrough',
    create_readme      => 0,
    sign               => 1,
    script_files       => [ 'bin/svnweb-install', 'bin/svnweb-server' ],
    requires	       => { 'Template'                           => 0,
                            'YAML'                               => 0,
                            'XML::RSS'                           => 0,
                            'Text::Diff'                         => 0,
	                    'Text::Diff::HTML'                   => 0,
	                    'Template::Plugin::Number::Format'   => 0,
	                    'Locale::Maketext::Lexicon'          => 0,
	                    'Locale::Maketext::Simple'           => 0,
	                    'Exception::Class'                   => 1.22,
	                    'List::Util'                         => 0,
                            'URI'                                => 0, },
    recommends         => { 'Cache::Cache',                      => 0,
                            'Template::Plugin::Clickable'        => 0,
	                    'Template::Plugin::Clickable::Email' => 0,
	                    'Template::Plugin::Subst'            => 0,
	                    'HTTP::Server::Simple'               => 0,
                            'Test::Benchmark'                    => 0,
                            'Test::HTML::Tidy'                   => 0, },
    add_to_cleanup     => [ qw't/repos*' ],
)->create_build_script();
