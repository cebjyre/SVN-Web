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

    die "not a file" unless SVN::Fs::check_path ($root, $self->{path})
	== $SVN::Core::node_file;

    my $file = SVN::Fs::file_contents ($root, $self->{path});
    local $/;
    return {mimetype => SVN::Fs::node_prop ($root, $self->{path},
					    'svn:mime-type') ||'text/plain',
	    body => <$file>};
}
1;
