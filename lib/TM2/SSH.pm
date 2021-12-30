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
write "Perl code" here, then this also implies "shell code", as it is easy to invoke a shell capture
from Perl:

    qx[ls -al]      # also known as "backtick"

Obviously, there are three phases: First open the SSH connection to the remote machine, then execute
one or more Perl code fragments (the results will be delivered back), then let the SSH connection go
away. This is easily achieved with a _junction_:

       ( "qx[ls]" )           # the shell command to be executed
     |-{
         ( "localhost" ) |->> ts:fusion( ssh:pool ) => $ssh
     ||><||                   # signals to TS that the following is not automatically collapsing
         <- 2 sec | @ $ssh
     }-|->> io:write2log

In the above case we use a single string as incoming block. For this block first the SSH connection
will be erected using the `ts:fusion` function. Once that is established that small block is also
pushed into second stage of the junction. It will pass unharmed the `2 seconds` disabler (while
starting it) and will move into the `$ssh` stream handler.

Hereby a single tuple will be interpreted as such, that the first value in the tuple is used as Perl
code, the other values in the tuple as optional arguments. For example,

     ( "open FILE, '>', $_[0]; print FILE $_[1]; close FILE;",
       "foo.txt",
       "Hello, world!" )

or

     ( "unlink", "foo.txt" )

Any result of a single execution will be returned as ONE string, even if it consists of several lines.

The `2 seconds` disabler takes care that the SSH connection is only used for incoming blocks within
these 2 seconds. After this the connection will be shut down, unless another block arrived within
these 2 secs. Any later blocks would open a new connection.

Beware of the default *connection timeout* the binary `ssh` has, as that can be pretty long. If you
ask to connect to a slow machine (or your DNS is slow), then the disabler might kick in earlier,
leading to quite erratic and confusing behaviour. You might want to throw in an SSH option (see
below), such as `ConnectionTimeout=1`.


One can also use TempleScript's mechanism to maintain long-living SSH connections, either by
increasing the scope of the variable `$ssh`; or by not disabling the $ssh stream at all.

If you pass in a block of several tuples into `$ssh`, then the individual tuples will be executed
separately; but the coherence of the block on the outgoing side will be maintained.

## URI Addressing

Naming the target host by itself is a convenient and fast-and-loose way, but occasionally you need
to be more specific about the modalities of the SSH connection to be built. For this reason, we
adopt partially the URI format proposed in [SSH URI draft](https://tools.ietf.org/id/draft-salowey-secsh-uri-00.html]):

   ssh://somehost.org
   ssh://somehost.org:1234
   ssh://someuser@somehost.org

### SSH Options

This also includes all options mentioned in the [SSH man page](https://man.openbsd.org/ssh#o), e.g.

   ssh://someuser;IdentityFile=/home/someuser/.ssh/id.rsa@somehost.org

or even with making explicit the SSH fingerprint to be acceptable:

   ssh://someuser;IdentityFile=/home/someuser/.ssh/id.rsa;FingerprintHash=12:....:34@somehost.org

### Additional Options

* "optional":

  If you throw in "optional=yes" into the list of options, then a failed connection with that
  particular host will *not* result in an exception; TS will just report a line in the log and move
  on.

* "multiplicity":

  If you throw in "multiplicity=3", then 3 separate SSH connections will be created to that
  particular host. Setting this number to "0" is ok per-se, but that will not create any connection,
  unsurprisingly.

  Not that every connection is maintained via a single fork()ed process.




block behaviour

@@@ what happens with errors


ConnectTimeout

Advice: 

(a) either provide password manually
(b) other have .pub and then

ssh://po;IdentityFile=t/po_rsa@localhost

restrict user on target host

po      ALL=(ALL) !ALL
po      ALL=(root) NOPASSWD: /usr/bin/whoami


SSH fingerprinting, add in DNS

option ????

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
