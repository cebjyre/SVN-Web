package SVN::Web::Revision;
use strict;
use Text::Diff;
use SVN::Core;
use SVN::Repos;
use SVN::Fs;
use SVN::Web::X;

=head1 NAME

SVN::Web::Revision - SVN::Web action to view a repository revision

=head1 SYNOPSIS

In F<config.yaml>

  actions:
    ...
    revision:
      class: SVN::Web::Revision
      opts:
        show_diff: 1 # or 0
    ...

=head1 DESCRIPTION

Shows information about a specific revision in a Subversion repository.

=head1 CONFIGURATION

The following configuration options may be specified in F<config.yaml>.

=over

=item show_diff

Boolean indicating whether or not a diff of every file that was changed
in the revision should be shown.

Defaults to 1.

=back

=head1 OPTIONS

=over 8

=item rev

The revision to show.  There is no default.

=item context

The number of lines of context to show around each change.  Uses the global
default if not set.

=back

=head1 TEMPLATE VARIABLES

=over 8

=item rev

The revision that is being shown.

=item youngest_rev

The repository's youngest revision.  This is useful when constructing
C<next revision> and C<previous revision> links.

=item date

The date on which the revision was committed.

=item author

The revision's author.

=item msg

The log message associated with this revision.

=item paths

A hash of hash refs.  Each key is a path name.  The value is a further hash ref
with the following keys.

=over 8

=item isdir

A boolean value, true if the given path is a directory.

=item diff

The HTML diff for this path (if it was modified in this revision).  The diff
is generated using L<Text::Diff::HTML>.

A diff is only generated if:

=over 3

=item a)

The file was modified.

=item b)

The file was copied from another file, and the new file and the old
file have different MD5 checksums.

=back

=item action

A single letter indicating the action that carried out on the path.  A
file was either added C<A>, modified C<M>, or deleted C<D>.

=item copyfrom

If the file was copied from another file then this is the path of the
source of the copy.

=item copyfromrev

If the file was copied from another file then this is the revision of
the file that it was copied form.

=back

=back

=head1 EXCEPTIONS

=over 4

=item (no revision)

The C<rev> parameter was not given.

=back

=cut

my %default_opts = (show_diff => 1);

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    %$self = @_;

    return $self;
}

sub _log {
    my ($self, $paths, $rev, $author, $date, $msg, $pool) = @_;
    $pool->default;
    my $data = {rev => $rev, author => $author,
		date => $date, msg => $msg};
    $data->{paths} = {map { $_ => {action => $paths->{$_}->action,
				   copyfrom => $paths->{$_}->copyfrom_path,
				   copyfromrev => $paths->{$_}->copyfrom_rev,
				  }} keys %$paths};
    my $root = $self->{repos}->fs->revision_root ($rev);
    my $oldroot = $self->{repos}->fs->revision_root ($rev-1);
    for (keys %{$data->{paths}}) {
	$data->{paths}{$_}{isdir} = 1
	    if $data->{paths}{$_}{action} eq 'D' ? $oldroot->is_dir ($_) : $root->is_dir ($_);
    }
    return $data;
}

sub run {
    my $self    = shift;

    $self->{opts} = { %default_opts, %{$self->{opts}} };

    my $pool    = SVN::Pool->new_default_sub;
    my $rev     = $self->{cgi}->param('rev') || 
      SVN::Web::X->throw(error => '(no revision)',
			 vars => []);

    $self->{repos}->get_logs (['/'], $rev, $rev, 1, 0,
			      sub { $self->{REV} = $self->_log(@_)});

    my $fs = $self->{repos}->fs();

    $self->make_diffs($rev) if $self->{opts}{show_diff};

    return {template => 'revision',
	    data => { rev => $rev,
		      youngest_rev => $fs->youngest_rev(),
		      %{$self->{REV}}}};
}

sub make_diffs {
    my $self = shift;
    my $rev  = shift;

    my $fs = $self->{repos}->fs();
    my $context = $self->{cgi}->param('context')
      || $self->{config}->{diff_context};

    # Generate the diffs for each file
    foreach my $path (keys %{$self->{REV}->{paths}}) {
      next if $self->{REV}->{paths}{$path}{isdir};

      if($self->{REV}->{paths}{$path}{action} eq 'M') {
	my $root1 = $fs->revision_root($rev);
	my $root2 = $fs->revision_root($rev - 1);

	my $kind;
	$kind = $root1->check_path($path);
	next if $kind == $SVN::Node::none;
	$kind = $root2->check_path($path);
	next if $kind == $SVN::Node::none;

	$self->{REV}->{paths}{$path}{diff} = Text::Diff::diff
	  ($root2->file_contents($path),
	   $root1->file_contents($path),
	   { STYLE => 'Text::Diff::HTML',
	     CONTEXT => $context, });

	next;
      }

      # If the file was added it may have been copied from another file.
      # Find out if it was, and if it was, do a diff between the two files.
      # If there were any changes then show them
      if(($self->{REV}->{paths}{$path}{action} eq 'A') and
	 defined $self->{REV}->{paths}{$path}{copyfrom}) {
	my $src = $self->{REV}->{paths}{$path}{copyfrom};

	my $root1 = $fs->revision_root($rev);
	my $root2 = $fs->revision_root($self->{REV}->{paths}{$path}{copyfromrev});

	# If the files have differing MD5s then do a diff
	if($root1->file_md5_checksum($path) ne $root2->file_md5_checksum($src)) {
	  $self->{REV}->{paths}{$path}{diff} = Text::Diff::diff
	    ($root2->file_contents($src),
	     $root1->file_contents($path),
	     { STYLE => 'Text::Diff::HTML' });
	}

	next;
      }
    } continue {
      if(defined $self->{REV}->{paths}{$path}{diff}) {
	$self->{REV}->{paths}{$path}{diff} =~ s/^  /<span class="diff-leader">  <\/span>/mg;
	$self->{REV}->{paths}{$path}{diff} =~ s/<span class="ctx">  /<span class="ctx">/mg;
	$self->{REV}->{paths}{$path}{diff} =~ s/<ins>\+ /<span class="ins"><span class="diff-leader">+ <\/span>/mg;
	$self->{REV}->{paths}{$path}{diff} =~ s/<del>- /<span class="del"><span class="diff-leader">- <\/span>/mg;
	$self->{REV}->{paths}{$path}{diff} =~ s/<\/ins>/<\/span>/mg;
	$self->{REV}->{paths}{$path}{diff} =~ s/<\/del>/<\/span>/mg;
	$self->{REV}->{paths}{$path}{diff} =~ s/^- /<span class="diff-leader">- <\/span>/mg;
	$self->{REV}->{paths}{$path}{diff} =~ s/^\+ /<span class="diff-leader">+ <\/span>/mg;
      }
    }
}

1;

