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


my @SSH_keywords = qw(
    AddKeysToAgent
    AddressFamily
    BatchMode 
    BindAddress 
    CanonicalDomains 
    CanonicalizeFallbackLocal
    CanonicalizeHostname
    CanonicalizeMaxDots
    CanonicalizePermittedCNAMEs
    CASignatureAlgorithms
    CertificateFile
    ChallengeResponseAuthentication
    CheckHostIP
    Ciphers
    ClearAllForwardings
    Compression
    ConnectionAttempts
    ConnectTimeout
    ControlMaster
    ControlPath
    ControlPersist
    DynamicForward
    EscapeChar
    ExitOnForwardFailure
    FingerprintHash
    ForwardAgent
    ForwardX11
    ForwardX11Timeout
    ForwardX11Trusted
    GatewayPorts
    GlobalKnownHostsFile
    GSSAPIAuthentication
    GSSAPIDelegateCredentials
    HashKnownHosts
    Host
    HostbasedAuthentication
    HostbasedKeyTypes
    HostKeyAlgorithms
    HostKeyAlias
    HostName
    IdentitiesOnly
    IdentityAgent
    IdentityFile
    IPQoS
    KbdInteractiveAuthentication
    KbdInteractiveDevices
    KexAlgorithms
    LocalCommand
    LocalForward
    LogLevel
    MACs
    Match
    NoHostAuthenticationForLocalhost
    NumberOfPasswordPrompts
    PasswordAuthentication
    PermitLocalCommand
    PKCS11Provider
    Port
    PreferredAuthentications
    ProxyCommand
    ProxyJump
    ProxyUseFdpass
    PubkeyAcceptedKeyTypes
    PubkeyAuthentication
    RekeyLimit
    RemoteCommand
    RemoteForward
    RequestTTY
    SendEnv
    ServerAliveInterval
    ServerAliveCountMax
    SetEnv
    StreamLocalBindMask
    StreamLocalBindUnlink
    StrictHostKeyChecking
    TCPKeepAlive
    Tunnel
    TunnelDevice
    UpdateHostKeys
    User
    UserKnownHostsFile
    VerifyHostKeyDNS
    VisualHostKey
    XAuthLocation
);

#== ARRAY interface ==========================================================

sub new_ssh {
    my $addr = shift;
    my $loop = shift;

    my $mult     = 1; # default
    my $optional = 0; # default;
    my @options;
    if ($addr =~ s{ssh://}{}) { # inspired by https://tools.ietf.org/id/draft-salowey-secsh-uri-00.html
	$mult     = $1        if $addr =~ s/;multiplicity=(\d+)//;
	$TM2::log->warn( "multiplicity 0 implies that NO ssh session will be created" ) unless $mult > 0;
	$optional = $1        if $addr =~ s/;optional=(\d+)//;

	foreach my $kw (@SSH_keywords) {
	    push @options, "-o $kw=$1" if $addr =~ s/;$kw=([^@;]+)//;
	}
#warn Dumper \@options;
    }
#warn "addr $addr";
    $addr =~ /((\w+?)@)?([\w\.]+)(:(\d+))?/
        // $TM2::log->logdie ("address should be of the form (user@)?hostname(:port)? '$addr'");
    my ($user, $host, $port) = ($2, $3, $5);
#warn "user >>$user<< host >>$host<< port >>$port<< mult >>$mult<<";

    my @sshs;
    foreach my $instance (1..$mult) {
	use IPC::PerlSSH::Async;
	my $ssh;
	$ssh = IPC::PerlSSH::Async->new(
	    on_exception => sub {
		$TM2::log->debug( "IPC::PerlSSH::Async build exception '$_[0]' ignored for the moment..." );
	    },
	    Host         => $host,
  ($user ? (User         => $user) : ()),
  ($port ? (Port         => $port) : ()),
	    SshOptions   => \@options,
	    );
#warn "generated $ssh";
	$loop->add( $ssh );
#warn "added ssh";
	my $url;
	$url .= "ssh://".($user ? $user : '')."\@$host";
	$url .= ":$port" if defined $port;
	$url =~ s{@}{;instance=$instance/$mult@} if $mult > 1;
	push @sshs, { url        => $url,
		      connection => $ssh,
		      optional   => $optional,
		      options    => \@options };
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
	pool      => undef, # array of connections (IPC::PerlSSH::Async)
	pool_i    => 0, # RR index into the pool
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
            map {
	          map { new_ssh( $_, $elf->{loop} ) } @$_                                        # produces a LIST of HASHes 
            } @{ $elf->{addrs} }                                                               # get each of the LISTs within the ARRAY
	    ];
#warn "pool ".Dumper $elf->{pool};
#warn "pool ".Dumper [
#      map { $_->{url} .' '.($_->{optional} ? 'optional' : 'mandatatory') }
#      @{ $elf->{pool} }
#];

	my @partials; # collect results temporarily, until we can flush them
	foreach my $t (@block) {                                                               # walk over every incoming tuple
#warn "working on ".Dumper $t;
	    my ($code, @params) = map { $_->[0] } @$t;                                         # assume TM2::Literal (TODO: general stringify?)
#warn "\\ code $code";
	    _find_working_connection_and_launch( $elf, $code, \@params, \@partials, (scalar @block), $tail );
	}

sub _find_working_connection_and_launch {
    my $elf = shift;
    my $code = shift;
    my $params = shift;
    my $partials = shift;
    my $nr_tuples = shift;
    my $tail = shift;

    my $instance = _find_working_connection_within( $elf ) # side effect on elf pool index
	or $TM2::log->logdie( "all connections in the pool are gone" );

    my $ssh = $instance->{connection};
#warn "\\_ $ssh detected as valid ";
    $ssh->eval(
	code      => $code,
	args      => $params,
	on_result => sub {
#warn "result".Dumper \@_;
	    my $s = join "", @_;
	    push @$partials, [ TM2::Literal->new( $s ) ];                # collect the intermediate results in the block
	    if ($nr_tuples <= scalar @$partials) {                    # if we have as many responses as commands,
#warn "tailing ".Dumper \@$partials;
		push @$tail, @$partials;                                 # push the whole lot downstream
		@$partials = ();                                              # flush the buffer
	    }
	},
	on_exception => sub {
#warn "exception on eval $_[0]";
	    $instance->{exception}++; # ignore it next time around
	    if ($instance->{optional}) {
		$TM2::log->warn( $instance->{url} . " went out of business, ignoring since it is marked optional");
		_find_working_connection_and_launch( $elf, $code, $params, $partials, $nr_tuples, $tail );  # try re-launch
	    } else {
		$TM2::log->logdie( $instance->{url} . " went out of business, mandatory, so we are escalating ..." );
	    }
	},
	);
}

sub _find_working_connection_within {
    my $elf = shift;
    my $p = $elf->{pool};
    return undef unless grep { ! $_->{exception} }
                        grep {   $_->{connection} }  @$p;                        # so there is at least one defined connection in this pool
#warn "there is one defined ssh in $p";

    my $instance; # agenda
    my $i = $elf->{pool_i};                                                   # find wrapper index
    do {
#warn "ssh for $p -> $i";
	$instance = $p->[$i];                                                  # select one connection within the subpool
	$i = 0 if ++$i > $#$p;                                                 # increment and reset wrapper index, in case
	$elf->{pool_i} = $i;                                                  # track that for next time in this subpool
    } until $instance->{connection} && ! $instance->{exception};               # if not undef, we will work with it
#warn "\\  for $p -> $i >>$instance";
    return $instance;
}


    }
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

#			$elf->{loop}->remove( $instance->{connection} );
#			$instance->{connection} = undef;   # mark it as unusable


	    foreach my $p (@{ $elf->{pool} }) {                                                # the tuple must be handed down to ALL subpools
		    or next;                                                                   # no valid connection in this pool, so we ignore this tuple here
warn "ssh with $code";
	    }
	}
#warn "partials".Dumper $partials;
# TODO: warn/react if partial result have not been tailed
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



