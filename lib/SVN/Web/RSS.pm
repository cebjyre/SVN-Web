package SVN::Web::RSS;
@ISA = qw(SVN::Web::Log);
use strict;
use SVN::Web::Log;
use XML::RSS;

sub run {
    my $self = shift;
    my $data = $self->SUPER::run(@_)->{data};

    my $rss = new XML::RSS (version => '1.0');
    my $url = "http://$ENV{HTTP_HOST}$ENV{SCRIPT_NAME}/$self->{reposname}";

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
	( title       => "revision $_->{rev}",
	  link        => "$url/revision/?rev=$_->{rev}",
	  dc => { date		=> $_->{date},
		  creator	=> $_->{author},
		},
	  description => $_->{msg},
	) for @{$self->{REVS}}[0..10];
    return { mimetype => 'text/xml', body => $rss->as_string };
}

1;
