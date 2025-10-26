#!/usr/bin/env perl

package CSAPP::Heap;
use v5.36;
use parent qw(Exporter);
use Carp;

sub new ($class, $size) { bless \("\0" x $size), $class }

sub _BBD ($heap, $i) {
	my $n = length($$heap);
	0 <= $$i < $n or croak("segmentation violation: $$i/$n out of bounds");
	$$i%4 and croak("bus error: $$i is not addressable");
}
sub GET    ($heap, $i)        { use integer; $heap->_BBD(\$i); vec($$heap, $i/4, 32) }
sub SET    ($heap, $i, $data) { use integer; $heap->_BBD(\$i); vec($$heap, $i/4, 32) = $data }
sub GETSIZ ($heap, $i) { GET($heap, $i) & ~07 }
sub ISPLNK ($heap, $i) { GET($heap, $i) & 02 }
sub ISALNK ($heap, $i) { GET($heap, $i) & 01 }
sub SETSIZ ($heap, $i, $size) { SET($heap, $i, (GET($heap, $i) & 07) | ($size & ~07)) }
sub MKPLNK ($heap, $i, $flag) { SET($heap, $i, (GET($heap, $i) &~02) | (!!$flag << 1)) }
sub MKALNK ($heap, $i, $flag) { SET($heap, $i, (GET($heap, $i) &~01) | (!!$flag << 0)) }

sub init ($heap, @chnks)
{
	my ($addr, $size, $pbit, $abit);
	$addr = 0;
	foreach my $chunk (@chnks) {
		if ($chunk eq 'END') {
			$size = 4;
		}
		elsif ($chunk =~ m!([0-9]+)/([01])([01])!) {
			($size, $pbit, $abit) = ($1, $2, $3);
		}
	}
	continue {
		$heap->SETSIZ($addr, $size);
		$heap->MKPLNK($addr, $pbit);
		$heap->MKALNK($addr, $abit);
		$addr += $size
	}
}

sub tell
{
	my @buf;
	@buf;
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

my $heap = CSAPP::Heap->new(0xC0);
$heap->init(qw( END 16/11 32/11 16/11 8/10 56/01 32/10 16/01 END ));

say for $heap->tell;
