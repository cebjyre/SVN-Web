package SVN::Web::Branch::YAML;
@ISA = qw(SVN::Web::Revision);
use strict;
use SVN::Web::Revision;
use SVN::Core;
use SVN::Repos;
use SVN::Fs;
use YAML;

sub check_branch {
    my ($self, $data) = @_;

    while (my ($path, $info) = each %{$data->{paths}}) {
	next unless $info->{copyfrom};
	if ($info->{copyfrom}) {
	    my $revinfo = [$info->{copyfromrev}, $data->{rev}, $info->{isdir}];
	    push @{$self->{BRANCHINFO}{dst}{$path}{$info->{copyfrom}}},
		$revinfo;

	    push @{$self->{BRANCHINFO}{src}{$info->{copyfrom}}{$path}},
		$revinfo;
	}
    }
}

sub new {
    my $class = shift;
    my $self = $class->SUPER::new (@_);
    my $pool = SVN::Pool->new_default_sub;
    my $temp = ($self->{tmpdir} || '.');
    my $file = "$temp/branch-$self->{reposname}.yaml";
    $self->{BRANCHINFO} = YAML::LoadFile ($file) if -e $file;

    # XXX: lock this

    $self->{repos}->get_logs ([], $self->{BRANCHINFO}{youngest}+1,
			      $self->{repos}->fs->youngest_rev, 1, 0,
			      sub { $self->check_branch ($self->_log(@_))})
	if $self->{repos}->fs->youngest_rev > $self->{BRANCHINFO}{youngest};

    $self->{BRANCHINFO}{youngest} = $self->{repos}->fs->youngest_rev;

    YAML::DumpFile ($file, $self->{BRANCHINFO});

    return $self;
}

sub branchto {
    my ($self, $path, $rev) = @_;
    my @branches = grep { "$_/" eq substr ($path, 0, length($_)+1) }
	keys %{$self->{BRANCHINFO}{src}};

    my $ret;

    for (@branches) {
	my $src = $self->{BRANCHINFO}{src}{$_};
	my $relpath = $path;
	$relpath =~ s/^$_//;
	for (keys %$src) {
	    # XXX: re-branch interface
	    my $info = $src->{$_}[0];
	    push @$ret, { dst => "$_$relpath",
			  srcrev => $info->[0],
			  dstrev => $info->[1],
			  isdir => $info->[2],
			}
		if $info->[0] <= $rev;
	}
    }
    return $ret;
}

sub branchfrom {
    my ($self, $path, $rev) = @_;
    my @branches = grep { "$_/" eq substr ($path, 0, length($_)+1) }
	keys %{$self->{BRANCHINFO}{dst}};

    my $ret;

    for (@branches) {
	my $dst = $self->{BRANCHINFO}{dst}{$_};
	my $relpath = $path;
	$relpath =~ s/^$_//;
	for (keys %$dst) {
	    # XXX: re-branch interface
	    my $info = $dst->{$_}[0];
	    push @$ret, { src => "$_$relpath",
			  srcrev => $info->[0],
			  dstrev => $info->[1],
			  isdir => $info->[2],
			}
		if $info->[1] <= $rev;
	}
    }
    return $ret;
}

sub branchpoints {
    my ($self, $path) = @_;
    my @branches = grep { $path =~ m|^$_/?| }
	keys %{$self->{BRANCHINFO}{src}};
    my $ret;

    for (@branches) {
	my $src = $self->{BRANCHINFO}{src}{$_};
	my $relpath = $path;
	$relpath =~ s/^$_//;
	for (keys %$src) {
	    # XXX: re-branch interface
	    my $info = $src->{$_}[0];
	    push @$ret, { dst => "$_$relpath",
			  srcrev => $info->[0],
			  dstrev => $info->[1],
			};
	}
    }
    @$ret = sort {$b->{srcrev} <=> $a->{srcrev}} @$ret if $ret;
    return $ret;
}

sub run {
    my $self = shift;
    return '<pre>'.Dump ($self->{BRANCHINFO});
}

1;
