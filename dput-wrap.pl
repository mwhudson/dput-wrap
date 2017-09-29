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

my $check_sru_bug_py = '
import sys

from launchpadlib.launchpad import Launchpad

bug_number = int(sys.argv[1])
source_package_name = sys.argv[2]
distro_series_name = sys.argv[3]

lp = Launchpad.login_anonymously("devel")

distro_series = lp.distributions["ubuntu"].getSeries(name_or_version=distro_series_name)

try:
   bug = lp.bugs[bug_number]
except KeyError:
   print("cannot find bug #%s, maybe private?"%bug_number)
   sys.exit(1)

for task in bug.bug_tasks:
    target = task.target
    ds = getattr(target, "distroseries", None)
    if ds != distro_series:
        continue
    if target.name != source_package_name:
        continue
    if task.status not in ["New", "Confirmed", "Triaged"]:
        print("bug %s has task for %s/%s with unsuitable status %s"%(bug_number, distro_series_name, source_package_name, task.status))
        sys.exit(1)
    else:
        # yay, all ok
        sys.exit(0)

print("bug %s has no task for %s/%s"%(bug_number, distro_series_name, source_package_name))
sys.exit(1)
';

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
        if (!defined($c->{"Launchpad-Bugs-Fixed"})) {
            die "$changes does not close a bug\n";
        }
        my $source = $c->{Source};
        foreach my $bug (split /\s+/,$c->{"Launchpad-Bugs-Fixed"}) {
            open(my $fh, "-|", "python", "-c", $check_sru_bug_py, $bug, $source, $distribution);
            my $msg;
            while (<$fh>) {
                $msg .= $_;
            }
            if (!close($fh)) {
                die "$msg";
            }
        }
    }
} elsif ($target =~ /^ppa:/) {
    if (!($version =~ "[+~]ppa")) {
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
