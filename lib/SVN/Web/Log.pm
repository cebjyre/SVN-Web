package SVN::Web::Log;
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

sub _log {
    my ($self, $paths, $rev, $author, $date, $msg, $pool) = @_;
    return unless $rev > 0;
    push @{$self->{REVS}}, {rev => $rev, author => $author,
			    date => $date, msg => $msg};
}

sub run {
    my $self = shift;
    my $pool = SVN::Pool->new_default_sub;
    my $fs = $self->{repos}->fs;

    $self->{repos}->get_logs ([$self->{path}], $fs->youngest_rev, 0, 0, 0,
			      sub { $self->_log(@_)});
    return {template => 'log',
	    data => { isdir => ($fs->revision_root ($fs->youngest_rev)->
				is_dir($self->{path})),
		      revs => $self->{REVS},
		      branchpoints => $self->{branch}->branchpoints ($self->{path}),
		    }};
}

sub template {
    local $/;
    return {log => <DATA>};
}

1;

__DATA__
[%|l(path)%]history for path %1[%END%] <a href="[% script %]/[% repos %]/rss[% path %]">[%|l%](track)[%END%]</a>
[% IF isdir %]
<a href="[% script %]/[% repos %]/browse[% path %]">[%|l%](browse)[%END%]</a>
[% END %]
[% FOREACH revs %]
<hr />
<a name="rev[% rev %]"/>
<a href="[% script %]/[% repos %]/revision/?rev=[% rev %]">[%|l(rev)%]revision %1[%END%]</a>
[% IF isdir %]
<a href="[% script %]/[% repos %]/browse[% path %]?rev=[% rev %]">[%|l%](browse)[%END%]</a>
[% ELSE %]
<a href="[% script %]/[% repos %]/checkout[% path %]?rev=[% rev %]">[%|l%](checkout)[%END%]</a>
[% END %]
 - [% author %] - [% date %]<br/>

[% WHILE branchpoints.size && branchpoints.first.srcrev >= rev %]
[% b = branchpoints.shift %]
branchpoint for
[% IF isdir %]
<a href="[% script %]/[% repos %]/browse[% b.dst %]?rev=[% b.dstrev %]">[% b.dst %]</a>:[% b.dstrev %]<br/>
[% ELSE %]
<a href="[% script %]/[% repos %]/log[% b.dst %]#rev[% b.dstrev %]">[% b.dst %]</a>:[% b.dstrev %]<br/>
[% END %]

[% END %]
[% UNLESS isdir || loop.count == loop.size%]
[% prev = loop.count %]
<a href="[% script %]/[% repos %]/diff[% path %]?rev1=[% revs.$prev.rev %]&rev2=[% rev %]">[%|l%](diff with previous)[%END%]</a><br/>
[% END %]
[% msg | html | html_line_break %]
[% END %]
