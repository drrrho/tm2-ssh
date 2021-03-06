use strict;
use warnings;

use Test::More;
use Test::Exception;
use Test::Moose;
use TM2::TS::Test;
use TM2::TempleScript::Test;

use Data::Dumper;
$Data::Dumper::Indent = 1;

use constant DONE => 1;

sub _chomp {
    my $s = shift;
    chomp $s;
    return $s;
}

my $warn = shift @ARGV;
unless ($warn) {
    close STDERR;
    open (STDERR, ">/dev/null");
    select (STDERR); $| = 1;
}


use lib '../tm2_dbi/lib';
use lib '../tm2-base/lib';
use lib '../templescript/lib';

use TM2;
use Log::Log4perl::Level;
$TM2::log->level($warn ? $DEBUG : $ERROR); # one of DEBUG, INFO, WARN, ERROR, FATAL

use TM2::TempleScript;

sub _parse {
    my $ref_stm = shift;
    my $t = shift;

    use TM2::Materialized::TempleScript;
    my $tm = TM2::Materialized::TempleScript->new (baseuri => 'tm:')
	->extend ('TM2::ObjectAble')
	->establish_storage ('*/*' => {})
	->extend ('TM2::Executable')
	->extend ('TM2::ImplementAble')
	->extend( 'TM2::StackAble' )
	    ->stack_under( $ref_stm )
	;

    $tm->deserialize ($t);
    return $tm;
}

sub _mk_ctx {
    my $stm = shift;
    return [ { '$_'  => $stm, '$__' => $stm } ];
}

#-- TESTS ----------------------------------------------------------

use TM2::TempleScript::Parser;
#$TM2::TempleScript::Parser::UR_PATH = '/usr/share/templescript/ontologies/';
$TM2::TempleScript::Parser::UR_PATH = '../templescript/ontologies/';

unshift  @TM2::TempleScript::Parser::TS_PATHS, './ontologies/';
my $core = TM2::Materialized::TempleScript->new (
    file    => $TM2::TempleScript::Parser::UR_PATH . 'core.ts',
    baseuri => 'ts:')
        ->extend ('TM2::ObjectAble')
        ->extend ('TM2::ImplementAble')
    ->sync_in;
my $env = TM2::Materialized::TempleScript->new (
    file    => $TM2::TempleScript::Parser::UR_PATH . 'env.ts',
    baseuri => 'ts:')
        ->extend ('TM2::ObjectAble')
        ->extend ('TM2::ImplementAble')
    ->sync_in;

my $sco = TM2::TempleScript::Stacked->new (orig => $core, id => 'ts:core');
my $sen = TM2::TempleScript::Stacked->new (orig => $env,  id => 'ts:environment', upstream => $sco);

require_ok( 'TM2::TS::Stream::ssh_s' );

if (DONE) {
    my $AGENDA = q{factory, structural: };

    use IO::Async::Loop;
    my $loop = IO::Async::Loop->new;

    my $stm = $sen;
    my $tm = _parse (\$stm, q{

%include file:ssh.ts

});

    my $ctx = _mk_ctx ($stm);
    $ctx = [ @$ctx, { '$loop' => $loop } ];
#--
    my $tss;

    if (1) {
	$tss = TM2::TempleScript::return ($ctx, q{
( "localhost" ) |->> ts:fusion( sshp:pool )
               });
	is_singleton( $tss, undef, $AGENDA.'single factory');
	my $cc = $tss->[0]->[0];
	isa_ok( $cc, 'TM2::TS::Stream::ssh_s::factory');
	is_deeply( $cc->addresses, [ 'ssh://localhost' ], $AGENDA.'target addresses, canonicalized');
	isa_ok( $cc->loop, 'IO::Async::Loop');
#warn Dumper $tss; exit;
    }
#--
    $stm = $sen;
    $tm = _parse (\$stm, q{

%include file:ssh.ts

sshp:pool
ssh:ConnectTimeout : "3" ^^ lang:perl
sshp:multiplicity  : 4

});
    $ctx = _mk_ctx ($stm);
    $ctx = [ @$ctx, { '$loop' => $loop } ];

    if (1) {
	$tss = TM2::TempleScript::return ($ctx, q{
( "localhost" ) |->> ts:fusion( sshp:pool )
               });
	is_singleton( $tss, undef, $AGENDA.'single factory');
	my $cc = $tss->[0]->[0];
	isa_ok( $cc, 'TM2::TS::Stream::ssh_s::factory');
	is_deeply( $cc->addresses, [ 'ssh://;ConnectTimeout=3;multiplicity=4@localhost' ], $AGENDA.'target addresses, with options');
	isa_ok( $cc->loop, 'IO::Async::Loop');
#warn Dumper $tss; exit;
    }
#--
    $stm = $sen;
    $tm = _parse (\$stm, q{

%include file:ssh.ts

sshp:pool
ssh:ConnectTimeout : "3" ^^ lang:perl
sshp:multiplicity  : 4

});
    $ctx = _mk_ctx ($stm);
    $ctx = [ @$ctx, { '$loop' => $loop } ];

    if (1) {
	$tss = TM2::TempleScript::return ($ctx, q{
( "ssh://;ConnectTimeout=5@localhost" ) |->> ts:fusion( sshp:pool )
               });
	is_singleton( $tss, undef, $AGENDA.'single factory');
	my $cc = $tss->[0]->[0];
	isa_ok( $cc, 'TM2::TS::Stream::ssh_s::factory');
	TODO: {
	    local $TODO = 'override';
	    is_deeply( $cc->addresses, [ 'ssh://;ConnectTimeout=5;multiplicity=4@localhost' ], $AGENDA.'target addresses, with options, merge');
	}
	isa_ok( $cc->loop, 'IO::Async::Loop');
#warn Dumper $tss; exit;
    }
}

if (DONE) {
    my $AGENDA = q{given factory, execute: };

    use IO::Async::Loop;
    my $loop = IO::Async::Loop->new;

    my $stm = $sen;
    my $tm = _parse (\$stm, q{

%include file:ssh.ts

do-ssh isa ts:stream
return
   ( "'XXX';" ) | @ $ssh |->> ts:tap( $tss )

});

    my $cc = TM2::TS::Stream::ssh_s::factory->new (TM2::Literal->new( 'localhost' ), loop => $loop);
    my $ts = [];

    my $ctx = _mk_ctx ($stm);
    $ctx = [ @$ctx, { '$loop' => $loop, '$ssh' => $cc, '$tss' => $ts } ];
#--
    if (1) {
	{
	    (my $ss, undef) = $tm->execute ($ctx);
	    $loop->watch_time( after => 5, code => sub { diag "stopping timeout " if $warn; push @$ss, bless [], 'ts:collapse'; } );
	}
	$loop->watch_time( after => 7, code => sub { diag "stopping loop " if $warn; $loop->stop; } );
	$loop->run;

	is_singleton( $ts, TM2::Literal->new( 'XXX' ), $AGENDA.'ssh response');
#warn Dumper $ts;
    }
}

if (DONE) {
    my $AGENDA = q{computed factory in junction, execute: };

    use IO::Async::Loop;
    my $loop = IO::Async::Loop->new;

    my $ap = new TM2::TempleScript::Parser ();                          # quickly clone a parser

    my $stm = $sen;
    my $tm = _parse (\$stm, q{

%include file:ssh.ts

});

    my $ts = [];

    my $ctx = _mk_ctx ($stm);
    $ctx = [ @$ctx, { '$loop' => $loop, '$tss' => $ts } ];
#--
    @$ts = ();
    if (1) {
	{
	    my $cpr = $ap->parse_query (q{ 
   ( "'XXX';", "'YYY';" ) | zigzag
 |-{
     count | ( "localhost" ) |->> ts:fusion( sshp:pool ) => $ssh
 ||><||
     <<- 2 sec | @ $ssh |->> io:write2log
 }-| demote |->> ts:tap( $tss )

 }, $tm->stack);
	    (my $ss, undef) = TM2::TempleScript::PE::pe2pipe ($ctx, $cpr);
	    $loop->watch_time( after => 4, code => sub { diag "stopping stream " if $warn; push @$ss, bless [], 'ts:collapse'; } );
	    $loop->watch_time( after => 5, code => sub { diag "stopping loop "   if $warn; $loop->stop; } );
	    push @$ss, bless [], 'ts:kickoff';
	}
	$loop->run;

#warn Dumper $ts; exit;
	is_singleton( $ts, undef, $AGENDA.'ssh single');
	my $ts2 = $ts->[0]->[0];
	ok( scalar @$ts2 == 2, $AGENDA.'both went through');
	ok(eq_array ([ map { $_->[0]->[0] } @$ts2 ], [ qw(XXX YYY) ]), $AGENDA.'content');
    }
#--
    @$ts = ();
    if (1) {
	{
	    my $cpr = $ap->parse_query (q{ 
   ( "'XXX';", "'YYY';" ) | zigzag
 |-{
     count | ( "localhost" ) |->> ts:fusion( sshp:pool ) => $ssh
 ||><||
     <- 2 sec |_1_| @ $ssh |->> io:write2log
 }-| demote |->> ts:tap( $tss )

 }, $tm->stack);
	    (my $ss, undef) = TM2::TempleScript::PE::pe2pipe ($ctx, $cpr);
	    $loop->watch_time( after => 4, code => sub { diag "stopping stream " if $warn; push @$ss, bless [], 'ts:collapse'; } );
	    $loop->watch_time( after => 5, code => sub { diag "stopping loop "   if $warn; $loop->stop; } );
	    push @$ss, bless [], 'ts:kickoff';
	}
	$loop->run;
#warn Dumper $ts; exit;
	ok( scalar @$ts == 2, $AGENDA.'both went through');
	is_singleton( $ts->[0]->[0], TM2::Literal->new('XXX'), $AGENDA.'ssh single');
	is_singleton( $ts->[1]->[0], TM2::Literal->new('YYY'), $AGENDA.'ssh single');
    }
#--
    @$ts = ();
    if (1) {
	{
	    my $cpr = $ap->parse_query (q{ 
   ( "qx[ls]" )
 |-{
     count | ( "localhost" ) |->> ts:fusion( sshp:pool ) => $ssh
 ||><||
     <<- 2 sec | @ $ssh
 }-|->> ts:tap( $tss )

 }, $tm->stack);
	    (my $ss, undef) = TM2::TempleScript::PE::pe2pipe ($ctx, $cpr);
	    $loop->watch_time( after => 4, code => sub { diag "stopping stream " if $warn; push @$ss, bless [], 'ts:collapse'; } );
	    $loop->watch_time( after => 5, code => sub { diag "stopping loop "   if $warn; $loop->stop; } );
	    push @$ss, bless [], 'ts:kickoff';
	}
	$loop->run;
	is_singleton( $ts, undef, $AGENDA.'ssh single');
	like( $ts->[0]->[0]->[0], qr/Download/, $AGENDA.'ls remote');
#warn Dumper $ts; exit;
    }
}


if (DONE) {
    my $AGENDA = q{problems with connections: };

    use IO::Async::Loop;
    my $loop = IO::Async::Loop->new;

    my $ap = new TM2::TempleScript::Parser ();                          # quickly clone a parser

    my $stm = $sen;
    my $tm = _parse (\$stm, q{

%include file:ssh.ts

});

    my $ts = [];

    my $ctx = _mk_ctx ($stm);
    $ctx = [ @$ctx, { '$loop' => $loop, '$ts' => $ts } ];
#--
    @$ts = ();
    if (1) {
	{
	    my $cpr = $ap->parse_query (q{ 
   ( "'XXX';", "'YYY';" ) | zigzag
 |-{
     count | ( "ssh://;ConnectTimeout=1;optional=1@192.168.255.255",
               "localhost" )
           |->> ts:fusion( sshp:pool ) => $ssh
 ||><||
     <<- 4 sec | @ $ssh |->> io:write2log
 }-| demote |->> ts:tap( $ts )

 }, $tm->stack);
	    (my $ss, undef) = TM2::TempleScript::PE::pe2pipe ($ctx, $cpr);
	    $loop->watch_time( after => 4, code => sub { diag "stopping stream " if $warn; push @$ss, bless [], 'ts:collapse'; } );
	    $loop->watch_time( after => 5, code => sub { diag "stopping loop "   if $warn; $loop->stop; } );
	    push @$ss, bless [], 'ts:kickoff';
	}
	$loop->run;
#warn Dumper $ts; exit;
	is_singleton( $ts, undef, $AGENDA.'ssh single, optional');
	my $ts2 = $ts->[0]->[0];
	ok( scalar @$ts2 == 2, $AGENDA.'both went through, optional');
	ok(eq_set ([ map { $_->[0]->[0] } @$ts2 ], [ qw(XXX YYY) ]), $AGENDA.'content, optional');
    }
#--
    @$ts = ();
    if (1) {
	{
	    my $cpr = $ap->parse_query (q{ 
   ( "'XXX';", "'YYY';" ) | zigzag
 |-{
     count | ( "ssh://;ConnectTimeout=1;optional=0@192.168.255.255",
               "localhost" )
           |->> ts:fusion( sshp:pool ) => $ssh
 ||><||
     <<- 2 sec | @ $ssh |->> io:write2log
 }-| demote |->> ts:tap( $ts )

 }, $tm->stack);
	    (my $ss, undef) = TM2::TempleScript::PE::pe2pipe ($ctx, $cpr);
	    $loop->watch_time( after => 4, code => sub { diag "stopping stream " if $warn; push @$ss, bless [], 'ts:collapse'; } );
	    $loop->watch_time( after => 5, code => sub { diag "stopping loop "   if $warn; $loop->stop; } );
	    push @$ss, bless [], 'ts:kickoff';
	}

	throws_ok {
	    $loop->run;
	} qr/escalat/, $AGENDA.'detected connection problem';
	$loop->run;
	diag "not interested in result";
    }
#--
    @$ts = ();
    if (1) {
	{
	    my $cpr = $ap->parse_query (q{ 
   ( "'XXX';", "'YYY';" ) | zigzag
 |-{
     count | ( "ssh://;ConnectTimeout=1;optional=1@192.168.255.255",
               "ssh://;ConnectTimeout=1;optional=1@192.168.255.255",
               "localhost" )
           |->> ts:fusion( sshp:pool ) => $ssh
 ||><||
     <<- 4 sec | @ $ssh |->> io:write2log
 }-| demote |->> ts:tap( $ts )

 }, $tm->stack);
	    (my $ss, undef) = TM2::TempleScript::PE::pe2pipe ($ctx, $cpr);
	    $loop->watch_time( after => 5, code => sub { diag "stopping stream " if $warn; push @$ss, bless [], 'ts:collapse'; } );
	    $loop->watch_time( after => 6, code => sub { diag "stopping loop "   if $warn; $loop->stop; } );
	    push @$ss, bless [], 'ts:kickoff';
	}
	$loop->run;
#warn Dumper $ts; exit;
	is_singleton( $ts, undef, $AGENDA.'ssh single, optionals + one functional');
	my $ts2 = $ts->[0]->[0];
	ok( scalar @$ts2 == 2, $AGENDA.'both went through, optional');
	ok(eq_set ([ map { $_->[0]->[0] } @$ts2 ], [ qw(XXX YYY) ]), $AGENDA.'content, optional');

    }
}

done_testing;

__END__

	throws_ok {
	    $loop->run;
	} qr/all.+gone/, $AGENDA.'detected connection problem';
	$loop->run;
