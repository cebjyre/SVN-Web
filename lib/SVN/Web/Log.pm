package SVN::Web::Log;

use strict;
use warnings;

use SVN::Core;
use SVN::Repos;
use SVN::Fs;

use base 'SVN::Web::action';

our $VERSION = 0.48;

=head1 NAME

SVN::Web::Log - SVN::Web action to show log messages for a repository path

=head1 SYNOPSIS

In F<config.yaml>

  actions:
    ...
    log:
      class: SVN::Web::Log
    ...

=head1 DESCRIPTION

Shows log messages (in reverse order) for interesting revisions of a given
file or directory in the repository.

=head1 OPTIONS

=over 8

=item limit

The number of log entries to retrieve.  The default is 20.

=item rev

The repository revision to start with.  The default is the repository's
youngest revision.

=back

=head1 TEMPLATE VARIABLES

=over 8

=item at_head

A boolean value, true if the log starts with the most recent revision.

=item isdir

A boolean value, true if the given path is a directory.

=item rev

The repository revision that the log starts with.

=item revs

A list of hashes.  Each entry corresponds to a particular repository revision,
and has the following keys.

=over 8

=item rev

The repository revision this entry is for.

=item youngest_rev

The repository's youngest revision.

=item author

The author of this change.

=item date

The date of this change, formatted according to
L<SVN::Web/"Time and date formatting">.

=item msg

The log message for this change.

=item paths

A list of hashes containing information about the paths that were
changed with this commit.  Each hash key is the path name that was
modified with this commit.  Each key is a hash ref of extra
information about the change to this path.  These hash refs have the
following keys.

=over 8

=item action

A single letter indicating the action that was carried out on the
path.  A file was either added C<A>, modified C<M>, or deleted C<D>.

=item copyfrom

If the file was copied from another file then this is the path of the
source of the copy.

=item copyfromrev

If the file was copied from another file then this is the revision of
the file that it was copied from.

=back

=back

=item limit

The maximum number of log entries that were retrieved.  This is not
necessarily the same as the total number of log entries that were
retrieved.

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

    my $root = $self->{repos}->fs()->revision_root($rev);

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

    foreach my $path (keys %{ $data->{paths} }) {
        if(defined $data->{paths}{$path}{copyfrom}) {
            if($root->check_path($data->{paths}{$path}{copyfrom})
                == $SVN::Node::dir) {
                if($data->{paths}{$path}{copyfrom} !~ m|/$|) {
                    $data->{paths}{$path}{copyfrom} .= '/';
                }
            }
        }
    }

    push @{ $self->{REVS} }, $data;
}

# XXX: stolen from svk::util
sub traverse_history {
    my %args = @_;

    my $old_pool = SVN::Pool->new;
    my $new_pool = SVN::Pool->new;
    my $spool    = SVN::Pool->new_default;

    my $hist = $args{root}->node_history($args{path}, $old_pool);
    my $rv;

    while($hist = $hist->prev(($args{cross} || 0), $new_pool)) {
        $rv = $args{callback}->($hist->location($new_pool));
        last if !$rv;
        $old_pool->clear;
        $spool->clear;
        ($old_pool, $new_pool) = ($new_pool, $old_pool);
    }

    return $rv;
}

sub cache_key {
    my $self = shift;
    my $path  = $self->{path};
    my $fs    = $self->{repos}->fs();

    my(undef, undef, $act_rev, $head) = $self->get_revs();

    my $root  = $fs->revision_root($act_rev);
    my $kind  = $root->check_path($path);

    return if $kind == $SVN::Node::dir and $path !~ m{/$};

    my $limit = $self->{cgi}->param('limit') || 20;

    return "$act_rev:$limit:$head:$path";
}

sub run {
    my $self  = shift;
    my $pool  = SVN::Pool->new_default_sub;
    my $fs    = $self->{repos}->fs;
    my $limit = $self->{cgi}->param('limit') || 20;
    my $rev   = $self->{cgi}->param('rev') || $fs->youngest_rev();
    my $root  = $fs->revision_root($rev);
    my $path  = $self->{path};

    my(undef, undef, undef, $head) = $self->get_revs();

    my $kind = $root->check_path($path);
    if($kind == $SVN::Node::dir) {
        if($path !~ m|/$|) {
            print $self->{cgi}
                ->redirect(-uri => $self->{cgi}->self_url() . '/');
        }
    }

    my $endrev = 0;
    if($limit) {
        my $left = $limit;
        traverse_history(
            root     => $root,
            path     => $path,
            cross    => 0,
            callback => sub { $endrev = $_[1]; return --$left }
        );
    }

    #    SVK::Command::Log::do_log (repos => $self->{repos}, limit => $limit,
    #			       path => $self->{path},
    #			       fromrev => $fs->youngest_rev, torev => -1,
    #			       cb_log => sub {$self->_log(@_)});

    $self->{repos}->get_logs([$path], $rev, $endrev, 1, 0,
        sub { $self->_log(@_) });
    return {
        template => 'log',
        data     => {
            isdir        => ($root->is_dir($path)),
            revs         => $self->{REVS},
            limit        => $limit,
            rev          => $rev,
            youngest_rev => $fs->youngest_rev(),
            at_head      => $head,
        }
    };
}

1;
