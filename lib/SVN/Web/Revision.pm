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
    my $data = {rev => $rev, author => $author,
		date => $date, msg => $msg};
    $data->{paths} = {map { $_ => {action => $paths->{$_}->action,
				   copyfrom => $paths->{$_}->copyfrom_path,
				   copyfromrev => $paths->{$_}->copyfrom_rev,
				  }} keys %$paths};
    my $root = $self->{repos}->fs->revision_root ($rev, $pool);
    my $oldroot = $self->{repos}->fs->revision_root ($rev-1, $pool);
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

sub template {
    local $/;
    return {revision => <DATA>};
}

1;

__DATA__
revision [% rev %] - [% author || '(no author)' %] - [% date %]:<br />
<p>
[% msg | html | html_line_break %]
</p>
[% FOREACH path = paths %]
[% path.value.action %] -
[% IF path.value.isdir %]
<a href="[% script %]/[% repos %]/browse[% path.key %]/?rev=[% rev %]">[% path.key %]</a>
[% IF path.value.copyfrom %]
(from
<a href="[% script %]/[% repos %]/browse[% path.value.copyfrom %]/?rev=[% path.value.copyfromrev %]">[% path.value.copyfrom %]:[% path.value.copyfromrev %]</a>
)
[% END %]

[% ELSE %]
[% IF path.value.action == 'D' %]
[% path.key %]
[% ELSE %]
<a href="[% script %]/[% repos %]/log[% path.key %]#rev[% rev %]">[% path.key %]</a>
<a href="[% script %]/[% repos %]/checkout[% path.key %]?rev=[% rev %]">(checkout)</a>
[% END %]
[% IF path.value.copyfrom %]
(from
<a href="[% script %]/[% repos %]/log[% path.value.copyfrom %]#rev[% path.value.copyfromrev %]">[% path.value.copyfrom %]:[% path.value.copyfromrev %]</a>
)
[% END %]
[% END %]

<br />
[% END %]
