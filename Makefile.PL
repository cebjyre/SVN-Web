#!/usr/bin/perl
use ExtUtils::MakeMaker;

my $required_svn = '0.29.0';

WriteMakefile(
    AUTHOR              => 'Chia-liang Kao (clkao@clkao.org)',
    ABSTRACT            => 'Subversion repository web frontend',
    NAME                => 'SVN::Web',
    VERSION_FROM        => 'lib/SVN/Web.pm',
    DISTNAME            => 'SVN-Web',
    EXE_FILES		=> [ 'svnweb-install' ],
    PREREQ_PM           => {
        'SVN::Core'   => $required_svn,
        'Template'    => '0',
        'YAML'        => '0',
        'XML::RSS'    => '0',
        'Text::Diff'  => '0',
    },
    dist                => {
        COMPRESS        => 'gzip -9',
        SUFFIX          => '.gz',
    },
);

die "SVN::Core $required_svn must be manually installed"
    unless eval {require SVN::Core} && $SVN::Core::VERSION >= $required_svn;
