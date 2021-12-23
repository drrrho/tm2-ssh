use strict;
use warnings;

use Test::More;
use Test::Exception;
use Test::Moose;
use TM2::TS::Test;
use TM2::TempleScript::Test;

use Data::Dumper;
$Data::Dumper::Indent = 1;

use constant DONE => 0;

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
    my $AGENDA = q{logging in with different user: };

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
     count | ( "ssh://po;IdentityFile=t/po_rsa@localhost" ) |->> ts:fusion( ssh:pool ) => $ssh
 ||><||
     <<- 6 sec | @ $ssh |->> io:write2log
 }-| demote |->> ts:tap( $tss )

 }, $tm->stack);
	    (my $ss, undef) = TM2::TempleScript::PE::pe2pipe ($ctx, $cpr);
	    $loop->watch_time( after => 7, code => sub { diag "stopping stream " if $warn; push @$ss, bless [], 'ts:collapse'; } );
	    $loop->watch_time( after => 8, code => sub { diag "stopping loop "   if $warn; $loop->stop; } );
	    push @$ss, bless [], 'ts:kickoff';
	}
	$loop->run;
#warn Dumper $ts; # exit;
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
   ( "qx[sudo whoami]", "qx[sudo whoami]" ) | zigzag
 |-{
     count | ( "ssh://po;IdentityFile=t/po_rsa@localhost" ) |->> ts:fusion( ssh:pool ) => $ssh
 ||><||
     <<- 6 sec | @ $ssh |->> io:write2log
 }-| demote |->> ts:tap( $tss )

 }, $tm->stack);
	    (my $ss, undef) = TM2::TempleScript::PE::pe2pipe ($ctx, $cpr);
	    $loop->watch_time( after => 7, code => sub { diag "stopping stream " if $warn; push @$ss, bless [], 'ts:collapse'; } );
	    $loop->watch_time( after => 8, code => sub { diag "stopping loop "   if $warn; $loop->stop; } );
	    push @$ss, bless [], 'ts:kickoff';
	}
	$loop->run;

#warn Dumper $ts; exit;
	is_singleton( $ts, undef, $AGENDA.'ssh single');
	my $ts2 = $ts->[0]->[0];
	ok( scalar @$ts2 == 2, $AGENDA.'both went through');
	ok(eq_array ([ map { $_->[0]->[0] } @$ts2 ], [ 'root
', 'root
' ]), $AGENDA.'content');
    }
#--
    @$ts = ();
    if (1) {
	{
	    my $cpr = $ap->parse_query (q{ 
   ( "qx[sudo lsof]", "qx[sudo whoami]" ) | zigzag
 |-{
     count | ( "ssh://po;IdentityFile=t/po_rsa@localhost" ) |->> ts:fusion( ssh:pool ) => $ssh
 ||><||
     <<- 6 sec | @ $ssh |->> io:write2log
 }-| demote |->> ts:tap( $tss )

 }, $tm->stack);
	    (my $ss, undef) = TM2::TempleScript::PE::pe2pipe ($ctx, $cpr);
	    $loop->watch_time( after => 7, code => sub { diag "stopping stream " if $warn; push @$ss, bless [], 'ts:collapse'; } );
	    $loop->watch_time( after => 8, code => sub { diag "stopping loop "   if $warn; $loop->stop; } );
	    push @$ss, bless [], 'ts:kickoff';
	}
	$loop->run;

#warn Dumper $ts; exit;
	is_singleton( $ts, undef, $AGENDA.'ssh single');
	my $ts2 = $ts->[0]->[0];
	ok( scalar @$ts2 == 2, $AGENDA.'both went through');
	ok(eq_array ([ map { $_->[0]->[0] } @$ts2 ], [ '', 'root
' ]), $AGENDA.'content');
    }
}

if (1||DONE) {
    my $AGENDA = q{multiple connections: };

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
    if (0) {
	{
	    my $cpr = $ap->parse_query (q{ 
  -{
     count | ( "ssh://po;IdentityFile=t/po_rsa;multiplicity=3@localhost" ) |->> ts:fusion( ssh:pool ) => $ssh
 ||><||
     <<- 6 sec | @ $ssh |->> io:write2log
 }-|->> ts:tap( $tss )

 }, $tm->stack);
	    (my $ss, undef) = TM2::TempleScript::PE::pe2pipe ($ctx, $cpr);
	    $loop->watch_time( after => 7, code => sub { diag "stopping stream " if $warn; push @$ss, bless [], 'ts:collapse'; } );
	    $loop->watch_time( after => 8, code => sub { diag "stopping loop "   if $warn; $loop->stop; } );
	    push @$ss, map { [ TM2::Literal->new("\$\$") ] } 0..9;
	}
	$loop->run;
#warn Dumper $ts; #exit;
	my %pids;
	map { $pids{$_}++ } map { $_->[0]->[0] } @$ts;
	is( (scalar keys %pids), 3, $AGENDA.'worked N processes');
	use List::Util qw(sum);
	is( (sum values %pids), 10, $AGENDA.'load distributed');

#	ok(eq_set ([ map { $_->[0]->[0] } @$ts ], [ map { $_ + 0.5 } 0..9 ]), $AGENDA.'content');
    }
#--
    @$ts = ();
    if (1) {
	{
	    my $cpr = $ap->parse_query (q{ 
_1_|-{
       ( "ssh://po;IdentityFile=t/po_rsa@localhost" ) |->> ts:fusion( ssh:pool ) => $ssh
     |><|
       <<- 2 sec | @ $ssh |->> io:write2log
     }-|->> ts:tap( $tss )

 }, $tm->stack);
	    (my $ss, undef) = TM2::TempleScript::PE::pe2pipe ($ctx, $cpr);
	    $loop->watch_time( after => 15, code => sub { diag "stopping stream " if $warn; push @$ss, bless [], 'ts:collapse'; } );
	    $loop->watch_time( after => 16, code => sub { diag "stopping loop "   if $warn; $loop->stop; } );
	    push @$ss, map { [ TM2::Literal->new("\$\$") ] } 0..4;
	}
	$loop->run;
#warn Dumper $ts; #exit;
	my %pids;
	map { $pids{$_}++ } map { $_->[0]->[0] } @$ts;
	is( (scalar keys %pids), 5, $AGENDA.'worked N processes');
	use List::Util qw(sum);
	is( (sum values %pids), 5, $AGENDA.'load distributed');

#	ok(eq_set ([ map { $_->[0]->[0] } @$ts ], [ map { $_ + 0.5 } 0..9 ]), $AGENDA.'content');
    }
}

done_testing;

__END__

