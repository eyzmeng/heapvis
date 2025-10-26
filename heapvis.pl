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
sub tell ($heap)
{
	my @buf;
	my ($addr, $word, $size, $pbit, $abit, $caps);
	my ($wd_addr, $ab_pad);

	$caps = length($$heap);
	$addr = 0;
	$pbit = 0;

	# Padding should be 6,5,4,3,2 for address width 2,3,4,5,6
	$wd_addr = length(sprintf "%X", $caps);
	$wd_addr = 2 if $wd_addr < 2;
	$ab_pad = ($wd_addr < 6 ? 8 - $wd_addr : 2);

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
				push @buf, sprintf "%0${wd_addr}X%${ab_pad}s%0${wd_addr}X %s%5s%s",
					$addr, '', $addr, $vbar, '', $vbar;
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

sub alloc ($heap, $s)
{
}

sub free
{
}

sub coalesce
{
}

package main;
use v5.36;
use open ':std', ':encoding(UTF-8)';

my $heap = CSAPP::Heap->new(0xC0);
$heap->init(qw( END 16/11 32/11 16/11 8/10 56/01 32/10 16/01 8/10 END ));

say for $heap->tell();

say unpack "H*", $$heap;
