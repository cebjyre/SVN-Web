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
    $self->{REV} = {rev => $rev, author => $author,
		     date => $date, msg => $msg};
    $self->{REV}{paths} = {map { $_ => {action => $paths->{$_}->action,
					 copyfrom => $paths->{$_}->copyfrom_path,
					 copyfromrev => $paths->{$_}->copyfrom_rev,
				       }} keys %$paths};
    my $root = $self->{repos}->fs->revision_root ($rev, $pool);
    for (keys %{$self->{REV}{paths}}) {
	$self->{REV}{paths}{$_}{isdir} = 1
	    if SVN::Fs::check_path ($root, $_) == $SVN::Core::node_dir;
    }
}

sub run {
    my $self = shift;
    my $pool = SVN::Pool->new_default_sub;
    my $rev = $self->{cgi}->param('rev') || die 'no revision';

    $self->{repos}->get_logs ([], $rev, $rev, 1, 0,
			      sub { $self->_log(@_)});
    return {template => 'revision',
	    data => { rev => $rev, %{$self->{REV}}}};
}

sub template {
    local $/;
    return {revision => <DATA>};
}

1;

__DATA__
revision [% rev %] - [% author || '(no author)' %] - [% date %]:<br />
[% FOREACH path IN paths %]
[% path.value.action %] -
[% IF path.value.isdir %]
<a href="[% script %]/[% repos %]/browse[% path.key %]?rev=[% rev %]">[% path.key %]</a>
[% ELSE %]
<a href="[% script %]/[% repos %]/log[% path.key %]#rev[% rev %]">[% path.key %]</a>
<a href="[% script %]/[% repos %]/checkout[% path.key %]?rev=[% rev %]">(checkout)</a>
[% END %]

<br />
[% END %]
