package SVN::Web::Revision;
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
    $pool->default;
    my $data = {rev => $rev, author => $author,
		date => $date, msg => $msg};
    $data->{paths} = {map { $_ => {action => $paths->{$_}->action,
				   copyfrom => $paths->{$_}->copyfrom_path,
				   copyfromrev => $paths->{$_}->copyfrom_rev,
				  }} keys %$paths};
    my $root = $self->{repos}->fs->revision_root ($rev);
    my $oldroot = $self->{repos}->fs->revision_root ($rev-1);
    for (keys %{$data->{paths}}) {
	$data->{paths}{$_}{isdir} = 1
	    if $data->{paths}{$_}{action} eq 'D' ? $oldroot->is_dir ($_) : $root->is_dir ($_);
    }
    return $data;
}

sub run {
    my $self = shift;
    my $pool = SVN::Pool->new_default_sub;
    my $rev = $self->{cgi}->param('rev') || die 'no revision';

    $self->{repos}->get_logs ([], $rev, $rev, 1, 0,
			      sub { $self->{REV} = $self->_log(@_)});
    return {template => 'revision',
	    data => { rev => $rev, %{$self->{REV}}}};
}

1;

