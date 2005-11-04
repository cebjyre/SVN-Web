package SVN::Web::Checkout;
use strict;
use SVN::Core;
use SVN::Repos;
use SVN::Fs;

=head1 NAME

SVN::Web::Checkout - SVN::Web action to checkout a given file

=head1 SYNOPSIS

In F<config.yaml>

  actions:
    ...
    - checkout
    ...

  checkout_class: SVN::Web::Checkout

=head1 DESCRIPTION

Returns the contents of the given filename.  Uses the C<svn:mime-type>
property.

=head1 OPTIONS

=over 4

=item rev

The repository revision to checkout.  Defaults to the repository's youngest
revision.

=back

=head1 TEMPLATE VARIABLES

N/A

=head1 EXCEPTIONS

=over 4

=item C<not a file>

Thrown if the given path is not a file.

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
