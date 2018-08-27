#!/usr/bin/perl -w

use strict;

use Dpkg::Control;
use Dpkg::Version;

my @args;
my $target = "ubuntu";
my $changes;
my $dryrun = 0;
my $versioncheck = 1;


foreach my $arg (@ARGV) {
    if ($arg eq '-n') {
        $dryrun = 1;
        next;
    }
    if ($arg eq '--no-version-check') {
        $versioncheck = 0;
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

lp = Launchpad.login_with("sru-scanner", "production", version="devel")

distro_series = lp.distributions["ubuntu"].getSeries(name_or_version=distro_series_name)

try:
   bug = lp.bugs[bug_number]
except KeyError:
   print("cannot find bug #%s, maybe private?"%bug_number)
   sys.exit(1)

found = False
exit_code = 0

if "[regression potential]" not in bug.description.lower():
    print("bug {} does not appear to follow SRU template".format(bug_number))
    exit_code = 1

for task in bug.bug_tasks:
    target = task.target
    ds = getattr(target, "distroseries", None)
    if ds != distro_series:
        continue
    if target.name != source_package_name:
        continue
    found = True
    if task.status not in ["New", "Confirmed", "Triaged", "In Progress"]:
        print("bug %s has task for %s/%s with unsuitable status %s"%(bug_number, distro_series_name, source_package_name, task.status))
        exit_code = 1

if not found:
    print("bug %s has no task for %s/%s"%(bug_number, distro_series_name, source_package_name))
    exit_code = 1

sys.exit(exit_code)
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
        my $source = $c->{Source};
        if ($versioncheck && !($version =~ /[~+.]\Q$codename\E/)) {
            open(my $fh, "-|", "chdist", "apt-cache", $distribution, "madison", $source);
            my @vers;
            while (<$fh>) {
                chomp;
                /Sources$/ || next;
                my $ver = (split /\|/)[1];
                $ver =~ s/^\s+|\s+$//g;
                push @vers, $ver;
            }
            my $firstver = (sort version_compare @vers)[0];
            my $curver = (reverse (sort version_compare @vers))[0];
            my $trailing = $curver;
            $trailing =~ s/.*\.([0-9]+)$/$1/;
            $trailing++;
            my $ok = 0;
            if ($curver eq $firstver && $version eq "$curver.1") {
                $ok = 1;
                print("good version number for first SRU\n");
            }
            if ($curver ne $firstver && $version eq "$firstver.$trailing") {
                $ok = 1;
                print("good version number for subsequent SRU\n");
            }
            if (!$ok) {
                if ($version =~ /([~+.][0-9][0-9]\.[0-9][0-9])/) {
                    die "no [~+]$codename in version for upload targeting $distribution, found $1 though\n";
                } else {
                    die "no [~+]$codename in version for upload targeting $distribution\n";
                }
            }
        }
        if (!defined($c->{"Launchpad-Bugs-Fixed"})) {
            die "$changes does not close a bug\n";
        }
        foreach my $bug (split /\s+/,$c->{"Launchpad-Bugs-Fixed"}) {
            open(my $fh, "-|", "python", "-c", $check_sru_bug_py, $bug, $source, $distribution);
            my $msg;
            while (<$fh>) {
                $msg .= $_;
            }
            if (!close($fh)) {
                print("$msg");
                die "sru bug check failed";
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
