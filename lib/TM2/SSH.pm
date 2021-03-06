package TM2::SSH;

use strict;
use warnings;

=head1 NAME

TM2::SSH - TempleScript extension for SSH

=cut

our $VERSION = '0.03';

=pod

=head1 SYNOPSIS

   # not to be used from Perl

=head1 DESCRIPTION

This TempleScript extension provides a vehicle to execute Perl code on a remote machine. When I
write I<Perl code> here, then this also implies I<shell code>, as it is easy to invoke a shell capture
from Perl:

    qx[ls -al]      # also known as "backtick"

Obviously, there are three phases: First open the SSH connection to the remote machine, then execute
one or more Perl code fragments (the results will be delivered back), then let the SSH connection go
away. This is easily achieved with a I<junction>:

       ( "qx[ls]" )           # the shell command to be executed
     |-{
         ( "localhost" ) |->> ts:fusion( sshp:pool ) => $ssh
         ||><||               # signals to TS that the following is not automatically collapsing
         <- 2 sec | @ $ssh
     }-|->> io:write2log

In the above case we use a single string as incoming block. For this block first the SSH connection
will be erected using the C<ts:fusion> function. Once that is established that small block is also
pushed into second stage of the junction. It will pass unharmed the "2 seconds" disabler (while
starting it) and will move into the B<$ssh> stream handler.

Hereby a single tuple will be interpreted as such, that the first value in the tuple is used as Perl
code, the other values in the tuple as optional arguments. For example,

     ( "open FILE, '>', $_[0]; print FILE $_[1]; close FILE;",
       "foo.txt",
       "Hello, world!" )

or

     ( "unlink", "foo.txt" )

Any result of a single execution will be returned as ONE string, even if it consists of several lines.

The "2 seconds" disabler takes care that the SSH connection is only used for incoming blocks within
these 2 seconds. After this the connection will be shut down, unless another block arrived within
these 2 secs. Any later blocks would open a new connection.

Beware of the default B<connection timeout> the binary C<ssh> has, as that can be pretty long. If you
ask to connect to a slow machine (or your DNS is slow), then the disabler might kick in earlier,
leading to quite erratic and confusing behaviour. You might want to throw in an SSH option (see
below), such as C<ConnectionTimeout=1>.

One can also use TempleScript's mechanism to maintain long-living SSH connections, either by
increasing the scope of the variable B<$ssh>; or by not disabling the B<$ssh> stream at all.

=head2 Use Cases

=head3 Have one machine do something

     apt-update isa ts:stream
     return
       <+ every 6 hours +>
     | ( "qx[sudo apt update]" )         # the shell command to be executed
     |-{
         ( "my.server.home" ) |->> ts:fusion( sshp:pool ) => $ssh
         |><|
         <- 60 sec | @ $ssh              # wait for 60 secs to terminate connection
     }-|->> io:write2log

=head3 Use a few servers for processing

     do-computing isa ts:function
     return
       ( "use MachineLearning; relearn(); print q[model updated];" )
     |-{
         ( "server1.home",                        # runs all the time
           "server2.home",                        # runs all the time
           "ssh://;optional=yes@server3.home",    # that might be running, or not
         ) |->> ts:fusion( sshp:pool ) => $ssh
         |><|
         <- 300 sec | @ $ssh
     }-|->> io:write2log

=head2 URI Addressing

Naming the target host by itself is a convenient and fast-and-loose way, but occasionally you need
to be more specific about the modalities of the SSH connection to be built. For this reason, we
adopt partially the URI format proposed in L<SSH URI draft|https://tools.ietf.org/id/draft-salowey-secsh-uri-00.html>:

   ssh://somehost.org
   ssh://somehost.org:1234
   ssh://someuser@somehost.org

=head3 SSH Options

This also includes all options mentioned in the [SSH man page](https://man.openbsd.org/ssh#o), e.g.
as in

   ssh://someuser;IdentityFile=/home/someuser/.ssh/id.rsa@somehost.org

or even with making explicit the SSH fingerprint to be acceptable:

   ssh://someuser;IdentityFile=/home/someuser/.ssh/id.rsa;FingerprintHash=12:....:34@somehost.org

=head3 Options as Topic Attributes

Adding options directly to the URI might provide the sense of urgency; another way is to provide SSH
options as attributes to the C<sshp:pool> topic, or a subclass thereof:

    sshp:pool
    ssh:ConnectTimeout : 3
    sshp:multiplicity  : 4

Anytime an instance of something of this type is generated by the C<fusion> function, all attributes
within the C<ssh> and C<sshp> namespace will be added to the object constructor.

Note, that while merging of these attribute options and direct embedding in the URI works,
overriding does not (yet).

=head2 Host Lists

If you provide a single host or URI to the C<fusion> function, then this host will be the primary
target of the SSH connections to be made later.

It is also possible to provide several hosts:

     ( "host1", "host2", "host3" ) |->> ts:fusion( sshp:pool ) => $ssh

In that case the 3 hosts form a pool and there will be one connection per host. When incoming tuple
blocks arrive at the B<$ssh>, the tuples will be split up evenly (round-robin) among the hosts, and
that concurrently. The order of returned results is not guaranteed (yet) and is undeterministic.

If B<only one> host connection fails, or breaks down during execution, then an exception is
raised. So there is no recovery from that. But:

=head3 Additional Options

With the options below the resilience of the pool can be controlled to some extent:

=over

=item * B<optional>

If you throw in C<optional=yes> into the list of SSH options, then a failed connection with that
particular host will B<not> result in an exception; TempleScript will just report a line in the
log, record internally that connection is being defunct and will push the tuple in question to the
next working connection.

Only if all of the optional connections failed, an exception will be raised.

=item * B<multiplicity>

If you throw in C<multiplicity=3>, then 3 separate SSH connections will be created to that
particular host. Setting this number to C<0> is ok per-se, but that will not create any connection,
unsurprisingly.

=back

=head2 Tuple Blocking

As TempleScript delivers incoming data as tuple blocks, each incoming tuple will be directed into
the I<next> working SSH connection within the pool. At this stage, a simple round-robin mechanism is
used for this. All string output will be combined into one string.

Only if responses for B<all> tuples of the block have arrived, the results are pushed downstream as
one outgoing block.

That way, if you pass in a block of several tuples into B<$ssh>, then the individual tuples will be
executed separately; but the coherence of the block on the outgoing side will be maintained.

=head2 Error Handling

@@@

=head1 HINTS

When you are allowing a program to login automatically into machines with sensitive
data/functionality you may want to take a few precautions:

=over

=item * Use C<authorized_keys> and C<known_hosts>:

Obviously, you do not want to enter the password manually whenever the process tries to open an SSH
connection, so you may L<provision ahead of execution time|https://www.quora.com/What-is-the-difference-between-authorized_keys-and-known_hosts-file-for-SSH>.

=item * Create a dedicated user and C<sudo> it:

To restrict potential harm you should create a dedicated B<remote> user, together with its own
public/private key pair. The secret key you will have to provide in the SSH URI. Here with a user
C<po>:

   ssh://po;IdentityFile=t/po_rsa@localhost

Also wise it is to limit the user's privileges, even if it is supposed to run commands as
C<root>. As inspiration only, take for instance the following I<sudo> declarations which one could
store under C</etc/sudoers.d/>:

   po      ALL=(ALL) !ALL
   po      ALL=(root) NOPASSWD: /usr/bin/whoami

Here the user C<po> can run as C<root>, but only the C<whoami> command.

=item * Fingerprints

When your remote machines are procured automatically then you do not want to trip over the problem
that the SSH server's fingerprint is unknown to the client side. One way to deal with this is to
L<add the fingerprint as DNS record|https://emanuelduss.ch/2014/11/15/ssh-fingerprints-im-dns-hinterlegen-sshfp-record/>
and add the SSH option C<VerifyHostKeyDNS=yes> to the client.

Another option is to retrieve the SSH fingerprint from the server first and use it in the C<FingerprintHash> option.

=back

=head1 AUTHOR

Robert Barta, C<< <rho at devc.at> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2021 Robert Barta.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1; # End of TM2::SSH
