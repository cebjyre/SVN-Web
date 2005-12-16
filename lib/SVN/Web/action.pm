package SVN::Web::action;

=head1 NAME

SVN::Web::action - documentation for writing new SVN::Web actions

=head1 DESCRIPTION

This file contains no code.  It provides documentation for writing new
SVN::Web actions.

=head1 OVERVIEW

SVN::Web actions are Perl modules loaded by SVN::Web.  They are
expected to retrieve some information from the Subversion repository,
and return that information ready for the user's browser, optionally
via formatting by a Template::Toolkit template.

Action names are listed in the SVN::Web configuration file,
F<config.yaml>, in the C<actions:> clause.  Each entry specifies the
class that implements the action, and any options that are set globally
for that action.

  actions:
    ...
    new_action:
      class: Class::That::Implements::Action
      opts:
        option1: value1
        option2: value2
    ...

Each action is a class that must implement at least two methods,
C<new()> and C<run()>.

=head1 METHODS

=head2 new()

This is a traditional Perl constructor.  The following boilerplate
code will suffice.

  sub new {
      my $class = shift;
      my $self = bless {}, $class;
      %$self = @_;

      return $self;
  }

=head2 run()

The C<run> method is where the action carries out its work.

=head3 Parameters

The method is passed a single parameter, the standard C<$self> hash
ref.  This contains numerous useful keys.

=over 4

=item $self->{opts}

The options for this action from F<config.yaml>.  Using the example from the
L<OVERVIEW>, this would lead to:

  $self->{opts} = { 'option1' => 'value1',
                    'option2' => 'value2',
                  };

=item $self->{cgi}

An instance of a CGI object corresponding to the current request.  This is
normally an object from either the L<CGI> or L<CGI::Fast> modules, although
it is possible to specify another class with the C<cgi_class> directive in
F<config.yaml>.

You can use this object to retrieve the values of any parameters passed to
your action.

For example, if your action takes a C<rev> parameter, indicating the
repository revision to work on;

  my $rev = $self->{cgi}->param('rev');

=item $self->{path}

The path in the repository that was passed to the action.

=item $self->{navpaths}

A reference to an array of path components, one for each directory
(and possible final file) in $self->{path}.  Equivalent to S<C<< [
split('/', $self->{path}) ] >>>

=item $self->{config}

The config hash, as read by L<YAML> from F<config.yaml>.  Directives
from the config file are second level hash keys.  For example, the
C<actions> configuration directive contains a list of valid actions.

  my @valid_actions = @{ $self->{config}->{actions} };

=item $self->{reposname}

The symbolic name of the repository being accessed.

=item $self->{repos}

A instance of the L<SVN::Repos> class, corresponding to the repository
being accessed.  This repository has already been opened.

For example, to find the youngest (i.e., most recent) revision of the
repository;

  my $yr = $self->{repos}->fs()->youngest_rev();

=item $self->{action}

The action that has been requested.  It's possible for multiple action
names to be mapped to a single class in the config file, and this lets
you differentiate between them.

=item $self->{script}

The URL for the currently running script.

=back

=head3 Return value

The return value from C<run()> determines how the data from the action is
displayed.

=head4 Using a template

If C<run()> wants a template to be displayed containing formatted data
from the method then the hash ref should contain two keys.

=over 4

=item template

This is the name of the template to return.  By convention the template and
the action share the same name.

=item data

This is a hash ref.  The hash keys become variables of the same name in the
template.

=back

The character set and MIME type can also be specified, in the
C<charset> and C<mimetype> keys.  If these values are not specified
then they default to C<UTF-8> and C<text/html> respectively.

E.g., for an action named C<my_action>, using a template called
C<my_action> that looks like this:

  <p>The youngest interesting revision of [% file %] is [% rev %].</p>

then this code would be appropriate.

  # $rev and $file set earlier in the method
  return { template => 'my_action',
           data     => { rev  => $rev,
                         file => $file,
                       },
         };

=head4 Returning data with optional charset and MIME type

If the action does not want to use a template and just wants to return
data, but retain control of the character set and MIME type, C<run()>
should return a hash ref.  This should contain a key called C<body>,
the value of which will be sent directly to the browser.

The character set and MIME type can also be specified, in the
C<charset> and C<mimetype> keys.  If these values are not specified
then they default to C<UTF-8> and C<text/html> respectively.

E.g., for an action that generates a PNG image from data in the
repository (perhaps using L<SVN::Churn>);

  # $png contains the PNG image, created earlier in the method
  return { mimetype => 'image/png',
           body     => $png
         };

=head4 Returning HTML with default charset and MIME type

If the action just wants to return HTML in UTF-8, it can return a single
scalar that contains the HTML to be sent to the browser.

  return "<p>hello, world</p>";

=head1 ERRORS AND EXCEPTIONS

If your action needs to fail for some reason -- perhaps the parameters
passed to it are incorrect, or the user lacks the necessary permissions,
then throw an exception.

Exceptions, along with examples, are described in L<SVN::Web::X>.

=cut

1;
