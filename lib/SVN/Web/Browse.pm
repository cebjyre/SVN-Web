package SVN::Web::Browse;
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

sub run {
    my $self = shift;
    my $pool = SVN::Pool->new_default_sub;
    my $fs = $self->{repos}->fs;
    my $rev = $self->{cgi}->param('rev') || $fs->youngest_rev;
    my $root = $fs->revision_root ($rev);

    my $kind = SVN::Fs::check_path ($root, $self->{path});

    die "path does not exist" if $kind == $SVN::Core::node_none;

    die "not a directory in browse" unless $kind == $SVN::Core::node_dir;

    my $entries = [ map {{ name => $_->name,
			   kind => $_->kind,
			   isdir => ($_->kind == $SVN::Core::node_dir),
		       }} values %{SVN::Fs::dir_entries ($root, $self->{path})}];

    for (@$entries) {
	$_->{rev} = SVN::Repos::revisions_changed
	    ($fs, $self->{path}.'/'.$_->{name}, 0, $rev, 0)->[0];
	$_->{size} = $_->{isdir} ? '' :
	    SVN::Fs::file_length ($root, $self->{path}.'/'.$_->{name});
	$_->{type} = SVN::Fs::node_prop ($root, $self->{path}.$_->{name},
					  'svn:mime-type') unless $_->{isdir};
	$_->{type} =~ s|/\w+|| if $_->{type};

    }

    return { template => 'browse',
	     data => { entries => $entries, revision => $rev,
		       branchto => $self->{branch}->branchto ($self->{path}, $rev),
		       branchfrom => $self->{branch}->branchfrom ($self->{path}, $rev),
		     }};
}

sub template {
    local $/;
    return {browse => <DATA>};
}

1;
__DATA__
browsing [% path %] (of revision [% revision %])
<a href="[% script %]/[% repos %]/log[% path %]">(history of this directory)</a>
[% IF branchto %]
<hr>
Branch to:
[% FOR branchto %]
<a href="[% script %]/[% repos %]/browse[% dst %]">[% dst %]</a>:
<a href="[% script %]/[% repos %]/revision/?rev=[% dstrev %]">[% dstrev %]</a> (from revision [% srcrev %])
[% END %]
[% END %]
[% IF branchfrom %]
<hr>
Branch from:
[% FOR branchfrom %]
<a href="[% script %]/[% repos %]/browse[% src %]">[% src %]</a>:[% srcrev %] (to <a href="[% script %]/[% repos %]/revision/?rev=[% dstrev %]">revision [% dstrev %]</a>)
[% END %]
[% END %]
<table border=0 width="90%" class="entries">
<tr><td>name</td><td>revision</td><td>age</td><td>size</td></tr>
[% FOREACH entries %]
<tr>
<td class="name">
[% IF isdir %]
<img border="0" src="/icons/dir.gif" />
<a href="[% script %]/[% repos %]/browse[% path %][% name %]/">[% name %]</a>
[% ELSE %]
<a href="[% script %]/[% repos %]/checkout[% path %][% name %]?rev=[% rev %]"><img border="0" src="/icons/[% type || 'text' %].gif" /></a>
<a href="[% script %]/[% repos %]/log[% path %][% name %]">[% name %]</a>
[% END %]</td>
<td class="revision">[% rev %]</td>
<td class="age"></td>
<td class="size">[% size %]</td>
</tr>
[% END %]

</table>

