#!/usr/bin/env perl
use strict;
use warnings;
use List::Util qw(min max);
use Getopt::Long;

my ( $filename, $summary, $verbose );
GetOptions(
            "file|f=s"  => \$filename,
            "summary|s" => \$summary,
            "verbose|v" => \$verbose,
          );
$filename ||= $ARGV[0];
die("Usage: $0 --file <file.dxf> [--summary] [--verbose]\n") unless $filename;

open my $fh, '<', $filename or die "Can't open $filename: $!";

my %entity_count;
my @coords;
my $current_section        = '';
my $expecting_section_name = 0;
my $in_entities            = 0;
my $in_blocks              = 0;
my $block_entities         = 0;
my $prev_code              = '';

while (<$fh>) {
    chomp;
    my $line = $_;

    if ( $prev_code eq '' ) {
        $prev_code = $line;
        next;
    }

    my $code  = $prev_code;
    my $value = $line;
    $prev_code = '';
    $code  =~ s/^\s+|\s+$//g;
    $value =~ s/^\s+|\s+$//g;

    if ( $code eq '0' ) {
        if ( $value eq 'SECTION' ) {
            $expecting_section_name = 1;
            next;
        }

        if ( ( $in_entities || $in_blocks ) && $value ne 'ENDSEC' ) {
            $entity_count{$value}++;
            $block_entities++ if $in_blocks;
        }

        if ( $value eq 'ENDSEC' ) {
            $current_section = '';
            $in_entities     = 0;
            $in_blocks       = 0;
            next;
        }
    }
    elsif ( $code eq '2' && $expecting_section_name ) {
        $current_section        = $value;
        $in_entities            = ( $current_section eq 'ENTITIES' ) ? 1 : 0;
        $in_blocks              = ( $current_section eq 'BLOCKS' )   ? 1 : 0;
        $expecting_section_name = 0;
        next;
    }

    if ( ( $in_entities || $in_blocks ) && $code =~ /^1[01]$|^2[01]$/ ) {
        push @coords, $value if $value =~ /^-?(?:\d+\.?\d*|\.\d+)$/;
    }
}
close $fh;

my ( $min_coord, $max_coord, $spread );
if (@coords) {
    $min_coord = min @coords;
    $max_coord = max @coords;
    $spread    = $max_coord - $min_coord;
}

# Optional: read header EXTMIN/EXTMAX
my ( $extmin_x, $extmax_x );
if ($summary) {
    # inside header summary if ($summary)
    my ( $header_key, $expecting_value );
    open my $fh2, '<', $filename or die "Can't reopen $filename: $!";
    while (<$fh2>) {
        chomp;
        s/^\s+|\s+$//g;
        if ( /^\$EXTMIN$/ || /^\$EXTMAX$/ ) {
            $header_key = $_;
        }
        elsif ( $header_key && $_ eq '10' ) {
            chomp( my $val = <$fh2> );
            $val =~ s/^\s+|\s+$//g;
            if ( $header_key eq '$EXTMIN' ) { $extmin_x = $val; }
            if ( $header_key eq '$EXTMAX' ) { $extmax_x = $val; }
            $header_key = '';
        }
    }
    close $fh2;

}

print "=== Entity Summary ===\n";
for my $ent ( sort { $entity_count{$b} <=> $entity_count{$a} } keys %entity_count ) {
    printf "%-10s : %6d\n", $ent, $entity_count{$ent};
}
print "\nEntities in BLOCKS section: $block_entities\n";

print "\n=== Coordinate Extents ===\n";
if ( defined $spread ) {
    print "Min: $min_coord\n";
    print "Max: $max_coord\n";
    printf "Spread: %.2f units\n", $spread;
    print "\n[!]  Warning: Drawing spans over 10,000 units.\n" if $spread > 10000;
}
else {
    print "No usable coordinate data found.\n";
}

if ($summary) {
    print "\n=== Header Values (from \$EXTMIN and \$EXTMAX) ===\n";
    print "EXTMIN X: $extmin_x\n" if defined $extmin_x;
    print "EXTMAX X: $extmax_x\n" if defined $extmax_x;
}

if ($verbose) {
    printf "\n[DEBUG] Parsed %d coordinates\n", scalar(@coords);
    print "[DEBUG] Last section parsed: $current_section\n";
}
