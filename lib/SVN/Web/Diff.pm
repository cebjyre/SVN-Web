package SVN::Web::Diff;
use strict;
use Text::Diff;
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
    my $rev1 = $self->{cgi}->param('rev1');
    my $rev2 = $self->{cgi}->param('rev2');

    my $root1 = $fs->revision_root ($rev1);
    my $kind = $root1->check_path ($self->{path});

    die "path does not exist" if $kind == $SVN::Node::none;
    # TODO: a diff editor using SVN::Editor::Simple
    die "directory diff not implemented yet" if $kind == $SVN::Node::dir;

    my $root2 = $fs->revision_root ($rev2);

    # TODO: different type of presentation, download, etc
    return { mimetype => 'text/plain',
	     body => Text::Diff::diff
	     ($root1->file_contents ($self->{path}),
	      $root2->file_contents ($self->{path}),
	      { STYLE => "Unified" })
	     };
}

1;
