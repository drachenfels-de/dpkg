#!/usr/bin/perl
#
# Options:
#  -v<version>
#   changes since <version>

use strict;
use warnings;

use Dpkg;

push(@INC,$dpkglibdir);
require 'controllib.pl';

our %f;

require 'dpkg-gettext.pl';
textdomain("dpkg-dev");

my $controlfile = 'debian/control';
my $changelogfile = 'debian/changelog';
my $fileslistfile = 'debian/files';
my $since = '';
my %mapkv = (); # XXX: for future use

my @changelog_fields = qw(Source Version Distribution Urgency Maintainer
                          Date Closes Changes);

$progname = "parsechangelog/$progname";


sub version {
    printf _g("Debian %s version %s.\n"), $progname, $version;

    printf _g("
Copyright (C) 1996 Ian Jackson.");
    printf _g("
This is free software; see the GNU General Public Licence version 2 or
later for copying conditions. There is NO warranty.
");
}

sub usage {
    printf _g(
"Usage: %s [<option>]

Options:
  -l<changelog>       use <changelog> as the file name when reporting.
  -v<versionsince>    print changes since <versionsince>.
  -h, --help          print this help message.
      --version       print program version.
"), $progname;
}

while (@ARGV) {
    $_=shift(@ARGV);
    if (m/^-v(.+)$/) {
        $since= $1;
    } elsif (m/^-l(.+)$/) {
        $changelogfile = $1;
    } elsif (m/^-(h|-help)$/) {
        &usage; exit(0);
    } elsif (m/^--version$/) {
        &version; exit(0);
    } else {
        &usageerr(sprintf(_g("unknown option \`%s'"), $_));
    }
}

my %urgencies;
my $i = 1;
grep($urgencies{$_} = $i++, qw(low medium high critical emergency));

my $expect = 'first heading';
my $blanklines;

while (<STDIN>) {
    s/\s*\n$//;
#    printf(STDERR "%-39.39s %-39.39s\n",$expect,$_);
    if (m/^(\w[-+0-9a-z.]*) \(([^\(\) \t]+)\)((\s+[-+0-9a-z.]+)+)\;/i) {
        if ($expect eq 'first heading') {
            $f{'Source'}= $1;
            $f{'Version'}= $2;
            $f{'Distribution'}= $3;
            &error(_g("-v<since> option specifies most recent version")) if
                $2 eq $since;
            $f{'Distribution'} =~ s/^\s+//;
        } elsif ($expect eq 'next heading or eof') {
            last if $2 eq $since;
            $f{'Changes'}.= " .\n";
        } else {
            &clerror(sprintf(_g("found start of entry where expected %s"), $expect));
        }
	my $rhs = $';
	$rhs =~ s/^\s+//;
	my %kvdone;
	for my $kv (split(/\s*,\s*/, $rhs)) {
            $kv =~ m/^([-0-9a-z]+)\=\s*(.*\S)$/i ||
                &clerror(sprintf(_g("bad key-value after \`;': \`%s'"), $kv));
	    my $k = (uc substr($1, 0, 1)).(lc substr($1, 1));
	    my $v = $2;
            $kvdone{$k}++ && &clwarn(sprintf(_g("repeated key-value %s"), $k));
            if ($k eq 'Urgency') {
                $v =~ m/^([-0-9a-z]+)((\s+.*)?)$/i ||
                    &clerror(_g("badly formatted urgency value"));

		my $newurg = lc $1;
		my $oldurg;
		my $newurgn = $urgencies{lc $1};
		my $oldurgn;
		my $newcomment = $2;
		my $oldcomment;

                $newurgn ||
                    &clwarn(sprintf(_g("unknown urgency value %s - comparing very low"), $newurg));
                if (defined($f{'Urgency'})) {
                    $f{'Urgency'} =~ m/^([-0-9a-z]+)((\s+.*)?)$/i ||
                        &internerr(sprintf(_g("urgency >%s<"), $f{'Urgency'}));
                    $oldurg= lc $1;
                    $oldurgn= $urgencies{lc $1}; $oldcomment= $2;
                } else {
                    $oldurgn= -1;
                    $oldcomment= '';
                }
                $f{'Urgency'}=
                    (($newurgn > $oldurgn ? $newurg : $oldurg).
                     $oldcomment.
                     $newcomment);
            } elsif (defined($mapkv{$k})) {
                $f{$mapkv{$k}}= $v;
            } elsif ($k =~ m/^X[BCS]+-/i) {
                # Extensions - XB for putting in Binary,
                # XC for putting in Control, XS for putting in Source
                $f{$k}= $v;
            } else {
                &clwarn(sprintf(_g("unknown key-value key %s - copying to %s"), $k, "XS-$k"));
                $f{"XS-$k"}= $v;
            }
        }
        $expect= 'start of change data'; $blanklines=0;
        $f{'Changes'}.= " $_\n .\n";
    } elsif (m/^\S/) {
        &clerror(_g("badly formatted heading line"));
    } elsif (m/^ \-\- (.*) <(.*)>  ((\w+\,\s*)?\d{1,2}\s+\w+\s+\d{4}\s+\d{1,2}:\d\d:\d\d\s+[-+]\d{4}(\s+\([^\\\(\)]\))?)$/) {
        $expect eq 'more change data or trailer' ||
            &clerror(sprintf(_g("found trailer where expected %s"), $expect));
        $f{'Maintainer'}= "$1 <$2>" unless defined($f{'Maintainer'});
        $f{'Date'}= $3 unless defined($f{'Date'});
#        $f{'Changes'}.= " .\n $_\n";
        $expect= 'next heading or eof';
        last if $since eq '';
    } elsif (m/^ \-\-/) {
        &clerror(_g("badly formatted trailer line"));
    } elsif (m/^\s{2,}\S/) {
        $expect eq 'start of change data' || $expect eq 'more change data or trailer' ||
            &clerror(sprintf(_g("found change data where expected %s"), $expect));
        $f{'Changes'}.= (" .\n"x$blanklines)." $_\n"; $blanklines=0;
        $expect= 'more change data or trailer';
    } elsif (!m/\S/) {
        next if $expect eq 'start of change data' || $expect eq 'next heading or eof';
        $expect eq 'more change data or trailer' ||
            &clerror(sprintf(_g("found blank line where expected %s"), $expect));
        $blanklines++;
    } else {
        &clerror(_g("unrecognised line"));
    }
}

$expect eq 'next heading or eof' || die sprintf(_g("found eof where expected %s"), $expect);

$f{'Changes'} =~ s/\n$//;
$f{'Changes'} =~ s/^/\n/;

my @closes;

while ($f{'Changes'} =~ /closes:\s*(?:bug)?\#?\s?\d+(?:,\s*(?:bug)?\#?\s?\d+)*/ig) {
  push(@closes, $& =~ /\#?\s?(\d+)/g);
}
$f{'Closes'} = join(' ',sort { $a <=> $b} @closes);

set_field_importance(@changelog_fields);
outputclose();

sub clerror
{
    &error(sprintf(_g("%s, at file %s line %d"), $_[0], $changelogfile, $.));
}

sub clwarn
{
    &warn(sprintf(_g("%s, at file %s line %d"), $_[0], $changelogfile, $.));
}

