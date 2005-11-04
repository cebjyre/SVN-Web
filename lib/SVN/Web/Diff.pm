# -*- Mode: cperl; cperl-indent-level: 4 -*-

package SVN::Web::Diff;
use strict;
use Text::Diff;
use SVN::Core;
use SVN::Repos;
use SVN::Fs;

eval 'use SVN::DiffEditor 0.09; require IO::String; 1' and my $has_svk = 1;

=head1 NAME

SVN::Web::Diff - SVN::Web action to show differences between file revisions

=head1 SYNOPSIS

In F<config.yaml>

  actions:
    ...
    - diff
    ...

  diff_class: SVN::Web::Diff

=head1 DESCRIPTION

Returns the difference between two revisions of the same file.

=head1 OPTIONS

=over 8

=item rev1

The first revision of the file to compare.

=item rev2

The second revision of the file to compare.

=item mime

The desired output format.  The default is C<html> for an HTML, styled diff
using L<Text::Diff::HTML>.  The other allowed value is C<text>, for a plain
text unified diff.

=item context

The number of lines of context to show around each change.  Uses the global
default if not set.

=back

=head1 TEMPLATE VARIABLES

None.  If C<mime> is C<html> then raw HTML is returned for immediate insertion
in to the template.  If C<mime> is C<text> then the template is bypassed and
plain text is returned.

=head1 EXCEPTIONS

=over 4

=item C<path does not exist>

The file does not exist in C<rev1> of the repository.

=item C<directory diff requires svk>

Showing the difference between two directories needs the SVN::DiffEditor
module.

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
    my $mime    = $self->{cgi}->param('mime') || 'text/html';
    my $context = $self->{cgi}->param('context')
                  || $self->{config}->{diff_context};

    my $root1 = $fs->revision_root ($rev1);
    my $root2 = $fs->revision_root ($rev2);
    my $kind = $root1->check_path ($self->{path});

    die "path does not exist" if $kind == $SVN::Node::none;

    my $output;

    if ($kind == $SVN::Node::dir) {
	die "directory diff requires svk"
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
		 data => { body => $output }};
    } else {
	return { mimetype => $mime,
		 body => $output };
    }
}

1;
