=head1 NAME

SVN::Web::Test - automated web testing for SVN::Web

=head1 DESCRIPTION


=cut

package SVN::Web::Test;
use strict;
use Storable qw(freeze thaw);
use base qw(Test::WWW::Mechanize);

# CGI.pm does not reinitialise itself from the environment when multiple
# objects are created.  This is a problem when testing, as the tests pass
# in different QUERY_STRING variables.  C<< use CGI >> and increment
# $CGI::PERLEX, which is an internal CGI.pm flag that turns off this
# behaviour.
use CGI;
$CGI::PERLEX++;

my ($host, $script) = @_;

sub import {
    my %repos;
    (undef, $host, $script, %repos) = @_;
    my $config = {qw{
branch_class              SVN::Web::Branch
browse_class              SVN::Web::Browse
checkout_class            SVN::Web::Checkout
diff_class                SVN::Web::Diff
list_class                SVN::Web::List
log_class                 SVN::Web::Log
revision_class            SVN::Web::Revision
rss_class                 SVN::Web::RSS
template_class            SVN::Web::Template;
view_class		  SVN::Web::View
cgi_class		  CGI
templatedir lib/SVN/Web/Template/trac}};

    $config->{repos} = \%repos;
    SVN::Web::set_config ($config);
}

sub send_request {
    my ($self, $request) = @_;

    my $buf = '';
    my $uri = $request->uri;
    {
	open my $outfh, '>', \$buf;
	local *STDOUT = $outfh;
	$uri =~ s/^$host$script//;
	$uri =~ s/\?(.*)$//g;
	local $ENV{QUERY_STRING} = $1 || '';
	local $ENV{PATH_INFO} = $uri;
	local $ENV{SCRIPT_NAME} = $script;
	local $ENV{HTTP_HOST} = $host;
	local $ENV{REQUEST_METHOD} = 'GET';
	SVN::Web::run_cgi;
    }

    my $response = HTTP::Response->new (200);
    # XXX: HTTP::Message::parse is unhappy with content having :
    $buf =~ s/^(.*\r?\n)\r?\n//;
    my $header = $1;
    my $msg = HTTP::Message->parse($header);
    $response->header (%{$msg->headers});
    $response->content ($buf);
    $response->request($request);
    $response->header("Client-Date" => HTTP::Date::time2str(time));

    return $response;
}

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

1;
