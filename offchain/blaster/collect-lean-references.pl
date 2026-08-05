#!/usr/bin/env perl
use strict;
use warnings;
use File::Spec;

@ARGV >= 2 or die "usage: collect-lean-references.pl SOURCE_ROOT FILE...\n";
my $root = File::Spec->rel2abs(shift @ARGV);
my %seen;

sub package_for {
    my ($reference) = @_;
    return 'leanBlaster'             if $reference =~ /^Blaster(?:\.|$)/;
    return 'plutusCoreBlaster'       if $reference =~ /^PlutusCore(?:\.|$)/;
    return 'cardanoLedgerApiBlaster' if $reference =~ /^CardanoLedgerApi(?:\.|$)/;
    return;
}

sub emit {
    my ($path, $reference, $kind) = @_;
    my $package = package_for($reference) or return;
    my $relative = File::Spec->abs2rel(File::Spec->rel2abs($path), $root);
    $relative =~ s{\\}{/}g;
    my $source_path = "offchain/blaster/$relative";
    my $key = join "\t", $source_path, $package, $reference;
    $seen{$key} = $kind if !exists $seen{$key} || $kind eq 'module';
}

sub without_comments {
    my ($text) = @_;
    my $clean = '';
    my $depth = 0;
    my $line_comment = 0;
    for (my $i = 0; $i < length($text); ++$i) {
        my $two = substr($text, $i, 2);
        my $char = substr($text, $i, 1);
        if ($line_comment) {
            if ($char eq "\n") {
                $line_comment = 0;
                $clean .= $char;
            } else {
                $clean .= ' ';
            }
        } elsif ($depth > 0) {
            if ($two eq '/-') {
                ++$depth;
                $clean .= '  ';
                ++$i;
            } elsif ($two eq '-/') {
                --$depth;
                $clean .= '  ';
                ++$i;
            } else {
                $clean .= ($char eq "\n" ? "\n" : ' ');
            }
        } elsif ($two eq '--') {
            $line_comment = 1;
            $clean .= '  ';
            ++$i;
        } elsif ($two eq '/-') {
            $depth = 1;
            $clean .= '  ';
            ++$i;
        } else {
            $clean .= $char;
        }
    }
    die "unterminated Lean block comment\n" if $depth != 0;
    return $clean;
}

for my $path (@ARGV) {
    open my $handle, '<', $path or die "cannot read $path: $!\n";
    local $/;
    my $code = without_comments(<$handle>);
    close $handle;

    while ($code =~ /^\s*import\s+((?:Blaster|PlutusCore|CardanoLedgerApi)(?:\.[A-Za-z][A-Za-z0-9_']*)*)/mg) {
        emit($path, $1, 'module');
    }

    while ($code =~ /^\s*open\s+((?:Blaster|PlutusCore|CardanoLedgerApi)(?:\.[A-Za-z][A-Za-z0-9_']*)*)\s*\(([^)]*)\)/mg) {
        my ($namespace, $members) = ($1, $2);
        for my $member ($members =~ /([A-Za-z][A-Za-z0-9_']*(?:\.[A-Za-z][A-Za-z0-9_']*)*)/g) {
            emit($path, "$namespace.$member", 'name');
        }
    }

    while ($code =~ /\b((?:Blaster|PlutusCore|CardanoLedgerApi)(?:\.[A-Za-z][A-Za-z0-9_']*)+)/g) {
        emit($path, $1, 'name');
    }

    # Lean's leading-dot constructor syntax omits the namespace from the
    # source token.  These constructors belong to the pinned Plutus Core
    # BuiltinSemanticsVariant type, so restore that namespace in the audit
    # record rather than silently dropping a live external reference.
    while ($code =~ /(?<![A-Za-z0-9_'])\.(defaultFunSemanticsVariant[A-Z])\b/g) {
        emit(
            $path,
            "PlutusCore.Default.BuiltinSemanticsVariant.$1",
            'name'
        );
    }
}

print "$_\t$seen{$_}\n" for sort keys %seen;
