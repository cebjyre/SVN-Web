package SVN::Web::Checkout;
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

    die "not a file" unless $root->is_file ($self->{path});

    my $file = $root->file_contents ($self->{path});
    local $/;
    return {mimetype => $root->node_prop ($self->{path},
					  'svn:mime-type') ||'text/plain',
	    body => <$file>};
}
1;
