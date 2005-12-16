package SVN::Web::RSS;
@ISA = qw(SVN::Web::Log);
use strict;
use SVN::Web::Log;
use XML::RSS;

=head1 NAME

SVN::Web::RSS - SVN::Web action to generate an RSS feed

=head1 SYNOPSIS

In F<config.yaml>

  actions:
    ...
    rss:
      class: SVN::Web::RSS
    ...

=head1 DESCRIPTION

Generates an RSS feed of commits to a file or path in the Subversion 
repository.

=head1 OPTIONS

None.

=head1 TEMPLATE VARIABLES

None.  This action does not use a template.

=head1 EXCEPTIONS

None.

=cut

sub run {
    my $self = shift;
    my $data = eval { $self->SUPER::run(@_)->{data}; };

    if(! defined $data) {
      return "<p>RSS error -- this file does not exist in the repository.</p>";
    }

    my $rss = new XML::RSS (version => '1.0');
    my $url = "http://$ENV{HTTP_HOST}$self->{script}/$self->{reposname}";

    $rss->channel(title        => "subversion revisions of $self->{path}",
		  link         => "$url/log$self->{path}",
		  dc => {
			 date       => $self->{REVS}[0]{date},
			 creator    => 'SVN::Web',
			 publisher  => "adm\@$ENV{HTTP_HOST}",
			},
		  syn => {
			  updatePeriod     => "daily",
			  updateFrequency  => "1",
			  updateBase       => "1901-01-01T00:00+00:00",
			 },
		 );

    $_ && $rss->add_item
	( title       => "$_->{rev} - ".substr ((split("\n",$_->{msg}, 1))[0],
						0, 40),
	  link        => "$url/revision/?rev=$_->{rev}",
	  dc => { date		=> $_->{date},
		  creator	=> $_->{author},
		},
	  description => $_->{msg},
	) for @{$self->{REVS}}[0..10];
    return { mimetype => 'text/xml', body => $rss->as_string };
}

1;
