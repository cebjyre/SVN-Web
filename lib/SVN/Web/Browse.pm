package SVN::Web::Browse;
use strict;
use SVN::Core;
use SVN::Repos;
use SVN::Fs;
use SVN::Web::X;

use Time::Local;

=head1 NAME

SVN::Web::Browse - SVN::Web action to browse a Subversion repository

=head1 SYNOPSIS

In F<config.yaml>

  actions:
    ...
    browse:
      class: SVN::Web::Browse
    ...

=head1 DESCRIPTION

Returns a file/directory listing for the given repository path.

=head1 OPTIONS

=over 4

=item rev

The repository revision to show.  Defaults to the repository's youngest
revision.

=back

=head1 TEMPLATE VARIABLES

=over 4

=item entries

A list of hash refs, one for each file and directory entry in the browsed
path.  The list is ordered with directories first, then files, sorted
alphabetically.

Each hash ref has the following keys.

=over 8

=item path

The entry's full path.

=item rev

The entry's most recent interesting revision.

=item size

The entry's size, in bytes.  The empty string C<''> for directories.

=item type

The entry's C<svn:mime-type> property.  Not set for directories.

=item author

The userid that committed the most recent interesting revision for this
entry.

=item date

The date of the entry's most recent interesting revision.

=item msg

The log message for the entry's most recent interesting revision.

=back

=item rev

The repository revision that is being browsed.  Will be the same as the
C<rev> parameter given to the action, unless that parameter was not set,
in which case it will be the repository's youngest revision.

=item youngest_rev

The repository's youngest revision.

=back

=head1 EXCEPTIONS

=over 4

=item (path %1 does not exist in revision %2)

The given path is not present in the repository at the given revision.

=back

=cut

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    %$self = @_;

    return $self;
}

sub run {
    my $self = shift;
    my $fs = $self->{repos}->fs;
    my $rev = $self->{cgi}->param('rev') || $fs->youngest_rev;

    if ($self->{path} !~ m|/$|) {
        print $self->{cgi}->redirect(-uri => $self->{cgi}->self_url() . '/');
	return;
    }
    my $path = $self->{path};
    $path =~ s|/$|| unless $path eq '/';
    my $root = $fs->revision_root ($rev);
    my $kind = $root->check_path ($path);

    if($kind == $SVN::Node::none) {
      SVN::Web::X->throw(error => '(path %1 does not exist in revision %2)',
			 vars => [$path, $rev]);
    }

    die "not a directory in browse" unless $kind == $SVN::Node::dir;

    my $entries = [ map {{ name => $_->name,
			   kind => $_->kind,
			   isdir => ($_->kind == $SVN::Node::dir),
		       }} values %{$root->dir_entries ($self->{path})}];

    my $spool = SVN::Pool->new_default;
    for (@$entries) {
	my $path = "$self->{path}$_->{name}";
	$_->{rev} = ($fs->revision_root ($rev)->node_history
		     ($path)->prev(0)->location)[1];
	$_->{size} = $_->{isdir} ? '' :
	    $root->file_length ($path);
	$_->{type} = $root->node_prop ($self->{path}.$_->{name},
				       'svn:mime-type') unless $_->{isdir};
	$_->{type} =~ s|/\w+|| if $_->{type};

	$_->{author} = $fs->revision_prop($_->{rev}, 'svn:author');
	$_->{date_modified} = $fs->revision_prop($_->{rev}, 'svn:date');
	my($y, $m, $d, $h, $M, $s)
	  = $_->{date_modified} =~ /^(....)-(..)-(..)T(..):(..):(..)/;
	my $time = timegm($s, $M, $h, $d, $m - 1, $y);
	$_->{age} = time() - $time;
	$_->{msg} = $fs->revision_prop($_->{rev}, 'svn:log');

	$spool->clear;
    }

    # TODO: custom sorting
    @$entries = sort {($b->{isdir} <=> $a->{isdir}) || ($a->{name} cmp $b->{name})} @$entries;

    my @props = ();
    foreach my $prop_name (qw(svn:externals)) {
      my $prop_value = $root->node_prop($path, $prop_name);
      if(defined $prop_value) {
	$prop_value =~ s/\s*\n$//ms;
	push @props, { name  => $prop_name,
		       value => $prop_value,
		       };
      }
    }

    return { template => 'browse',
	     data => { entries => $entries,
		       rev => $rev,
		       youngest_rev => $fs->youngest_rev(),
		       props => \@props,
		     }};
}

1;
