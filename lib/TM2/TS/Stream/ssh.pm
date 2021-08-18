package TM2::TS::Stream::ssh::factory;

use Moose;
extends 'TM2::TS::Stream::factory';

use Data::Dumper;

has 'loop' => (
    is        => 'rw',
    isa       => 'IO::Async::Loop',
    );

has 'address' => (
    is        => 'rw',
    isa       => 'TM2::Literal',
    );

around 'BUILDARGS' => sub {
    my $orig = shift;
    my $class = shift;
#warn "0MQ factory new $_[0]";
#warn "params $class $orig ".Dumper \@_;

    if (scalar @_ % 2 == 0) {
        return $class->$orig (@_);
    } else {
        my $addr = shift;
        return $class->$orig ({ address => $addr, @_ });
    }
};

sub prime {
    my $self = shift;
    my $out = [];

    tie @$out, 'TM2::TS::Stream::ssh', $self->loop, $self->address->[0], @_;
    return $out;
}

1;

package TM2::TS::Stream::ssh;

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

    $addr =~ /((\w+)@)?(\w+)(:(\d+))?/
        // $TM2::log->logdie ("address should be of the form (user@)?hostname(:port)? '$addr'");
    my ($user, $host, $port) = ($2, $3, $5);
#warn ">>$user<< >>$host<< >>$port<<";
    use IPC::PerlSSH::Async;
    my $ssh = IPC::PerlSSH::Async->new(
	  on_exception => sub {
	    $TM2::log->logdie( "ssh handle exception '$_[0]'" ); },
 	  Host         => $host,
($user ? (User         => $user) : ()),
($port ? (Port         => $port) : ()),
	);
#warn "generated $ssh";
    $loop->add( $ssh );

    return $ssh;
}

sub TIEARRAY {
    my $class = shift;
    my ($loop, $address, $tail) = @_;
#warn "ssh TIEARRAY $loop tail $tail";

    return bless {
        creator   => $$, # we can only be killed by our creator (not some fork()ed process)
        stopper   => undef,
	ssh       => undef,
        loop      => $loop,
	address   => $address,
        tail      => $tail,
    }, $class;
}

sub DESTROY {
    my $elf = shift;
#warn "DESTROY";
    return unless $$ == $elf->{creator};
#warn "DESTROY ssh $elf waiting";
    $elf->{loop}->await( $elf->{stopper} ) if $elf->{stopper};                                      # we do not give up that easily
#warn "DESTROY really";
    if ($elf->{ssh}) {
	$elf->{loop}->remove( $elf->{ssh} );
	undef $elf->{ssh};
    }
}

sub FETCH {
    my $elf = shift;
    return undef;
}

sub PUSH {
    my $elf = shift;
    my @block = @_;
#warn "ssh PUSH ".Dumper \@block;

    my $tail = $elf->{tail}; # handle

    if (ref ($_[0]) eq 'ts:collapse') {
	$elf->{stopper}->done unless $elf->{stopper}->is_done;

    } elsif (ref ($_[0]) eq 'ts:disable') {
	$elf->{stopper}->done unless $elf->{stopper}->is_done;

    } else {
	$elf->{stopper} //= $elf->{loop}->new_future;
	$elf->{ssh}     //= new_ssh ($elf->{address}, $elf->{loop} );
	my $block = [];  # here there is a 1:1 relationship between commands issued, and the tuple with the response
	foreach my $t (@block) {                                                           # walk over every incoming tuple
#warn Dumper $t;
	    my ($code, @params) = map { $_->[0] } @$t;                                     # assume TM2::Literal (TODO: general stringify?)
#warn "code $code";
	    $elf->{ssh}->eval(
		code      => $code,
		args      => \@params,
		on_result => sub {
#warn "result".Dumper \@_;
		    my $s = join "", @_;
		    push @$block, [ TM2::Literal->new( $s ) ];                            # collect the intermediate results in the block
#warn "-> block ".Dumper $block;
		    if (scalar @$block >= scalar @block) {                                # if we have as many responses as commands, we can push downstream
			push @$tail, @$block;
		    }
		},
	    );
	}
    }
}

sub FETCHSIZE {
    my $elf = shift;
    return 0;
}

sub CLEAR {
    my $elf = shift;
    $elf->{size} = 0;
}

1;

__END__


use ZMQ::FFI qw(ZMQ_REQ ZMQ_PUB ZMQ_SUB ZMQ_FD ZMQ_REP ZMQ_ROUTER ZMQ_DEALER);
our $CTX = ZMQ::FFI->new(); # shared in this process

sub new_socket {
    my $uri = shift;
    my $loop = shift;
#    my $ctx  = shift;
    my $tail = shift;

    $uri =~ /0mq-(.+?);(.+)/;
    my $endpoint = $1
	// $TM2::log->logdie ("no endpoint detected inside '$uri'");
    my %params = map { split (/=/, $_ ) }
		       split (/;/, $2);
    $params{type} = { # convert string into constant
		      'ROUTER' => ZMQ_ROUTER,
		      'DEALER' => ZMQ_DEALER,
		      'PUB'    => ZMQ_PUB,
		      'REQ'    => ZMQ_REQ,
		      'REP'    => ZMQ_REP,
	            }->{ uc( $params{type} ) }
        // $TM2::log->logdie ("unknown/unhandled 0MQ socket type inside '$endpoint'");
#warn "endpoint $endpoint ".Dumper \%params;

    use Net::Async::0MQ::Socket;
    my $socket = Net::Async::0MQ::Socket->new(
	endpoint => $endpoint,
	type     => $params{type},
	context  => $CTX,
	on_recv  => sub {
	    my $s = shift;
	    my @d = $s->recv_multipart();
#warn "zeromq recv on $s ".Dumper \@d;
	    use TM2::Literal;
	    push @$tail, [ $s, map { TM2::Literal->new( $_ ) } @d ];
	}
	);
    $loop->add( $socket );
    return $socket;
}

1;

__END__

