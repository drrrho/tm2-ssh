package TM2::SSH;

use strict;
use warnings;

=head1 NAME

TM2::SSH - TempleScript extension for SSH

=cut

our $VERSION = '0.02';

=pod

=head1 SYNOPSIS

   # not to be used from Perl

=head1 DESCRIPTION

This TempleScript extension provides a vehicle to execute Perl code on a remote machine. When I write "Perl code" here, then
this also implies "shell code", as it is easy to invoke a shell capture from Perl:

    qx[ls -al]      # also known as "backtick"

Obviously, there are three phases: First open the SSH connection to the remote machine, then execute
one or more Perl code fragments (the results will be delivered back), then let the SSH connection go
away. This is easily achieved with a I<junction>:

       ( "qx[ls]" )           # the shell command to be execute
     |-{
         ( "localhost" ) |->> ts:fusion( ssh:connection ) => $ssh
     ||><||                   # signals to TS that the following is not automatically collapsing
         <- now | @ $ssh
     }-|->> io:write2log

In the above case we use a single string as incoming block. For this block first the SSH connection
will be erected using the C<ts:fusion> function. Once that is established that small block is also
pushed into second stage. It will pass unharmed the C<now> disabler and will move into the C<$ssh>
stream handler.

Hereby a single tuple will be interpreted as such, that the first value is used as Perl code, the
other values of the tuples as optional arguments:

     ( "open FILE, '>', $_[0]; print FILE $_[1]; close FILE;",
       "foo.txt",
       "Hello, world!" )

     ( "unlink", "foo.txt" )

Any result of a single Perl code will be returned as ONE string, even if there are several lines.

The C<now> disabler takes care that the SSH connection is only used for that one incoming block. Any
later blocks would open a new connection. One can use TempleScript's mechanism to maintain
long-living SSH connections, either by increasing the scope of the variable C<$ssh>; or by not
disabling the $ssh stream.

If you pass in a block of several tuples into C<$ssh>, then the individual tuples will be executed
separately; but the coherence of the block on the outgoing side will be maintained.

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
