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
	    data => { isdir => (SVN::Fs::check_path
				($fs->revision_root ($fs->youngest_rev),
				 $self->{path}) == $SVN::Core::node_dir),
		      revs => $self->{REVS}}};
}

sub template {
    local $/;
    return {log => <DATA>};
}

1;

__DATA__
history for path [% path %]
[% FOREACH revs %]
<hr />
<a name="rev[% rev %]"/>
<a href="[% script %]/[% repos %]/revision/?rev=[% rev %]">revision [% rev %]</a>
[% UNLESS isdir %]
<a href="[% script %]/[% repos %]/checkout[% path %]?rev=[% rev %]">(checkout)</a>
[% END %]
 - [% author %] - [% date %]<br>
[% msg %]
[% END %]
