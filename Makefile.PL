#!/usr/bin/perl
use ExtUtils::MakeMaker;

WriteMakefile(
    AUTHOR              => 'Chia-liang Kao (clkao@clkao.org)',
    ABSTRACT            => 'Subversion repository web frontend',
    NAME                => 'SVN::Web',
    VERSION_FROM        => 'lib/SVN/Web.pm',
    DISTNAME            => 'SVN-Web',
    EXE_FILES		=> [ 'svnweb-install' ],
    PREREQ_PM           => {
        'SVN::Core'   => 0.28,
        'Template'    => 0,
        'YAML'        => 0,
    },
    dist                => {
        COMPRESS        => 'gzip -9',
        SUFFIX          => '.gz',
    },
);

