package SVN::Web::View;

use strict;
use warnings;

use SVN::Core;
use SVN::Repos;
use SVN::Fs;

use base 'SVN::Web::action';

our $VERSION = 0.48;

=head1 NAME

SVN::Web::View - SVN::Web action to view a file in the repository

=head1 SYNOPSIS

In F<config.yaml>

  actions:
    ...
    view:
      class: SVN::Web::View
    ...

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

=item at_head

A boolean value, indicating whether the user is currently viewing the
HEAD of the file in the repository.

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

The date the revision was committed, formatted according to
L<SVN::Web/"Time and date formatting">.

=item msg

The revision's commit message.

=back

=head1 EXCEPTIONS

None.

=cut

sub _log {
    my($self, $paths, $rev, $author, $date, $msg, $pool) = @_;

    return unless $rev > 0;

    my $data = {
        rev    => $rev,
        author => $author,
        date   => $self->format_svn_timestamp($date),
        msg    => $msg
    };

    my $root    = $self->{repos}->fs()->revision_root($rev);
    my $subpool = SVN::Pool->new($pool);
    $data->{paths} = {
        map {
            $_ => {
                action      => $paths->{$_}->action(),
                copyfrom    => $paths->{$_}->copyfrom_path(),
                copyfromrev => $paths->{$_}->copyfrom_rev(),
                isdir => $root->check_path($_, $subpool) == $SVN::Node::dir,
                },
                $subpool->clear()
            } keys %$paths
    };

    return $data;
}

sub cache_key {
    my $self = shift;
    my $path = $self->{path};

    my(undef, undef, $act_rev, $head) = $self->get_revs();

    return "$act_rev:$head:$path";
}

sub run {
    my $self = shift;
    my $pool = SVN::Pool->new_default_sub;
    my $fs   = $self->{repos}->fs;
    my $path = $self->{path};

    my($exp_rev, $yng_rev, $act_rev, $head) = $self->get_revs();

    my $rev = $act_rev;

    my $root = $fs->revision_root($rev);

    # Get the log for this revision of the file
    $self->{repos}->get_logs([$path], $rev - 1, $rev, 1, 0,
        sub { $self->{REV} = $self->_log(@_) });

    # Get the text for this revision of the file
    $root = $fs->revision_root($rev);
    my $file = $root->file_contents($path);
    local $/;
    return {
        template => 'view',
        data     => {
            rev          => $act_rev,
            youngest_rev => $yng_rev,
	    at_head      => $head,
            mimetype     => $root->node_prop($path, 'svn:mime-type')
                || 'text/plain',
            file => <$file>,
            %{ $self->{REV} },
        }
    };
}

1;
