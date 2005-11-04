package SVN::Web::View;
use strict;
use SVN::Core;
use SVN::Repos;
use SVN::Fs;

=head1 NAME

SVN::Web::View - SVN::Web action to view a file in the repository

=head1 SYNOPSIS

In F<config.yaml>

  actions:
    ...
    - view
    ...

  view_class: SVN::Web::View

=head1 DESCRIPTION

Shows a specific revision of a file in the Subversion repository.  Includes
the commit information for that file.

=head1 OPTIONS

=over 8

=item rev

The revision of the file to show.  Defaults to the repository's
youngest revision.

If this is not an interesting revision for this file, the repository history
is searched to find the youngest interesting revision for this file that is
less than C<rev>.

=back

=head1 TEMPLATE VARIABLES

=over 8

=item rev

The revision that has been returned.  This is not necessarily the same
as the C<rev> option passed to the action.  If the C<rev> passed to the
action is not interesting (i.e., there were no changes to the file at that
revision) then the file's history is searched backwards to find the next
oldest interesting revision.

=item youngest_rev

The youngest interesting revision of the file.

=item mimetype

The file's MIME type, extracted from the file's C<svn:mime-type>
property.  If this is not set then C<text/plain> is used.

=item file

The contents of the file.

=item author

The revision's author.

=item date

The date the revision was committed.

=item msg

The revision's commit message.

=back

=head1 EXCEPTIONS

None.

=cut

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    %$self = @_;

    return $self;
}

sub _log {
    my ($self, $paths, $rev, $author, $date, $msg, $pool) = @_;
#    my ($self, $rev, $root, $paths, $props) = @_;
    return unless $rev > 0;
#    my ($author, $date, $message) = @{$props}{qw/svn:author svn:date svn:log/};

    my $data = { rev => $rev, author => $author,
		 date => $date, msg => $msg };

    my $root = $self->{repos}->fs()->revision_root($rev);

    $data->{paths} = 
      { map { $_ => { action => $paths->{$_}->action(),
		      copyfrom => $paths->{$_}->copyfrom_path(),
		      copyfromrev => $paths->{$_}->copyfrom_rev(),
		      isdir => $root->check_path($_) == $SVN::Node::dir,
		    }} keys %$paths};

    return $data;
}

sub run {
    my $self = shift;
    my $pool = SVN::Pool->new_default_sub;
    my $fs = $self->{repos}->fs;
    my $rev = $self->{cgi}->param('rev') || $fs->youngest_rev;
    my $root = $fs->revision_root($rev);

    # Start at $rev, and look backwards for the first interesting
    # revision number for this file.
    my $hist = $root->node_history($self->{path});
    $hist = $hist->prev(0);
    $rev = ($hist->location())[1];

    # If no rev param was passed in, then $rev is also the file's youngest
    # rev.  Which means we're at the file's head.  Otherwise, use the fs'
    # youngest rev as the youngest rev
    my $youngest_rev;
    if(! defined $self->{cgi}->param('rev')) {
      $youngest_rev = $rev;
    } else {
      $youngest_rev = $fs->youngest_rev();
    }

    # Get the log for this revision of the file
    $self->{repos}->get_logs([$self->{path}], $rev - 1, $rev, 1, 0,
                             sub { $self->{REV} = $self->_log(@_)});

    # Get the text for this revision of the file
    $root = $fs->revision_root($rev);
    my $file = $root->file_contents($self->{path});
    local $/;
    return {template => 'view',
	    data => { rev => $rev,
		      youngest_rev => $youngest_rev,
		      mimetype => $root->node_prop($self->{path},
						   'svn:mime-type') || 'text/plain',
		      file => <$file>,
		      %{$self->{REV}},
		    }};
}

1;
