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
	     data => {nonav => 1,
                      repos => \@repos,
                      reposcount => scalar @repos}};
}

sub template {
    local $/;
    return {list => <DATA>};
}

1;

__DATA__
[% IF reposcount %]
<p>
Please select a repository to browse:
</p>

<ul>
  [% FOREACH r = repos %]
 <li><a href="[% script %]/[% r %]">[% r %]</a></li>
  [% END %]
</ul>
[% ELSE %]
<p>
No repositories are available for browsing.
</p>
[% END %]
