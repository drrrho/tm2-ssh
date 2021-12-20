package TM2::TS::Stream::ssh_s::factory;

use Moose;
extends 'TM2::TS::Stream::factory';

use Data::Dumper;

has 'loop' => (
    is        => 'rw',
    isa       => 'IO::Async::Loop',
    );

has 'addresses' => (
    is        => 'rw',
    isa       => 'ArrayRef[ArrayRef]',
    );

around 'BUILDARGS' => sub {
    my $orig = shift;
    my $class = shift;

    if (ref($_[0]) eq 'TM2::Literal') {
	my @addrs;
	while (ref($_[0]) eq 'TM2::Literal') {
	    push @addrs, shift;
	}
        return $class->$orig ({ addresses => [ [ @addrs ] ], @_ });

    } elsif (ref($_[0]) eq 'ARRAY') {
	my @addrs;
	while (ref($_[0]) eq 'ARRAY') {
	    push @addrs, shift;
	}
        return $class->$orig ({ addresses => [ @addrs ], @_ });

    } else {
        return $class->$orig (@_);
    }
};

sub prime {
    my $self = shift;
    my $out = [];

    tie @$out, 'TM2::TS::Stream::ssh_s', $self->loop,
	                                 [ map { [ map { $_->[0] } @$_ ] }  @{ $self->addresses } ],   # strip literal wrappers
	                                 @_;
    return $out;
}

1;

package TM2::TS::Stream::ssh_s;

use strict;
use warnings;

use Data::Dumper;

use vars qw( @ISA );

use TM2;
use TM2::TS::Shard;
@ISA = ('TM2::TS::Shard');


#== ARRAY interface ==========================================================

sub new_ssh {
    my $addr = shift;
    my $loop = shift;

    my $mult     = 1; # default
    my $optional = 0; # default;
    if ($addr =~ s{ssh://}{}) {
	$mult     = $1 if $addr =~ s/;multiplicity=(\d+)//;
	$optional = $1 if $addr =~ s/;optional=(\d+)//;
    }
    $addr =~ /(\w*?)(@)?(\w+)(:(\d+))?/
        // $TM2::log->logdie ("address should be of the form (user@)?hostname(:port)? '$addr'");
    my ($user, $host, $port) = ($1, $3, $5);
#warn ">>$user<< >>$host<< >>$port<< >>$mult<<";

    my @sshs;
    foreach my $instance (1..$mult) {
	use IPC::PerlSSH::Async;
	my $ssh;
	$ssh = IPC::PerlSSH::Async->new(
	    on_exception => sub {
		$TM2::log->debug( "IPC::PerlSSH::Async build exception '$_[0]' ignored for the moment..." );
#		$ssh->{process}->kill( 9 );
#		$loop->remove( $ssh );
#warn Dumper $ssh;
#		$optional
#		    ? $TM2::log->warn( "ssh exception '$_[0]'" )
#		    : $TM2::log->logdie( "ssh exception '$_[0]'" );
	    },
	    Host         => $host,
  ($user ? (User         => $user) : ()),
  ($port ? (Port         => $port) : ()),
	    );
#warn "generated $ssh";
	$loop->add( $ssh );
#warn "added ssh";
	my $url;
	$url .= "ssh://".($user ? $user : '')."\@$host";
	$url .= ":$port" if defined $port;
	$url =~ s{@}{;instance=$instance/$mult@} if $mult > 1;
	push @sshs, { url => $url, connection => $ssh, optional => $optional };
    }
#warn "return ".scalar @sshs;
    return @sshs;
}

sub TIEARRAY {
    my $class = shift;
    my ($loop, $addrs, $tail) = @_;
#warn "ssh TIEARRAY $loop tail $tail";
#warn "pool" . Dumper $addrs;

    return bless {
        creator   => $$,    # we can only be killed by our creator (not some fork()ed process)
        stopper   => undef,
	addrs     => $addrs,
	pool      => undef, # array of arrays of connections (IPC::PerlSSH::Async)
        loop      => $loop,
        tail      => $tail,
    }, $class;
}

sub DESTROY {
    my $elf = shift;
#warn "DESTROY $elf";
    return unless $$ == $elf->{creator};
#warn "DESTROY ssh $elf waiting";
    $elf->{loop}->await( $elf->{stopper} ) if $elf->{stopper};                                      # we do not give up that easily
#warn "DESTROY really";
#    if ($elf->{ssh}) {
#	$elf->{loop}->remove( $elf->{ssh} );
#	undef $elf->{ssh};
 #   }
}

sub PUSH {
    my $elf = shift;
    my @block = @_;
#warn "ssh_s PUSH ".Dumper \@block;

    my $tail = $elf->{tail}; # handle

    if (ref ($_[0]) eq 'ts:collapse') {
#warn "collapse pool ".Dumper $elf->{pool};
	map { $elf->{loop}->remove( $_ ) }                                                     # remove all ssh connections from the $loop
	   grep { defined }
	   map { $_->{connection} }                                                            # could have become invalid at some earlier time
	   map { @$_ }                                                                         # flatten list ref
	      @{ $elf->{pool} };
	$elf->{pool} = undef;                                                                  # trigger DESTROY
	$elf->{stopper}->done unless ! $elf->{stopper} || $elf->{stopper}->is_done;
        push @$tail, $_[0] if tied (@$tail);                                                   # pass it on downstream (if that can collapse)

    } elsif (ref ($_[0]) eq 'ts:disable') {
# TODO: not sure what to do here
	$elf->{stopper}->done unless $elf->{stopper}->is_done;
        push @$tail, $_[0] if tied (@$tail);                                                   # pass it on downstream (if that can collapse)

    } else {
	$elf->{stopper} //= $elf->{loop}->new_future;                                          # create death lock

	$elf->{pool} //= [                                                                     # maybe we already have created the ssh connections before
	    map { [ new_ssh( $_, $elf->{loop} ) ] }                                            # produces a LIST of HASHes 
	    map { @$_ }                                                                        # flatten this sublist
	       @{ $elf->{addrs} }                                                              # get each of the LISTs within the ARRAY
	    ];
#warn "pool ".Dumper $elf->{pool};
#warn "pool ".Dumper [
#map { [ map { $_->{url} .' '.($_->{optional} ? 'optional' : 'mandatatory') } @$_ ] }
#@{ $elf->{pool} }
#];

	my $partials = {};                                                                     # here we collect blocks on a per-subpool basis
	my $idx_pool = { map { $_ => 0 } @{ $elf->{pool} } };                                  # reset all indices in the subpools

	foreach my $t (@block) {                                                               # walk over every incoming tuple
#warn "working on ".Dumper $t;
	    my ($code, @params) = map { $_->[0] } @$t;                                         # assume TM2::Literal (TODO: general stringify?)
	    foreach my $p (@{ $elf->{pool} }) {                                                # the tuple must be handed down to ALL subpools
		my $instance = _find_working_connection_within( $p, $idx_pool )
		    or next;                                                                   # no valid connection in this pool, so we ignore this tuple here
#warn "ssh with $code";
		my $ssh = $instance->{connection};
#warn "\\_ $ssh ";
		$ssh->eval(
		    code      => $code,
		    args      => \@params,
		    on_exception => sub {
#warn "exception on eval $_[0]";
#			$elf->{loop}->remove( $instance->{connection} );
#			$instance->{connection} = undef;   # mark it as unusable
			$instance->{optional}
			    ? $TM2::log->warn( $instance->{url} . " went out of business, ignoring since it is marked optional")
			    : $instance->{exception}++      # only raise exception once
			    || $TM2::log->logdie( $instance->{url} . " went out of business, mandatory, so we are escalating ..." );
		    },
		    on_result => sub {
#warn "result".Dumper \@_;
			my $s = join "", @_;
			push @{ $partials->{$p} }, [ TM2::Literal->new( $s ) ];                # collect the intermediate results in the block
			if (scalar @block <= scalar @{ $partials->{$p} }) {                    # if we have as many responses as commands,
#warn "tailing ".Dumper $partials->{$p};
			    push @$tail, @{ $partials->{$p} };                                 # push the whole lot downstream
			    $partials->{$p} = [];                                              # flush the buffer
			}
		    },
		    );
	    }
	}
#warn "partials".Dumper $partials;
# TODO: warn/react if partial result have not been tailed
    }
}

sub _find_working_connection_within {
    my $p = shift;
    my $idx_pool = shift;
    return undef unless grep { $_->{connection} }  @$p;                        # so there is at least one defined connection in this pool
#warn "there is one defined ssh in $p";

    my $instance; # agenda
    my $i = $idx_pool->{$p};                                                   # find corresponding wrapper index
    do {
#warn "ssh for $p -> $i";
	$instance = $p->[$i];                                                  # select one connection within the subpool
	$i = 0 if ++$i > $#$p;                                                 # increment and reset wrapper index, in case
	$idx_pool->{$p} = $i;                                                  # track that for next time in this subpool
    } until $instance->{connection};               # if not undef, we will work with it
#warn "\\  for $p -> $i >>$ssh";
    return $instance;
}

sub FETCHSIZE {
    my $elf = shift;
    return 0;
}

sub FETCH {
    my $elf = shift;
    return undef;
}

sub CLEAR {
    my $elf = shift;
    $elf->{size} = 0;
}

1;

__END__

# sub new_sshs {
#     my $addrs = shift;
#     my $spool = shift;
#     my $loop  = shift;

#     foreach my $addr (@$addrs) {
# 	my $mult     = 1; # default
# 	my $optional = 0; # default;
# 	if ($addr =~ s{ssh://}{}) {
# 	    $mult     = $1 if $addr =~ s/;multiplicity=(\d+)//;
# 	    $optional = $1 if $addr =~ s/;optional=(\d+)//;
# 	}
# 	$addr =~ /((\w*)@)?(\w+)(:(\d+))?/
# 	    // $TM2::log->logdie ("address should be of the form (user@)?hostname(:port)? '$addr'");
# 	my ($user, $host, $port) = ($2, $3, $5);
# warn ">>$user<< >>$host<< >>$port<< >>$mult<< >>$optional<<";

# 	for (1..$mult) {
# 	    use IPC::PerlSSH::Async;
# 	    my $ssh;
# 	    $ssh = IPC::PerlSSH::Async->new(
# 		on_exception => sub {
# warn "perlssh exception $ssh $_[0] ".Dumper "$ssh";
# 		    $loop->remove( $ssh );                 # unhinge from loop
# warn "spool = ".join '', map { "$_ " } @$spool;
# 		    $_ == $ssh and $_ = undef for @$spool; # and also mark in the subpool that this connection is gone
# warn "\\\\_   = ".join '', map { "$_ " } @$spool;
# #		    $ssh->{process}->kill( 9 );
# 		    $optional
# 			? $TM2::log->warn( "ssh exception '$_[0]', but continuing as target is optional" )
# 			: $TM2::log->warn( "ssh exception '$_[0]'" );
# 		},
# 		Host         => $host,
#       ($user ? (User         => $user) : ()),
#       ($port ? (Port         => $port) : ()),
# 		);
# #warn "generated $ssh";
# 	    $loop->add( $ssh );
# #warn "added ssh";
# 	    push @$spool, $ssh;
# 	}
#     }
#     return $spool;
# }



