#!/usr/bin/env perl
use strict;
use warnings;
use File::Spec;

@ARGV >= 2 or die "usage: collect-lean-references.pl SOURCE_ROOT FILE...\n";
my $root = File::Spec->rel2abs(shift @ARGV);
my %seen_kind;
my %seen_provenance;
my $identifier = qr/[A-Za-z][A-Za-z0-9_']*[!?]?/;

sub reject_unrecognised_constructs {
    my ($path, $code) = @_;

    # A bare upstream `open` lets later unqualified identifiers depend on a
    # pinned package while hiding the members from this inventory.  Selective
    # opens are supported below because their parenthesised member list is an
    # explicit denominator.  Every broader form fails closed instead of
    # silently shrinking the published reference set.
    while ($code =~ /^\s*open\s+((?:Blaster|PlutusCore|CardanoLedgerApi)(?:\.$identifier)*)/mg) {
        my $after_namespace = substr($code, pos($code));
        if ($after_namespace !~ /^\s*\(/) {
            print STDERR "AUDIT-DISCOVERY source_path=$path construct=bare-open outcome=COULD-NOT-EVALUATE layer=reference-discovery\n";
            die "collect-lean-references: unsupported bare upstream open\n";
        }
    }

    if ($code =~ /^\s*open\s+scoped\s+(?:Blaster|PlutusCore|CardanoLedgerApi)(?:\.|\b)/m) {
        print STDERR "AUDIT-DISCOVERY source_path=$path construct=open-scoped outcome=COULD-NOT-EVALUATE layer=reference-discovery\n";
        die "collect-lean-references: unsupported upstream scoped open\n";
    }
    if ($code =~ /^\s*export\s+(?:Blaster|PlutusCore|CardanoLedgerApi)(?:\.|\b)/m) {
        print STDERR "AUDIT-DISCOVERY source_path=$path construct=export outcome=COULD-NOT-EVALUATE layer=reference-discovery\n";
        die "collect-lean-references: unsupported upstream export\n";
    }
}

sub package_for {
    my ($reference) = @_;
    return 'leanBlaster'             if $reference =~ /^Blaster(?:\.|$)/;
    return 'plutusCoreBlaster'       if $reference =~ /^PlutusCore(?:\.|$)/;
    return 'cardanoLedgerApiBlaster' if $reference =~ /^CardanoLedgerApi(?:\.|$)/;
    return;
}

sub emit {
    my ($path, $reference, $kind, $provenance) = @_;
    $provenance //= 'copied';
    my $package = package_for($reference) or return;
    my $relative = File::Spec->abs2rel(File::Spec->rel2abs($path), $root);
    $relative =~ s{\\}{/}g;
    my $source_path = "offchain/blaster/$relative";
    my $key = join "\t", $source_path, $package, $reference;
    my %priority = (name => 1, namespace => 2, module => 3);
    if (!exists $seen_kind{$key} || $priority{$kind} > $priority{$seen_kind{$key}}) {
        $seen_kind{$key} = $kind;
    }
    $seen_provenance{$key} = 'synthesised'
        if $provenance eq 'synthesised';
    $seen_provenance{$key} //= 'copied';
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

    reject_unrecognised_constructs($path, $code);

    while ($code =~ /^\s*import\s+((?:Blaster|PlutusCore|CardanoLedgerApi)(?:\.$identifier)*)/mg) {
        emit($path, $1, 'module');
    }

    while ($code =~ /^\s*open\s+((?:Blaster|PlutusCore|CardanoLedgerApi)(?:\.$identifier)*)\s*\(([^)]*)\)/mg) {
        my ($namespace, $members) = ($1, $2);
        emit($path, $namespace, 'namespace');
        for my $member ($members =~ /($identifier(?:\.$identifier)*)/g) {
            emit($path, "$namespace.$member", 'name');
        }
    }

    while ($code =~ /\b((?:Blaster|PlutusCore|CardanoLedgerApi)(?:\.$identifier)+)/g) {
        emit($path, $1, 'name');
    }

    # Lean's leading-dot constructor syntax omits the namespace from the
    # source token.  These constructors belong to the pinned Plutus Core
    # BuiltinSemanticsVariant type, so restore that namespace in the audit
    # record rather than silently dropping a live external reference.
    while ($code =~ /(?<![A-Za-z0-9_'])\.(defaultFunSemanticsVariant[A-Z])\b/g) {
        emit(
            $path,
            "PlutusCore.Default.Internal.BuiltinSemanticsVariant.$1",
            'name',
            'synthesised'
        );
    }
}

print "$_\t$seen_kind{$_}\t$seen_provenance{$_}\n" for sort keys %seen_kind;
