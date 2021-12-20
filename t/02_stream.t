use strict;
use Data::Dumper;
use Test::More;
use Test::Exception;
use Test::Deep;

use TM2;
use TM2::Literal;
use TM2::TS::Test;

use constant DONE   => 1;
use constant STRESS => 0;

my $warn = shift @ARGV;
unless ($warn) {
    close STDERR;
    open (STDERR, ">/dev/null");
    select (STDERR); $| = 1;
}

use TM2;
use Log::Log4perl::Level;
$TM2::log->level($warn ? $DEBUG : $ERROR); # one of DEBUG, INFO, WARN, ERROR, FATAL

use lib '../tm2-dbi/lib';
use lib '../tm2-base/lib';
use lib '../templescript/lib';

#== TESTS ========================================================================

require_ok( 'TM2::TS::Stream::ssh_s' );

if (DONE) {
    my $AGENDA = q{stream factory (multiple): };

    use IO::Async::Loop;
    my $loop = IO::Async::Loop->new;
    use TM2::TS::Stream::ssh_s;

    if (1) {
	my $cc = TM2::TS::Stream::ssh_s::factory->new (loop => $loop, addresses => []);
	isa_ok( $cc->loop, 'IO::Async::Loop');
	is_deeply( $cc->addresses, [], $AGENDA.'no addresses' );

	$cc = TM2::TS::Stream::ssh_s::factory->new (loop => $loop, addresses => [ [ TM2::Literal->new( 'localhost' ) ] ]);
	isa_ok( $cc->loop, 'IO::Async::Loop');
	is_deeply( $cc->addresses, [ [ TM2::Literal->new( 'localhost' ) ] ], $AGENDA.'addresses' );
#--
	$cc = TM2::TS::Stream::ssh_s::factory->new (TM2::Literal->new( 'localhost' ), loop => $loop);
	isa_ok( $cc->loop, 'IO::Async::Loop');
	is_deeply( $cc->addresses, [ [ TM2::Literal->new( 'localhost' ) ] ], $AGENDA.'addresses' );
#--
	$cc = TM2::TS::Stream::ssh_s::factory->new (TM2::Literal->new( 'localhost1' ), TM2::Literal->new( 'localhost2' ), loop => $loop);
	isa_ok( $cc->loop, 'IO::Async::Loop');
	is_deeply( $cc->addresses, [ [ TM2::Literal->new( 'localhost1' ), TM2::Literal->new( 'localhost2' ) ] ], $AGENDA.'addresses' );
#--
	$cc = TM2::TS::Stream::ssh_s::factory->new ([ TM2::Literal->new( 'localhost1' ) ], [ TM2::Literal->new( 'localhost2' ) ], loop => $loop);
	isa_ok( $cc->loop, 'IO::Async::Loop');
	is_deeply( $cc->addresses, [ [ TM2::Literal->new( 'localhost1' ) ], [ TM2::Literal->new( 'localhost2' ) ] ], $AGENDA.'addresses' );
    }
    if (1) { # single connection
	my $cc = TM2::TS::Stream::ssh_s::factory->new (TM2::Literal->new( 'localhost' ), loop => $loop);
        my $t = [];
        my $c = $cc->prime ($t);
	isa_ok( tied @$c, 'TM2::TS::Stream::ssh_s', $AGENDA.'stream type');

	push @$c, [ TM2::Literal->new( '"XXX";' ) ];

	$loop->watch_time( after => 4, code => sub {
	    push @$c, bless [], 'ts:collapse';
	    $loop->stop; } ); diag ("collapsing in 4 secs") if $warn;
	$loop->run;
#warn "final".Dumper $t;
	is_singleton ($t, TM2::Literal->new( "XXX" ), $AGENDA.'result with single tuple, no params');

    }
    if (1) { # two hosts, two tuples
	my $cc = TM2::TS::Stream::ssh_s::factory->new (loop => $loop, addresses => [ [ TM2::Literal->new( 'localhost'    ) ],
										     [ TM2::Literal->new( 'localhost:22' ) ] ]);
        my $t = [];
        my $c = $cc->prime ($t);
	isa_ok( tied @$c, 'TM2::TS::Stream::ssh_s', $AGENDA.'stream type');

	push @$c, [ TM2::Literal->new( '"XXX";' ) ], [ TM2::Literal->new( '"YYY";' ) ];

	$loop->watch_time( after => 4, code => sub {
	    push @$c, bless [], 'ts:collapse';
	    $loop->stop; } ); diag ("collapsing in 4 secs") if $warn;
	$loop->run;
#warn "final".Dumper $t;
	is ((scalar @$t), 4, $AGENDA.'2 batches of 2');
	ok( eq_set([ map { $_->[0]->[0] } @$t],
		   [ "XXX", "YYY", "XXX", "YYY" ]), $AGENDA.'two hosts, two tuples, contents');
    }
    if (1) { # one host x2, two tuples
	my $cc = TM2::TS::Stream::ssh_s::factory->new (loop => $loop, addresses => [ [ TM2::Literal->new( 'ssh://;multiplicity=2@localhost' ) ] ]);
        my $t = [];
        my $c = $cc->prime ($t);
	isa_ok( tied @$c, 'TM2::TS::Stream::ssh_s', $AGENDA.'stream type');

	push @$c, [ TM2::Literal->new( '"XXX";' ) ], [ TM2::Literal->new( '"YYY";' ) ];

	$loop->watch_time( after => 4, code => sub {
	    push @$c, bless [], 'ts:collapse';
	    $loop->stop; } ); diag ("collapsing in 4 secs") if $warn;
	$loop->run;
#warn "final".Dumper $t;
	is ((scalar @$t), 2, $AGENDA.'1 batch of 2');
	ok( eq_set([ map { $_->[0]->[0] } @$t],
		   [ "XXX", "YYY" ]), $AGENDA.'one hostx2, two tuples, contents');
    }
    if (1) { # one host x2, two tuples, blocking
	my $cc = TM2::TS::Stream::ssh_s::factory->new (loop => $loop, addresses => [ [ TM2::Literal->new( 'ssh://;multiplicity=2@localhost' ) ] ]);
        my $t = [];
        my $this = [];
	use TM2::TS::Stream::demote;
        tie @$this, 'TM2::TS::Stream::demote', $t;
        my $c = $cc->prime ($this);
	isa_ok( tied @$c, 'TM2::TS::Stream::ssh_s', $AGENDA.'stream type');

	push @$c, [ TM2::Literal->new( '"XXX";' ) ], [ TM2::Literal->new( '"YYY";' ) ];

	$loop->watch_time( after => 4, code => sub {
	    push @$c, bless [], 'ts:collapse';
	    $loop->stop; } ); diag ("collapsing in 4 secs") if $warn;
	$loop->run;
#warn "final".Dumper $t;
	$t = $t->[0]->[0]; # undo demote
	is ((scalar @$t), 2, $AGENDA.'1 batch of 2');
	ok( eq_set([ map { $_->[0]->[0] } @$t],
		   [ "XXX", "YYY" ]), $AGENDA.'one hostx2, two tuples, contents');
    }
    if (1) { # two hosts, one invalid, not optional
	my $cc = TM2::TS::Stream::ssh_s::factory->new (loop => $loop, addresses => [ [ TM2::Literal->new( 'localhost'    ) ],
										     [ TM2::Literal->new( 'xxxlocalhost' ) ] ]);
        my $t = [];
        my $c = $cc->prime ($t);
	isa_ok( tied @$c, 'TM2::TS::Stream::ssh_s', $AGENDA.'stream type');

	push @$c, [ TM2::Literal->new( '"XXX";' ) ], [ TM2::Literal->new( '"YYY";' ) ];

	$loop->watch_time( after => 4, code => sub {
	    push @$c, bless [], 'ts:collapse';
	    $loop->stop; } ); diag ("collapsing in 4 secs") if $warn;

	throws_ok {
	    $loop->run;
	} qr/ssh.+out/, $AGENDA.'unreachable host';

	$loop->run;
	diag "not interested in result";
    }
    if (1) { # two hosts, one invalid, but optional
	my $cc = TM2::TS::Stream::ssh_s::factory->new (loop => $loop, addresses => [ [ TM2::Literal->new( 'localhost'    ) ],
										     [ TM2::Literal->new( 'ssh://;optional=1@xxxlocalhost' ) ] ]);
        my $t = [];
        my $c = $cc->prime ($t);
	isa_ok( tied @$c, 'TM2::TS::Stream::ssh_s', $AGENDA.'stream type');

	push @$c, [ TM2::Literal->new( '"XXX";' ) ], [ TM2::Literal->new( '"YYY";' ) ];

	$loop->watch_time( after => 4, code => sub {
	    push @$c, bless [], 'ts:collapse';
	    $loop->stop; } ); diag ("collapsing in 4 secs") if $warn;

	$loop->run;
#warn "final".Dumper $t;
	is ((scalar @$t), 2, $AGENDA.'1 batch of 2');
	ok( eq_set([ map { $_->[0]->[0] } @$t],
		   [ "XXX", "YYY" ]), $AGENDA.'one hostx2, two tuples, contents');
    }
}

done_testing;

__END__

require_ok( 'TM2::TS::Stream::ssh' );

if (DONE) {
    my $AGENDA = q{stream factory: };

    use IO::Async::Loop;
    my $loop = IO::Async::Loop->new;
    use TM2::TS::Stream::ssh;

    {
	my $cc = TM2::TS::Stream::ssh::factory->new (loop => $loop, address => TM2::Literal->new( 'localhost' ));
	isa_ok( $cc->loop, 'IO::Async::Loop');
	is( $cc->address->[0], 'localhost', $AGENDA.'address' );
    }
    {
	my $cc = TM2::TS::Stream::ssh::factory->new (TM2::Literal->new( 'rho@somehost.com' ), loop => $loop);
	isa_ok( $cc->loop, 'IO::Async::Loop');
	is( $cc->address->[0], 'rho@somehost.com', $AGENDA.'address' );
    }
    if (1) {
	my $cc = TM2::TS::Stream::ssh::factory->new (TM2::Literal->new( 'localhost' ), loop => $loop);
        my $t = [];
        my $c = $cc->prime ($t);
	isa_ok( tied @$c, 'TM2::TS::Stream::ssh', $AGENDA.'stream type');
	
	push @$c, [ TM2::Literal->new( '"XXX";' ) ];

	$loop->watch_time( after => 4, code => sub {
	    push @$c, bless [], 'ts:collapse';
	    $loop->stop; } ); diag ("collapsing in 4 secs") if $warn;
	$loop->run;

#warn "final".Dumper $t;
	is_singleton ($t, TM2::Literal->new( "XXX" ), $AGENDA.'result with single tuple, no params');

    }
    if (1) {
	my $cc = TM2::TS::Stream::ssh::factory->new (TM2::Literal->new( 'localhost' ), loop => $loop);
        my $t = [];
        my $c = $cc->prime ($t);
	isa_ok( tied @$c, 'TM2::TS::Stream::ssh', $AGENDA.'stream type');
	
	push @$c, [ TM2::Literal->new( 'shift' ), TM2::Literal->new( 'YYY' ) ];

	$loop->watch_time( after => 4, code => sub {
	    push @$c, bless [], 'ts:collapse';
	    $loop->stop; } ); diag ("collapsing in 4 secs") if $warn;
	$loop->run;

#warn "final".Dumper $t;
	is_singleton ($t, TM2::Literal->new( "YYY" ), $AGENDA.'result with single tuple, no params');
    }
    if (1) {
	my $cc = TM2::TS::Stream::ssh::factory->new (TM2::Literal->new( 'localhost' ), loop => $loop);
        my $t = [];
        my $c = $cc->prime ($t);
	isa_ok( tied @$c, 'TM2::TS::Stream::ssh', $AGENDA.'stream type');
	
	push @$c, [ TM2::Literal->new( '"XXX";' ) ], [ TM2::Literal->new( '"YYY";' ) ], [ TM2::Literal->new( '"ZZZ";' ) ];

	$loop->watch_time( after => 4, code => sub {
	    push @$c, bless [], 'ts:collapse';
	    $loop->stop; } ); diag ("collapsing in 4 secs") if $warn;
	$loop->run;

	ok( eq_array([ map { $_->[0] } map { $_->[0] } @$t ],
		     [ "XXX", "YYY", "ZZZ" ]), $AGENDA.'whole block collected');

#warn "final".Dumper $t;
    }
}

done_testing;

__END__


if (DONE) {
    my $AGENDA = q{socket errors: };

    use TM2::TS::Stream::zeromq;
    {
        my $cc = TM2::TS::Stream::zeromq::factory->new (loop => $loop, uri => "0mqqq-$endpoint;type=ROUTER");

        my $t = [];
        my $c = $cc->prime ($t);
        throws_ok {
            push @$c, bless [], 'ts:kickoff';
        } qr/endpoint/, $AGENDA.'wrong endpoint'
    }
    {
        my $cc = TM2::TS::Stream::zeromq::factory->new (loop => $loop, uri => "0mq-$endpoint;type=ROUTERXXX");

        my $t = [];
        my $c = $cc->prime ($t);
        throws_ok {
            push @$c, bless [], 'ts:kickoff';
        } qr/type/, $AGENDA.'wrong type'
    }
}if (DONE) {
    my $AGENDA = q{simple router socket ping: };

    use IO::Async::Loop;
    my $loop = IO::Async::Loop->new;
    use TM2::TS::Stream::zeromq;
    my $cc = TM2::TS::Stream::zeromq::factory->new (loop => $loop, uri => "0mq-$endpoint;type=ROUTER");

    my $t = [];
    my $c = $cc->prime ($t);
    push @$c, bless [], 'ts:kickoff';

    my $req = $zmq_ctx->socket(ZMQ_DEALER);
    $req->connect( $endpoint );

    use IO::Async::Timer::Periodic;
    my $timer = IO::Async::Timer::Periodic->new(
        interval => 3,
        on_tick => sub {
            $req->send_multipart( [ qw[aaa 3 http://www.com ] ] );
        },
        );
    $timer->start;
    $loop->add( $timer );


    $loop->watch_time( after => 14, code => sub {
        push @$c, bless [], 'ts:collapse';
        $loop->stop; } ); diag ("collapsing in 14 secs") if $warn;
    $loop->run;

    $timer->stop; $loop->remove( $timer );

    is ((scalar @$t), 4, $AGENDA.'nr ticks');
    map { is( (scalar @$_), 5, $AGENDA.'tuple length') } @$t;
    map { isa_ok(    $_->[0], 'ZMQ::FFI::ZMQ3::Socket',              $AGENDA.'socket' )}  @$t;
    map { is_deeply( $_->[2], TM2::Literal->new( 'aaa' ),            $AGENDA.'string' )}  @$t;
    map { is_deeply( $_->[3], TM2::Literal->new( 3 ),                $AGENDA.'integer' )} @$t;
    map { is_deeply( $_->[4], TM2::Literal->new( 'http://www.com' ), $AGENDA.'uri' )} @$t;
#warn Dumper $t;
}


if (DONE) {
    my $AGENDA = q{receiving & sending via stream: };

    use IO::Async::Loop;
    my $loop = IO::Async::Loop->new;

    use Net::Async::0MQ::Socket;
    my $hb = Net::Async::0MQ::Socket->new(
        endpoint => $endpoint,
        type     => ZMQ_REP,
        context  => $zmq_ctx,
        on_recv => sub {
            my $s = shift;
            my @c = $s->recv_multipart();
#warn "hb received ".Dumper \@c;
            is_deeply (\@c, [ 'aaa', 'bbb' ], $AGENDA.'received');
        }
        );
    $loop->add( $hb );

    my $tail = [];
    my $this = [];



    use TM2::TS::Stream::zeromq;
    my $zz = TM2::TS::Stream::zeromq::factory->new (loop => $loop, uri => "0mq-$endpoint;type=REP");

    my $tail = [];

    my $back = [];
    use TM2::TS::Stream::perlcode;
    tie @$back, 'TM2::TS::Stream::perlcode', [ ], sub {
        my ($s, @t) = @_;
#warn "sending back to $s".Dumper \@t;
        map { $TM2::log->logdie( "cannot process non TM2::Literals for serialization" )
                  unless ref($_) eq 'TM2::Literal' }
            @t;
        $s->send_multipart( [ map { $_->[0] } @t ] );
        return \@t;
    }, { tuple => 1 }, $tail;

    my $hb= $zz->prime ($back);

    push @$hb, bless [], 'ts:kickoff'; # wake it up


    my $req = $zmq_ctx->socket(ZMQ_REQ);
    $req->connect( $endpoint );

    use IO::Async::Timer::Periodic;

    my $sender = IO::Async::Timer::Periodic->new(
        interval => 3,
        on_tick => sub {
            $req->send_multipart( [ qw[aaa] ] );
        },
        );
    $sender->start;
    $loop->add( $sender );

    my $back_ctr = 0;
    my $receiver = IO::Async::Timer::Periodic->new(
        interval => 1,
        on_tick => sub {
#warn "testing recv";
            if ( $req->has_pollin ) {
                my @c = $req->recv_multipart( );
                is_deeply( \@c, [ 'aaa' ], $AGENDA.'serialized sent back');
                $back_ctr++;
#warn "got back ".Dumper \@c;
            }
        },
        );
    $receiver->start;
    $loop->add( $receiver );

    $loop->watch_time( after => 14, code => sub {
        push @$hb, bless [], 'ts:collapse';
        $loop->stop; } ); diag ("collapsing in 14 secs") if $warn;
    $loop->run;

    $sender->stop;   $loop->remove( $sender );
    $receiver->stop; $loop->remove( $receiver );

    is ($back_ctr, 4, $AGENDA.'all sent back');

    is ((scalar @$tail), 4, $AGENDA.'all sent forward');
}


