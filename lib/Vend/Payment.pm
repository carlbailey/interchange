#!/usr/bin/perl
#
# $Id: Payment.pm,v 1.1.2.4 2001-04-10 05:03:39 heins Exp $
#
# Copyright (C) 1996-2000 Red Hat, Inc., http://www.redhat.com
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
# MA  02111-1307  USA.

package Vend::Payment;
require Exporter;

$VERSION = substr(q$Revision: 1.1.2.4 $, 10);

@ISA = qw(Exporter);

@EXPORT = qw(
				charge
				cyber_charge
				charge_param
		);

@EXPORT_OK = qw(
				map_actual
				);

use Vend::Util;
use Vend::Interpolate;
use Vend::Order;
use strict;

my $pay_opt;

my %cyber_remap = (
	qw/
		configfile CYBER_CONFIGFILE
        id         CYBERCASH_ID
        mode       CYBER_MODE
        host       CYBER_HOST
        port       CYBER_PORT
        remap      CYBER_REMAP
        currency   CYBER_CURRENCY
        precision  CYBER_PRECISION
	/
);

sub charge_param {
	my $name = shift;
	my $value = shift;

	if($name =~ s/^mv_payment_//i) {
		$name = lc $name;
	}

	if(defined $value) {
		$pay_opt = {} unless $pay_opt;
		return $pay_opt->{$name} = $value;
	}

	return $pay_opt->{$name}		if defined $pay_opt->{$name};

	my $uname = "MV_PAYMENT_\U$name";

	return $::Variable->{$uname} if defined $::Variable->{$uname};
	return $::Variable->{$cyber_remap{$name}}
		if defined $::Variable->{$cyber_remap{$name}};
	return undef;
}

# Do remapping of payment variables submitted by user
# Can be changed/extended with remap/MV_PAYMENT_REMAP
sub map_actual {
	my ($vref, $cref) = (@_);
	$vref = $::Values		unless $vref;
	$cref = \%CGI::values	unless $cref;
	my %map = qw(
		mv_credit_card_number       mv_credit_card_number
		name                        name
		fname                       fname
		lname                       lname
		b_name                      b_name
		b_fname                     b_fname
		b_lname                     b_lname
		address                     address
		address1                    address1
		address2                    address2
		b_address                   b_address
		b_address1                  b_address1
		b_address2                  b_address2
		city                        city
		b_city                      b_city
		state                       state
		b_state                     b_state
		zip                         zip
		b_zip                       b_zip
		country                     country
		b_country                   b_country
		mv_credit_card_exp_month    mv_credit_card_exp_month
		mv_credit_card_exp_year     mv_credit_card_exp_year
		cyber_mode                  mv_cyber_mode
		phone_day					phone_day
		email						email
		amount                      amount
	);

	# Allow remapping of the variable names
	my $remap;
	if( $remap	= charge_param('remap') ) {
		$remap =~ s/^\s+//;
		$remap =~ s/\s+$//;
		my (%remap) = split /[\s=]+/, $remap;
		for (keys %remap) {
			$map{$_} = $remap{$_};
		}
	}

	my %actual;
	my $key;

	# pick out the right values, need alternate billing address
	# substitution
	foreach $key (keys %map) {
		$actual{$key} = $vref->{$map{$key}} || $cref->{$key}
			and next;
		my $secondary = $key;
		next unless $secondary =~ s/^b_//;
		$actual{$key} = $vref->{$map{$secondary}} || $cref->{$map{$secondary}};
	}
	$actual{name}		 = "$actual{fname} $actual{lname}"
		if $actual{lname};
	$actual{b_name}		 = "$actual{b_fname} $actual{b_lname}"
		if $actual{b_lname};
	if($actual{b_address1}) {
		$actual{b_address} = "$actual{b_address1}";
		$actual{b_address} .=  ", $actual{b_address2}"
			if $actual{b_address2};
	}
	if($actual{address1}) {
		$actual{address} = "$actual{address1}";
		$actual{address} .=  ", $actual{address2}"
			if $actual{address2};
	}

	# Do some standard processing of credit card expirations
	$actual{mv_credit_card_exp_month} =~ s/\D//g;
	$actual{mv_credit_card_exp_month} =~ s/^0+//;
	$actual{mv_credit_card_exp_year} =~ s/\D//g;
	$actual{mv_credit_card_exp_year} =~ s/\d\d(\d\d)/$1/;

	$actual{mv_credit_card_reference} = $actual{mv_credit_card_number} =~ s/\D//g;
	$actual{mv_credit_card_reference} =~ s/^(\d\d).*(\d\d\d\d)$/$1**$2/;

    $actual{mv_credit_card_exp_all} = sprintf(
                                        '%02d/%02d',
                                        $actual{mv_credit_card_exp_month},
                                        $actual{mv_credit_card_exp_year},
                                      );

	$actual{cyber_mode} = charge_param('transaction')
						||	$actual{cyber_mode}
						|| 'mauthcapture';
	
	return %actual;
}

use vars qw/%order_id_check/;

%order_id_check = (
	cybercash => sub {
					my $val = shift;
					# The following characters are illegal in a CyberCash order ID:
					#    : < > = + @ " % = &
					$val =~ tr/:<>=+\@\"\%\&/_/d;
					return $val;
				},
);

sub gen_order_id {
	my $opt = shift || {};
	if( $opt->{order_id}) {
		# do nothing, already set
	}
	elsif($opt->{counter}) {
		$opt->{order_id} = Vend::Interpolate::tag_counter(
						$opt->{counter},
						{ start => $opt->{counter_start} || 100000 },
					);
	}
	else {
		my(@t) = gmtime(time());
		my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = @t;
		$opt->{order_id} = POSIX::strftime("%y%m%d%H%M%S$$", @t);

	}

	if (my $check = $order_id_check{$opt->{gateway}}) {
		$opt->{order_id} = $check->($opt->{order_id});
	}

	return $opt->{order_id};
}

sub charge {
	my ($charge_type, $opt) = @_;

	my $pay_route;

	### We get the payment base information from a route with the
	### same name as $charge_type if it is there
	if($Vend::Cfg->{Route}) {
		$pay_route = $Vend::Cfg->{Route_repository}{$charge_type}
					|| $Vend::Cfg->{Route};
	}
	else {
		$pay_route = {};
	}

	### Then we take any payment options set in &charge, [charge ...],
	### or $Tag->charge

	# $pay_opt is package-scoped but lexical
	$pay_opt = { %$pay_route };
	for(keys %$opt) {
		$pay_opt->{$_} = $opt->{$_};
	}

	# We relocate these to subroutines to standardize

	### Maps the form variable names to the names needed by the routine
	### Standard names are defined ala Interchange or MV4.0x, b_name, lname,
	### etc. with b_varname taking precedence for these. Falls back to lname
	### if the b_lname is not set
	my (%actual) = map_actual();
	$pay_opt->{actual} = \%actual;

	# We relocate this to a subroutine to standardize. Uses the payment
	# counter if there
	my $orderID = gen_order_id($pay_opt);

	### Set up the amounts. The {amount} key will have the currency prepended,
	### ala CyberCash (i.e. "usd 19.95"). {total_cost} has just the cost.

	# Uses the {currency} -> MV_PAYMENT_CURRENCY options if set
	my $currency =  charge_param('currency')
					|| ($Vend::Cfg->{Locale} && $Vend::Cfg->{Locale}{currency_code})
					|| 'usd';

	# Uses the {precision} -> MV_PAYMENT_PRECISION options if set
	my $precision = charge_param('precision') || 2;

	my $amount = $pay_opt->{amount} || Vend::Interpolate::total_cost();
	$amount = round_to_frac_digits($amount, $precision);
	$pay_opt->{total_cost} = $amount;
	$pay_opt->{amount} = "$currency $amount";

	### 
	### Finish setting amounts and currency

	# If we have a previous payment amount, delete it but push it on a stack
	# 
	my $stack = $Vend::Session->{payment_stack} || [];
	delete $Vend::Session->{payment_result}; 
	delete $Vend::Session->{cybercash_result}; ### Deprecated

	# Default to the gateway same as charge type if no gateway specified,
	# and set the gateway in the session for logging on completion
	$pay_opt->{gateway} = $charge_type if ! $opt->{gateway};
	$Vend::Session->{payment_mode} = $pay_opt->{gateway};

	# just convenience
	my $gw = $pay_opt->{gateway};

	# See if we are calling a defined GlobalSub payment mode
	my $sub = $Global::GlobalSub->{$gw};

	# Try our predefined modes
	if (! $sub and defined &{"Vend::Payment::$gw"} ) {
		$sub = \&{"Vend::Payment::$gw"};
	}

	# This is the return from all routines
	my %result;

	if($sub) {
		# Calling a defined GlobalSub payment mode
		# Arguments are the passed option hash (if any) and the route hash
		eval {
			%result = $sub->($pay_opt);
		};
		if($@) {
			my $msg = errmsg(
						"payment routine '%s' returned error: %s",
						$charge_type,
						$@,
			);
			::logError($msg);
			$result{MStatus} = 'died';
			$result{MErrMsg} = $msg;
		}
	}
	elsif($charge_type =~ /^\s*custom\s+(\w+)(?:\s+(.*))?/si) {
		# MV4 and IC4.6.x methods
		my (@args);
		@args = Text::ParseWords::shellwords($2) if $2;
		if(! defined ($sub = $Global::GlobalSub->{$1}) ) {
			::logError("bad custom payment GlobalSub: %s", $1);
			return undef;
		}
		eval {
			%result = $sub->(@args);
		};
		if($@) {
			my $msg = errmsg(
						"payment routine '%s' returned error: %s",
						$charge_type,
						$@,
			);
			::logError($msg);
			$result{MStatus} = $msg;
		}
	}
	elsif (
			$actual{cyber_mode} =~ /^minivend_test(?:_(.*))?/
				or 
			$charge_type =~ /^internal_test(?:[ _]+(.*))?/
		  )
	{

		# Test mode....

		my $status = $1 || charge_param('result') || undef;
		# Interchange test mode
		my %payment = ( %$pay_opt );
		&testSetServer ( %payment );
		%result = testsendmserver(
			$actual{cyber_mode},
			'Order-ID'     => $orderID,
			'Amount'       => $amount,
			'Card-Number'  => $actual{mv_credit_card_number},
			'Card-Name'    => $actual{b_name},
			'Card-Address' => $actual{b_address},
			'Card-City'    => $actual{b_city},
			'Card-State'   => $actual{b_state},
			'Card-Zip'     => $actual{b_zip},
			'Card-Country' => $actual{b_country},
			'Card-Exp'     => $actual{mv_credit_card_exp_all}, 
		);
		$result{MStatus} = $status if defined $status;
	}
	elsif ($Vend::CC3) {
		### Deprecated
		eval {
			%result = cybercash($pay_opt);
		};
		if($@) {
			my $msg = errmsg( "CyberCash died: %s", $@ );
			::logError($msg);
			$result{MStatus} = $msg;
		}
	}
	else {
		my $msg = errmsg("Unknown charge type: %s", $charge_type);
		::logError($msg);
		$result{MStatus} = $msg;
	}

	push @$stack, \%result;
	$Vend::Session->{payment_result} = \%result;
	$Vend::Session->{payment_stack}  = $stack;

	my $svar = charge_param('success_variable') || 'MStatus';
	my $evar = charge_param('error_variable')   || 'MErrMsg';

	if($result{$svar} !~ /^success/) {
		$Vend::Session->{payment_error} = $result{$evar};
		$result{'invalid-order-id'} = delete $result{'order-id'}
			if $result{'order-id'};
	}
	elsif($result{$svar} =~ /success-duplicate/) {
		$Vend::Session->{payment_error} = $result{$evar};
		$result{'invalid-order-id'} = delete $result{'order-id'}
			if $result{'order-id'};
	}
	else {
		delete $Vend::Session->{payment_error};
	}

	$Vend::Session->{payment_id} = $result{'order-id'};

	my $encrypt = charge_param('encrypt');
	$encrypt = 1 unless defined $encrypt;

	if($encrypt) {
		my $prog = charge_param('encrypt_program') || $Vend::Cfg->{EncryptProgram};
		if($prog =~ /pgp|gpg/) {
			local($Vend::Cfg->{Encrypt_program});
			$Vend::Cfg->{Encrypt_program} = $prog;
			$CGI::values{mv_credit_card_force} = 1;
			(
				undef,
				$::Values->{mv_credit_card_info},
				$::Values->{mv_credit_card_exp_month},
				$::Values->{mv_credit_card_exp_year},
				$::Values->{mv_credit_card_exp_all},
				$::Values->{mv_credit_card_type},
				$::Values->{mv_credit_card_error}
			)	= encrypt_standard_cc(\%CGI::values);
		}
	}
	::logError(
				"Order id for charge type %s: %s",
				$charge_type,
				$Vend::Session->{cybercash_id},
			)
		if $pay_opt->{log_to_error};

	# deprecated
	for(qw/ id error result /) {
		$Vend::Session->{"cybercash_$_"} = $Vend::Session->{"payment_$_"};
	}

	return \%result if $pay_opt->{hash};
	return $result{'order-id'};
}

sub testSetServer {
	my %options = @_;
	my $out = '';
	for(sort keys %options) {
		$out .= "$_=$options{$_}\n";
	}
	logError("Test CyberCash SetServer:\n%s\n" , $out);
	1;
}

sub testsendmserver {
	my ($type, %options) = @_;
	my $out ="type=$type\n";
	for(sort keys %options) {
		$out .= "$_=$options{$_}\n";
	}
	logError("Test CyberCash sendmserver:\n$out\n");
	my $oid;
	eval {
		$oid = Vend::Interpolate::tag_counter(
					"$Vend::Cfg->{ScratchDir}/internal_test.payment.number"
					);
	};
	return ('MStatus', 'success', 'order-id', $oid || 'COUNTER_FAILED');
}


# Old, old, old but still supported
*cyber_charge = \&Vend::Payment::charge;

1;
__END__
