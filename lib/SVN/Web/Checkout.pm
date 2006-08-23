package SVN::Web::Checkout;

use strict;
use warnings;

use base 'SVN::Web::action';

use SVN::Core;
use SVN::Repos;
use SVN::Fs;
use SVN::Web::X;

our $VERSION = 0.49;

=head1 NAME

SVN::Web::Checkout - SVN::Web action to checkout a given file

=head1 SYNOPSIS

In F<config.yaml>

  actions:
    ...
    checkout:
      class: SVN::Web::Checkout
    ...

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

=item (path %1 is not a file in revision %2)

The given path is not a file in the given revision.

=back

=cut

sub run {
    my $self = shift;
    my $pool = SVN::Pool->new_default_sub;
    my $fs   = $self->{repos}->fs;
    my $rev  = $self->{cgi}->param('rev') || $fs->youngest_rev;
    my $root = $fs->revision_root($rev);
    my $path = $self->{path};

    if(!$root->is_file($path)) {
        SVN::Web::X->throw(
            error => '(path %1 is not a file in revision %2)',
            vars  => [$path, $rev]
        );
    }

    my $file = $root->file_contents($path);
    local $/;
    return {
        mimetype => $root->node_prop($path, 'svn:mime-type')
            || 'text/plain',
        body => <$file>
    };
}
1;
