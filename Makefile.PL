#!/usr/bin/perl
my $required_svn = '1.0.4';

use inc::Module::Install;

name		('SVN-Web');
author		('Chia-liang Kao <clkao@clkao.org>');
abstract	('Subversion repository web frontend');
license		('perl');
version_from	('lib/SVN/Web.pm');
requires(
        'SVN::Core'   => $required_svn,
        'Template'    => '0',
        'YAML'        => '0',
        'XML::RSS'    => '0',
        'Text::Diff'  => '0',
	'Locale::Maketext::Simple' => 0);

include('ExtUtils::AutoInstall');
auto_install();

WriteAll( sign => 1 );

die "SVN::Core $required_svn must be manually installed"
    unless eval {require SVN::Core} && $SVN::Core::VERSION >= $required_svn;
