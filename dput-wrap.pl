#!/usr/bin/perl -w

use strict;

use Dpkg::Control;

my @args;
my $target = "ubuntu";
my $changes;
my $dryrun = 0;

foreach my $arg (@ARGV) {
    if ($arg eq '-n') {
        $dryrun = 1;
        next;
    }
    push @args, $arg;
    if ($arg =~ /^[^-]/) {
        if (defined($changes)) {
            $target = $changes;
            $changes = $arg;
        } else {
            $changes = $arg;
        }
    }
}

my $c = Dpkg::Control->new(type=>CTRL_FILE_CHANGES);
$c->load($changes);
my $version = $c->{Version};
my $distribution = $c->{Distribution};

if ($target eq "ubuntu") {
    if ($version =~ "ppa") {
        die("ppa version to ubuntu")
    }
    my $devel = qx/ubuntu-distro-info --devel/;
    chomp($devel);
    if ($distribution eq $devel) {
        if ($version =~ /[~+][0-9][0-9]\.[0-9][0-9]/) {
            die("do not upload [~+]XX.YY version to devel\n")
        }
    } else {
        my $codename = qx/ubuntu-distro-info --series=$distribution -r/;
        die "could not find codename for $distribution (mis-spelled?)\n" unless $codename ne '';
        chomp($codename);
        $codename = (split /\s+/, $codename)[0];
        if (!($version =~ /[~+]\Q$codename\E/)) {
            if ($version =~ /([~+][0-9][0-9]\.[0-9][0-9])/) {
                die "no [~+]$codename in version for upload targeting $distribution, found $1 though\n";
            } else {
                die "no [~+]$codename in version for upload targeting $distribution\n";
            }
        }
    }
} elsif ($target =~ /^ppa:/) {
    if (!($target =~ "[+~]ppa")) {
        die "no [+~]ppa in version for ppa\n"
    }
} else { # must be debian!
    if ($version =~ /ubuntu/) {
        die("don't upload ubuntu version to debian\n");
    }
    if ($distribution ne 'unstable' && $distribution ne 'experimental') {
        die("bad distribution $distribution for debian\n");
    }
}
if ($dryrun) {
    exec "/bin/echo", "dput", @args;
} else {
    exec "/usr/bin/dput", @args;
}
