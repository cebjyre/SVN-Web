package SVN::Web::List;
use strict;
use File::Basename ();

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    %$self = @_;

    return $self;
}

sub run {
    my $self = shift;

    my @repos = SVN::Web::repos_list();
    return { template => 'list',
	     data => {
		      action => 'list',
		      nonav => 1,
                      repos => \@repos,
                      reposcount => scalar @repos}};
}

1;
