package SVN::Web::Branch;
@ISA = qw(SVN::Web);
use strict;

sub new {
    my $class = shift;
    return bless {}, $class;
}

sub branchto {
    my ($self, $path, $rev) = @_;
    return undef;
}

sub branchfrom {
    my ($self, $path, $rev) = @_;
    return undef;
}

sub branchpoints {
    my ($self, $path) = @_;
    return undef;
}

sub run {
}

1;
