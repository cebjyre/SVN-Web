#!/usr/bin/perl
my $required_svn = '1.0.4';

use inc::Module::Install;

name		('SVN-Web');
author		('Chia-liang Kao <clkao@clkao.org>');
abstract	('Subversion repository web frontend');
install_script  ('bin/svnweb-install');
license		('perl');
version_from	('lib/SVN/Web.pm');
requires(
        'Template'    => '0',
        'YAML'        => '0',
        'XML::RSS'    => '0',
        'Text::Diff'  => '0',
	'Locale::Maketext::Simple' => 0);

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
