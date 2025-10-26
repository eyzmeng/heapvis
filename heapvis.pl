#!/usr/bin/env perl
use utf8;

package CSAPP::Heap;
use v5.36;
use parent qw(Exporter);
use Carp;

sub new ($class, $size) {
	$size % 4 and croak("bad heap size: $size");
	bless \("\0" x $size), $class
}
sub clone ($heap) {
	my $copy = (ref $heap)->new(length $$heap);
	$$copy = $$heap;
	$copy
}

sub _BBD ($heap, $i) {
	my $n = length($$heap);
	0 <= $$i < $n or croak("segmentation violation: $$i/$n out of bounds");
	$$i % 4 and croak("bus error: $$i is not addressable");
}
sub GET    ($heap, $i)        { use integer; $heap->_BBD(\$i); vec($$heap, $i/4, 32) }
sub SET    ($heap, $i, $word) { use integer; $heap->_BBD(\$i); vec($$heap, $i/4, 32) = $word }
sub GETSIZ ($heap, $i) { GET($heap, $i) & ~07 }
sub ISPLNK ($heap, $i) { (GET($heap, $i) >> 1) & 1 }
sub ISALNK ($heap, $i) { GET($heap, $i) & 1 }
sub SETSIZ ($heap, $i, $size) { SET($heap, $i, (GET($heap, $i) & 07) | ($size & ~07)) }
sub MKPLNK ($heap, $i, $flag) { SET($heap, $i, (GET($heap, $i) &~02) | (!!$flag << 1)) }
sub MKALNK ($heap, $i, $flag) { SET($heap, $i, (GET($heap, $i) &~01) | (!!$flag << 0)) }

sub init ($heap, @chnks)
{
	my ($addr, $size, $pbit, $abit);
	$addr = 0;
	$abit = 0;
	$pbit = 0;
	foreach my $chunk (@chnks) {
		if ($chunk eq 'END') {
			$heap->SET($addr, 1);
			$size = 4;
		}
		elsif ($chunk =~ m!\A([0-9]+)/([01])([01])\z!) {
			($size, $pbit, $abit) = ($1, $2, $3);
			$heap->SETSIZ($addr, $size);
			$heap->MKPLNK($addr, $pbit);
			$heap->MKALNK($addr, $abit);

			# Set footer if free
			if (!$abit) {
				$heap->SET($addr + $size - 4, $size);
			}
		}
		else {
			croak ("bad block spec: $chunk");
		}
	}
	continue { $addr += $size }

	my $caps = length($$heap);
	$size < $caps || carp "not enough: $size/$caps\n";
	$heap
}

#
# address     heap
# meter       block
#
# 18         │     │  busy
#            │     │  (a-bit = 1)
# 14      14 └─────┘
#            ┌ ─ ─ ┐
# 10         ┆     ┆
#            ┆     ┆
# 0c         ┆     ┆
#            ┆     ┆  free
# 08         ┆     ┆  (a-bit = 0)
#            ┆ =16 ┆
# 04      04 └ ─ ─ ┘
#            @@@@@@@
# 00          START 
#
# @><====>@> =======
#
sub tell ($heap, @table)
{
	my @buf;
	my ($addr, $word, $size, $pbit, $abit, $caps);
	my ($wd_addr, $ab_pad);
	my %symbol;

	$caps = length($$heap);
	$addr = 0;
	$pbit = 0;

	# Padding should be 6,5,4,3,2 for address width 2,3,4,5,6
	$wd_addr = length(sprintf "%X", $caps);
	$wd_addr = 2 if $wd_addr < 2;
	$ab_pad = ($wd_addr < 6 ? 8 - $wd_addr : 2);

	# Build symbol table
	%symbol = reverse @table;

	while ($addr < $caps) {
		$size = $heap->GETSIZ($addr);
		if (!$size) {
			if ($addr == 0) {
				push @buf, sprintf "%0${wd_addr}X%${ab_pad}s%${wd_addr}s  START", $addr, '', '';
				push @buf, sprintf "%${wd_addr}s%${ab_pad}s%${wd_addr}s @@@@@@@", '', '', '';
				$addr = $addr + 4;
				$pbit = 1;
				next;
			}
			else {
				push @buf, sprintf "%0${wd_addr}X%${ab_pad}s%${wd_addr}s @@@@@@@", $addr, '', '';
				push @buf, sprintf "%${wd_addr}s%${ab_pad}s%${wd_addr}s   END", '', '', '';
				push @buf, sprintf "%0${wd_addr}X", $addr + 4;
				last;
			}
		}
		my $init = $addr;
		my $STOP = $addr + $size;

		if ($pbit ^ (my $bad = $heap->ISPLNK($init))) {
			carp(sprintf("warning: 0x%02X: p-bit should be %d, but found %d", $addr, $pbit, $bad));
		}
		$abit = $heap->ISALNK($init);
		if (!$abit && (my $bad = $heap->GET($STOP - 4)) != $size) {
			carp(sprintf("warning: 0x%02X: bad footer just before 0x%02X: " .
				"should be %d, but found %d", $addr, $STOP, $size, $bad));
		}

		while ($addr < $STOP) {
			# Print Size/Status
			if ($addr == $init) {
				push @buf, sprintf "%0${wd_addr}X%${ab_pad}s%0${wd_addr}X %s  %d/%d%d",
					$addr, '', $addr, $abit ? '└─────┘' : '└ ─ ─ ┘', $size, $pbit, $abit;
				next;
			}
			if ($addr + 2 == $STOP) {
				push @buf, sprintf "%${wd_addr}s%${ab_pad}s%${wd_addr}s %s",
					'', '', '', '┌─   ─┐';
				next;
			}
			my $vbar = $abit ? '│' : '┆';
			# Print payload address for convenience
			if ($addr == $init + 4) {
				# ALSO, if we happen to equal some guy's memory,
				# now is the time to display them :)
				push @buf, sprintf "%0${wd_addr}X%${ab_pad}s%0${wd_addr}X %s%5s%s%s",
					$addr, '', $addr, $vbar, '', $vbar, exists $symbol{$addr}
						? " =$symbol{$addr}=" : '';
			}
			elsif ($addr % 4) {
				push @buf, sprintf "%${wd_addr}s%${ab_pad}s%${wd_addr}s %s%5s%s",
					'', '', '', $vbar, '', $vbar;
			} else {
				push @buf, sprintf "%0${wd_addr}X%${ab_pad}s%${wd_addr}s %s%5s%s",
					$addr, '', '', $vbar, '', $vbar;
			}
		}
		continue {
			$pbit = $abit;
			$addr = $addr + 2
		}
	}

	reverse @buf;
}

sub alloc ($heap, $need)
{
	$need > 0 or croak "bad alloc size: $need";
	# Round up, for double-word alignment
	my $need_size = ($need + 7) & ~7;

	my ($best_head, $best_size);
	$best_head = 0;


{
	my ($head, $caps, $size, $busy);
	$caps = length($$heap) - 4;

	for ($head = 4; $head < $caps; $head += $size) {
		$size = $heap->GETSIZ($head);
		$busy = $heap->ISALNK($head);

		if (!$busy && $need <= $size) {
			if (!$best_head || $size < $best_size) {
				$best_head = $head;
				$best_size = $size;
			}
		}
	}
}

	$best_head or return 0;

	# Split free block, if needed
{
	my $next_head = $best_head + $best_size;
	if ($need_size < $best_size) {
		my $free_head = $best_head + $need_size;
		my $free_foot = $next_head - 4;
		my $free_size = $best_size - $need_size;

		# Set header
		$heap->SETSIZ($free_head, $free_size);
		$heap->MKALNK($free_head, 0);
		$heap->MKPLNK($free_head, 1);

		# Set footer
		$heap->SET($free_foot, $free_size);
	}
	# The free block was Devoured, so expunge prev link
	else {
		$heap->MKPLNK($next_head, 1);
	}
}

	$heap->SETSIZ($best_head, $need_size);
	$heap->MKALNK($best_head, 1);
	$best_head + 4;
}

#
# Free + immediate coalescence (on homework)
#
sub imfree ($heap, $addr)
{
	my ($free_head, $free_foot, $free_size);
	$heap->ISALNK($free_head = $addr - 4) or croak "Double free";
	$free_size = $heap->GETSIZ($free_head);

{
	my ($head, $size);
	for (
		$head = $free_head + $free_size;
		!$heap->ISALNK($head);
		$head += $size
	) {
		$free_size += ($size = $heap->GETSIZ($head));  # read header
	}

	$free_foot = $head - 4;
	# Destroy prev link from next header
	$heap->MKPLNK($head, 0);

	for (
		$head = $free_head;
		!$heap->ISPLNK($head);
		$head -= $size
	) {
		$free_size += ($size = $heap->GET($head - 4)); # read footer
	}

	$free_head = $head;
}

	$heap->SETSIZ($free_head, $free_size);
	$heap->MKALNK($free_head, 0);
	$heap->SET($free_foot, $free_size);
}

sub free ($heap, $addr)
{
	my ($busy_head, $busy_size, $next_head, $free_foot);
	$busy_head = $addr - 4;
	$heap->ISALNK($busy_head) or croak "Double free";

	$busy_size = $heap->GETSIZ($busy_head);
	$next_head = $busy_head + $busy_size;
	$free_foot = $next_head - 4;

	$heap->MKALNK($busy_head, 0);
	$heap->SET($free_foot, $busy_size);
	$heap->MKPLNK($next_head, 0);
}

sub coalesce ($heap, $addr = 0)
{
	my ($head, $size);

	unless ($addr) {
		my ($caps, $busy);
		$caps = length($$heap);
		for ($head = 4; $head + 4 < $caps; $head += $size) {
			# NOTICE!!!  We grab size only after coalescence
			# is completed; lest we risk stepping into part
			# of a merged freed block.
			$busy = $heap->ISALNK($head);
			$heap->coalesce($head) if !$busy;
			$size = $heap->GETSIZ($head);
		}
		return;
	}

	my ($free_head, $free_foot, $free_size);
	!$heap->ISALNK($addr) or croak("Coalescing a busy block");
	$free_head = $addr;
	$free_size = $heap->GETSIZ($free_head);

	for (
		$head = $free_head + $free_size;
		!$heap->ISALNK($head);
		$head += $size
	) {
		$free_size += ($size = $heap->GETSIZ($head));  # read header
	}

	$free_foot = $head - 4;
	# Destroy prev link from next header
	$heap->MKPLNK($head, 0);

	for (
		$head = $free_head;
		!$heap->ISPLNK($head);
		$head -= $size
	) {
		$free_size += ($size = $heap->GET($head - 4)); # read footer
	}

	$free_head = $head;

	$heap->SETSIZ($free_head, $free_size);
	$heap->MKALNK($free_head, 0);
	$heap->SET($free_foot, $free_size);
}

package main;
use v5.36;
use open ':std', ':encoding(UTF-8)';

sub hexdump {
	open my $dumper, '|od -Ax -tx4z -w16';
	print $dumper ${ +shift };
	close $dumper;
}

my $heap_4a = CSAPP::Heap->new(0xC0)->init(qw(
	END 16/11 32/11 16/11 8/10 56/01 32/10 8/00 16/01 END
));

say "**** 4A UPPER";

{
	my $heap = $heap_4a->clone;
	my @table = ();
	$heap->free(0x50);

	my $p7 = $heap->alloc(18);
	push @table, p7 => $p7;
	print "p7 = alloc(18));\n";
	print sprintf("p7 = 0x_%02x", $p7), "\n";

	my $p8 = $heap->alloc(12);
	push @table, p8 => $p8;
	print "p8 = alloc(18));\n";
	print sprintf("p8 = 0x_%02x", $p7), "\n";

	print +("=" x 80), "\n";
	say for $heap->tell(@table);
	hexdump $heap;
#}

# Wait, we're supposed to re-use the heap???
say "**** 4A LOWER";

#{
#my $heap = $heap_4a->clone;
#my @table = ();

	$heap->coalesce();
	$heap->free(0x38);

	say for $heap->tell(@table);
	hexdump $heap;
}
