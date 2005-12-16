# -*- Mode: cperl; cperl-indent-level: 4 -*-

package SVN::Web::Diff;
use strict;
use Text::Diff;
use SVN::Core;
use SVN::Repos;
use SVN::Fs;
use SVN::Web::X;
use List::Util qw(max min);

eval 'use SVN::DiffEditor 0.09; require IO::String; 1' and my $has_svk = 1;

=head1 NAME

SVN::Web::Diff - SVN::Web action to show differences between file revisions

=head1 SYNOPSIS

In F<config.yaml>

  actions:
    ...
    diff:
      class: SVN::Web::Diff
    ...

=head1 DESCRIPTION

Returns the difference between two revisions of the same file.

=head1 OPTIONS

=over 8

=item rev1

The first revision of the file to compare.

=item rev2

The second revision of the file to compare.

=item revs

A list of two or more revisions.  If present, the smallest number in
the list is assigned to C<rev1> (overriding any given C<rev1> value) and the
largest number in the list is assigned to C<rev2> (overriding any given 
C<rev2> value).

In other words:

    ...?rev1=5;rev2=10

is equal to:

    ...?revs=10;revs=5

This supports the "diff between arbitrary revisions" functionality.

=item mime

The desired output format.  The default is C<html> for an HTML, styled diff
using L<Text::Diff::HTML>.  The other allowed value is C<text>, for a plain
text unified diff.

=item context

The number of lines of context to show around each change.  Uses the global
default if not set.

=back

=head1 TEMPLATE VARIABLES

=over 8

=item rev1

The first revision of the file to compare.  Corresponds with the C<rev1>
parameter, either set explicitly, or extracted from C<revs>.

=item rev2

The second revision of the file to compare.  Corresponds with the C<rev2>
parameter, either set explicitly, or extracted from C<revs>.

=back

In addition, if C<mime> is C<html> then raw HTML is returned for
immediate insertion in to the template.  If C<mime> is C<text> then
the template is bypassed and plain text is returned.

=head1 EXCEPTIONS

=over 4

=item (path %1 does not exist in revision %2)

The given path is not present in the repository at the given revision.

=item (directory diff requires svk)

Showing the difference between two directories needs the SVN::DiffEditor
module.

=item (two revisions must be provided)

No revisions were given to diff against.

=item (rev1 and rev2 must be different)

Either only one revision number was given, or several were given, but
they're the same number.

=back

=cut

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    %$self = @_;

    return $self;
}

sub run {
    my $self    = shift;
    my $pool    = SVN::Pool->new_default_sub;
    my $fs      = $self->{repos}->fs;
    my $rev1    = $self->{cgi}->param('rev1');
    my $rev2    = $self->{cgi}->param('rev2');
    my @revs    = $self->{cgi}->param('revs');

    if(@revs) {
	$rev1 = min(@revs);
	$rev2 = max(@revs);
    }

    SVN::Web::X->throw(error => '(two revisions must be provided)',
		       vars  => [])
	unless defined $rev1 and defined $rev2;

    SVN::Web::X->throw(error => '(rev1 and rev2 must be different)',
		       vars  => [])
	if @revs and @revs < 2;

    SVN::Web::X->throw(error => '(rev1 and rev2 must be different)',
		       vars  => [])
	if $rev1 == $rev2;

    my $mime    = $self->{cgi}->param('mime') || 'text/html';
    my $context = $self->{cgi}->param('context')
                  || $self->{config}->{diff_context};

    my $root1 = $fs->revision_root ($rev1);
    my $root2 = $fs->revision_root ($rev2);
    my $kind = $root1->check_path ($self->{path});

    if($kind == $SVN::Node::none) {
	SVN::Web::X->throw(error => '(path %1 does not exist in revision %2)',
			   vars => [$self->{path}, $rev1]);
    }

    $kind = $root2->check_path($self->{path});

    if($kind == $SVN::Node::none) {
	SVN::Web::X->throw(error => '(path %1 does not exist in revision %2)',
			   vars => [$self->{path}, $rev2]);
    }

    my $output;

    if ($kind == $SVN::Node::dir) {
	SVN::Web::X->throw(error => '(directory diff requires svk)',
			   vars => [])
	    unless $has_svk;

	my $path = $self->{path};
	$path =~ s|/$||;

	my $editor = SVN::DiffEditor->new
	    ( cb_basecontent => sub { my ($rpath) = @_;
				      my $base = $root1->file_contents ("$path/$rpath");
				      return $base;
				  },
	      cb_baseprop => sub { my ($rpath, $pname) = @_;
				   return $root1->node_prop ("$path/$rpath", $pname);
			       },
	      llabel => "revision $rev1",
	      rlabel => "revision $rev2",
	      lpath  => $path,
	      rpath  => $path,
	      fh     => IO::String->new(\$output)
	    );

	SVN::Repos::dir_delta ($root1, $path, '',
			       $root2, $path,
			       $editor, undef,
			       1, 1, 0, 1);
    }
    else {
        my $style;
	$mime eq 'text/html' and $style = 'Text::Diff::HTML';
	$mime eq 'text/plain' and $style = 'Unified';

	$output = Text::Diff::diff
	    ($root1->file_contents ($self->{path}),
	     $root2->file_contents ($self->{path}),
	     { STYLE => $style,
	       CONTEXT => $context, });
    }

    if($mime eq 'text/html') {
	$output =~ s/^  /<span class="diff-leader">  <\/span>/mg;
	$output =~ s/<span class="ctx">  /<span class="ctx"><span class="diff-leader">  <\/span>/mg;
	$output =~ s/<ins>\+ /<span class="ins"><span class="diff-leader">+ <\/span>/mg;
	$output =~ s/<del>- /<span class="del"><span class="diff-leader">- <\/span>/mg;
	$output =~ s/<\/ins>/<\/span>/mg;
	$output =~ s/<\/del>/<\/span>/mg;
	$output =~ s/^- /<span class="diff-leader">- <\/span>/mg;
	$output =~ s/^\+ /<span class="diff-leader">+ <\/span>/mg;

	return { template => 'diff',
		 data => { rev1 => $rev1,
			   rev2 => $rev2,
			   body => $output }};
    } else {
	return { mimetype => $mime,
		 body => $output };
    }
}

1;
