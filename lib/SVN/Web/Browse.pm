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
			   isdir => ($_->kind == $SVN::Core::node_dir)
		       }} values %{SVN::Fs::dir_entries ($root, $self->{path})}];

    for (@$entries) {
	$_->{rev} = SVN::Repos::revisions_changed
	    ($fs, $self->{path}.'/'.$_->{name}, 0, $rev, 0)->[0];
	$_->{size} = $_->{isdir} ? '' :
	    SVN::Fs::file_length ($root, $self->{path}.'/'.$_->{name})
    }

    return { template => 'browse',
	     data => { entries => $entries }};
}

sub template {
    local $/;
    return {browse => <DATA>};
}

1;
__DATA__
browsing [% path %]
<a href="[% script %]/[% repos %]/log[% path %]">(history of this directory)</a>
<table border=0 width="90%" class="entries">
<tr><td>name</td><td>revision</td><td>age</td><td>size</td></tr>
[% FOREACH entries %]
<tr>
<td class="name">
[% IF isdir %]
<a href="[% script %]/[% repos %]/browse[% path %][% name %]/">[% name %]</a>
[% ELSE %]
<a href="[% script %]/[% repos %]/log[% path %][% name %]">[% name %]</a>
[% END %]</td>
<td class="revision">[% rev %]</td>
<td class="age"></td>
<td class="size">[% size %]</td>
</tr>
[% END %]

</table>

