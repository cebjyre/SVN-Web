#!/usr/bin/perl
my $required_svn = '1.0.4';

use inc::Module::Install;

name		('SVN-Web');
author		('Nik Clayton <nik@FreeBSD.org>');
abstract	('Subversion repository web frontend');
install_script  ('bin/svnweb-install');
license		('perl');
version_from	('lib/SVN/Web.pm');
clean_files	(qw't/repos*');
requires(
        'Template'    => '0',
        'YAML'        => '0',
        'XML::RSS'    => '0',
        'Text::Diff'  => '0',
	'Text::Diff::HTML' => '0',
	'Template::Plugin::Number::Format' => '0',
	'Locale::Maketext::Lexicon' => 0,
	'Locale::Maketext::Simple' => 0,
	'URI' => 0,
	'Exception::Class' => 0,
	'List::Util' => 0);

recommends(
	'Template::Plugin::Clickable' => 0,
	'Template::Plugin::Clickable::Email' => 0,
	'Template::Plugin::Subst' => 0,
	);

include('ExtUtils::AutoInstall');
auto_install();

WriteAll( sign => 1 );

$::VERSION = $required_svn;
die << "." unless eval {require SVN::Core; SVN::Core->VERSION >= main->VERSION };
===> Warning: SVN::Core missing or outdated.
Please manually install SVN::Core by compiling Subversion
(version $required_svn or above) with SWIG/Perl bindings,
and try this installation process again.
.
