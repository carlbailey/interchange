UserTag write-shipping Order file
UserTag write-shipping PosNumber 1
UserTag write-shipping addAttr
UserTag write-shipping Routine <<EOR
sub {
	my ($file, $opt) = @_;
	if(! $file) {
		$file = $Vend::Cfg->{Special}{'shipping.asc'}
			|| Vend::Util::catfile($Vend::Cfg->{ProductDir},'shipping.asc');
	}
	my $lines = $Vend::Cfg->{Shipping_line};
	my @outlines;
	for (@$lines) {
		#    0      1      2      3     4     5       6      7
		# ($mode, $desc, $crit, $min, $max, $cost, $query, $opt) 
		my @line = @$_;
		my $opt = '';
		if (ref($line[7]) =~ /HASH/) {
			$line[7] = ::uneval_it($line[7]);
		}
		push @outlines, \@line;
	}
	rename($file, "$file.bak");
	open(SHIPOUT, ">$file")
		or die errmsg("Can't write shipping to %s: %s", $file, $!);
	for(@outlines) {
		print SHIPOUT join "\t", @$_;
		print SHIPOUT "\n";
	}
	close SHIPOUT;
}
EOR