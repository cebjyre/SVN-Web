package SVN::Web::Log;
use strict;
use SVN::Core;
use SVN::Repos;
use SVN::Fs;

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    %$self = @_;

    return $self;
}

sub _log {
    my ($self, $paths, $rev, $author, $date, $msg, $pool) = @_;
    return unless $rev > 0;
    push @{$self->{REVS}}, {rev => $rev, author => $author,
			    date => $date, msg => $msg};
}

sub run {
    my $self = shift;
    my $pool = SVN::Pool->new_default_sub;
    my $fs = $self->{repos}->fs;

    $self->{repos}->get_logs ([$self->{path}], $fs->youngest_rev, 0, 0, 0,
			      sub { $self->_log(@_)});
    return {template => 'log',
	    data => { isdir => ($fs->revision_root ($fs->youngest_rev)->
				is_dir($self->{path})),
		      revs => $self->{REVS},
		      branchpoints => $self->{branch}->branchpoints ($self->{path}),
		    }};
}

1;
