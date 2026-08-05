#!/usr/bin/env perl
use strict;
use warnings;
use File::Find;
use File::Spec;

@ARGV == 1 or die "usage: index-lean-declarations.pl SOURCE_ROOT\n";
my $root = File::Spec->rel2abs($ARGV[0]);
-d $root or die "source root is unavailable: $root\n";
my %entries;

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

sub qualify {
    my ($namespace, $name) = @_;
    return $name if $name =~ /^(?:Blaster|PlutusCore|CardanoLedgerApi)(?:\.|$)/;
    return join '.', @$namespace, $name if @$namespace;
    return $name;
}

my @files;
find(
    {
        wanted => sub {
            push @files, $File::Find::name if -f $_ && /\.lean\z/;
        },
        no_chdir => 1,
    },
    $root
);

for my $path (sort @files) {
    my $relative = File::Spec->abs2rel($path, $root);
    $relative =~ s{\\}{/}g;
    (my $module = $relative) =~ s{\.lean\z}{};
    $module =~ s{/}{.}g;
    $entries{"module\t$module"} = 1;
    $entries{"symbol\t$module"} = 1;

    open my $handle, '<', $path or die "cannot read $path: $!\n";
    local $/;
    my $raw = <$handle>;
    my $code = without_comments($raw // '');
    close $handle;

    my @namespace;
    my @blocks;
    my ($container, $container_kind, $container_indent);
    for my $line (split /\n/, $code) {
        my ($leading) = $line =~ /^(\s*)/;
        my $indent = length($leading // '');

        if (defined $container) {
            if ($line =~ /^\s*\|\s*([A-Za-z][A-Za-z0-9_']*)\b/) {
                $entries{"symbol\t" . qualify(\@namespace, "$container.$1")} = 1;
            } elsif (($container_kind eq 'structure' || $container_kind eq 'class')
                && $indent > $container_indent
                && $line =~ /^\s*([A-Za-z][A-Za-z0-9_']*)\s*:/) {
                $entries{"symbol\t" . qualify(\@namespace, "$container.$1")} = 1;
            } elsif ($line =~ /\S/ && $indent <= $container_indent
                && $line !~ /^\s*(?:deriving|where)\b/) {
                undef $container;
                undef $container_kind;
                undef $container_indent;
            }
        }

        if ($line =~ /^\s*namespace\s+([A-Za-z][A-Za-z0-9_']*(?:\.[A-Za-z][A-Za-z0-9_']*)*)\s*$/) {
            my @parts = split /\./, $1;
            my @previous = @namespace;
            if ($1 =~ /^(?:Blaster|PlutusCore|CardanoLedgerApi)(?:\.|$)/) {
                @namespace = @parts;
            } else {
                push @namespace, @parts;
            }
            push @blocks, [ namespace => \@previous ];
            for my $count (1 .. @namespace) {
                $entries{"symbol\t" . join('.', @namespace[0 .. $count - 1])} = 1;
            }
            next;
        }
        if ($line =~ /^\s*(?:section|mutual)\b/) {
            push @blocks, [ other => undef ];
            next;
        }
        if ($line =~ /^\s*end(?:\s+[A-Za-z][A-Za-z0-9_']*)?\s*$/) {
            my $block = pop @blocks;
            @namespace = @{$block->[1]} if $block && $block->[0] eq 'namespace';
            next;
        }

        if ($line =~ /^\s*(?:@\[[^]]+\]\s*)*(?:(?:noncomputable|unsafe|protected|partial)\s+)*(def|abbrev|opaque|theorem|lemma|axiom|constant|structure|class|inductive)\s+([A-Za-z][A-Za-z0-9_']*(?:\.[A-Za-z][A-Za-z0-9_']*)*)\b/) {
            my ($kind, $name) = ($1, $2);
            $entries{"symbol\t" . qualify(\@namespace, $name)} = 1;
            if ($kind eq 'structure' || $kind eq 'class' || $kind eq 'inductive') {
                ($container, $container_kind, $container_indent) = ($name, $kind, $indent);
            }
        }
    }

    # Lean's `export Source (Name ...)` makes each selected declaration
    # available from the namespace owning the module that contains the export.
    # Reproduce that exact aliasing, including constructors nested below an
    # exported inductive type.
    (my $export_target = $module) =~ s/\.[^.]+\z//;
    while ($code =~ /^\s*export\s+([A-Za-z][A-Za-z0-9_']*(?:\.[A-Za-z][A-Za-z0-9_']*)*)\s*\((.*?)\)/msg) {
        my ($source_namespace, $items) = ($1, $2);
        if ($source_namespace !~ /^(?:Blaster|PlutusCore|CardanoLedgerApi)(?:\.|$)/) {
            $source_namespace = "$export_target.$source_namespace";
        }
        for my $item ($items =~ /([A-Za-z][A-Za-z0-9_']*(?:\.[A-Za-z][A-Za-z0-9_']*)*)/g) {
            my $source = "$source_namespace.$item";
            my $target = "$export_target.$item";
            $entries{"symbol\t$target"} = 1;
            my $prefix = "symbol\t$source.";
            for my $entry (keys %entries) {
                next unless index($entry, $prefix) == 0;
                my $suffix = substr($entry, length($prefix));
                $entries{"symbol\t$target.$suffix"} = 1;
            }
        }
    }
}

print "$_\n" for sort keys %entries;
