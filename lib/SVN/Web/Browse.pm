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
    if ($self->{path} !~ m|/$|) {
	return 'internal server error';
    }
    my $root = $fs->revision_root ($rev);
    my $kind = $root->check_path ($self->{path});

    die "path does not exist" if $kind == $SVN::Node::none;

    die "not a directory in browse" unless $kind == $SVN::Node::dir;

    my $entries = [ map {{ name => $_->name,
			   kind => $_->kind,
			   isdir => ($_->kind == $SVN::Node::dir),
		       }} values %{$root->dir_entries ($self->{path})}];


    for (@$entries) {
	my $path = "$self->{path}$_->{name}";
	$_->{rev} = ($fs->revision_root ($rev)->node_history
		     ($path)->prev(0)->location)[1];
	$_->{size} = $_->{isdir} ? '' :
	    $root->file_length ($path);
	$_->{type} = $root->node_prop ($self->{path}.$_->{name},
				       'svn:mime-type') unless $_->{isdir};
	$_->{type} =~ s|/\w+|| if $_->{type};

    }

    # TODO: custom sorting
    @$entries = sort {($b->{isdir} <=> $a->{isdir}) || ($a->{name} cmp $b->{name})} @$entries;

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
[%|l(path, revision)%]browsing %1 (of revision %2)[%END%]
<a href="[% script %]/[% repos %]/log[% path %]">[%|l%](history of this directory)[%END%]</a>
[% IF branchto %]
<hr>
[%|l%]Branch to:[%END%]
[% FOR branchto %]
<a href="[% script %]/[% repos %]/browse[% dst %]">[% dst %]</a>:
<a href="[% script %]/[% repos %]/revision/?rev=[% dstrev %]">[% dstrev %]</a> [%|l(srcrev)%](from revision %1)[%END%]
[% END %]
[% END %]
[% IF branchfrom %]
<hr>
[%|l%]Branch from:[%END%]
[% FOR branchfrom %]
<a href="[% script %]/[% repos %]/browse[% src %]">[% src %]</a>:[% srcrev %] <a href="[% script %]/[% repos %]/revision/?rev=[% dstrev %]">[%|l(dstrev)%](to revision %1)[%END%]</a>
[% END %]
[% END %]
<table border=0 width="90%" class="entries">
<tr><td>[%|l%]name[%END%]</td><td>[%|l%]revision[%END%]</td><td>[%|l%]age[%END%]</td><td>[%|l%]size[%END%]</td></tr>
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

