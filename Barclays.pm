package Finance::Bank::Barclays;
use strict;
use warnings;
use Carp;
our $VERSION='0.01';
use LWP::UserAgent;
our $ua=LWP::UserAgent->new(
	env_proxy => 1, 
	keep_alive => 1, 
	timeout => 30,
	cookie_jar=> {},
	agent => "Mozilla/4.0 (compatible; MSIE 5.12; Atari ST)"
); 

sub check_balance {
	my ($class,%opts)=@_;
	croak "Must provide a membership number" unless exists $opts{memnumber};
	croak "Must provide a passcode" unless exists $opts{passcode};
	croak "Must provide a surname" unless exists $opts{surname};
	croak "Must provide a password/memorable word" unless exists $opts{password};

	my $self=bless { %opts }, $class;

	my $page=$ua->get("https://ibank.barclays.co.uk");
	croak "index: ".$page->error_as_HTML unless $page->is_success;

	my $logonurl;
	my @page=split(/\n/,$page->content);
	my @logonline=grep(/log[io]n/i,@page);
	if($#logonline == -1) { croak "Couldn't find logon URL"; }
	if($logonline[0] =~ m/href=\"(\S+)\"/) { $logonurl=$1; }

	$page=$ua->get("https://ibank.barclays.co.uk".$logonurl);
	croak "logon: ".$page->error_as_HTML unless $page->is_success;

	@page=split(/\n/,$page->content);
	my $onlineurl=&getact(grep(/method="POST"/i,@page));

	$page=$ua->post("https://ibank.barclays.co.uk".$onlineurl, {
			action=>"Submit Membership Number",
			servlet=>"startlogin",
			Screen=>"logon",
			membershipNo=>$opts{memnumber}
			});
	croak "first page: ".$page->error_as_HTML unless $page->is_success;

	@page=split(/\n/,$page->content);
	my $posturl=&getact(grep(/method="POST"/i,@page));
	my $startTime=&getval(grep(/name=startTime/,@page));
	my $colourType=&getval(grep(/name=colourType/,@page));
	my $issued=&getval(grep(/name=issued/,@page));
	my $sequence=&getval(grep(/name=sequence/,@page));
	my $servlet=&getval(grep(/name=servlet/,@page));
	my $usec=&getval(grep(/name=usec/,@page));

	my $letter1=0;
	my $letter2=0;
	if($page->content =~ m/Letter\s+(\d).*Letter\s+(\d)/si) {
		$letter1=$1;
		$letter2=$2;
	} else {
		croak "first page: couldn't identify letter numbers";
	}

	$page=$ua->post("https://ibank.barclays.co.uk".$posturl, {
			startTime=>$startTime,
			colourType=>$colourType,
			issued=>$issued,
			sequence=>$sequence,
			servlet=>$servlet,
			usec=>$usec,
			passCode=>$opts{passcode},
			surname=>$opts{surname},
			firstMDC=>substr($opts{password},$letter1-1,1),
			secondMDC=>substr($opts{password},$letter2-1,1),
			action=>"Submit Passcode"
			});
	croak "second page: ".$page->error_as_HTML unless $page->is_success;

	my @sortcodes=();
	my @acnumbers=();
	my @balances=();
	my $line;
	@page=split(/\n/,$page->content);
	foreach $line (@page) {
		if($line =~ m/\s*(\d\d-\d\d-\d\d)\s+(\d+)/) {
			push @sortcodes, $1;
			push @acnumbers, $2;
		} elsif($line =~ m/\<b\>\s*&\#163;([-0-9.]+)\s*\</) {
			push @balances, $1;
		}
	}

	croak "sortcodes and balances don't match (".($#sortcodes+1)."/".($#balances+1).")" unless ($#sortcodes == $#balances);

	my @accounts;
	for(my $i=0; $i<=$#sortcodes; $i++) {
		push @accounts, (bless {
				balance => $balances[$i],
				sort_code => $sortcodes[$i],
				account_no => $acnumbers[$i],
				}, "Finance::Bank::Barclays::Account");
	}
	return @accounts;
}

sub getval {
	my $line=shift;
	if($line =~ m/value="(\S*)"/) {
		return $1;
	} else {
		return "NotFound";
	}
}

sub getact {
	my $line=shift;
	if($line =~ m/action="(\S*)"/) {
		return $1;
	} else {
		return "NotFound";
	}
}


package Finance::Bank::Barclays::Account;

# magic
no strict;
sub AUTOLOAD { my $self=shift; $AUTOLOAD =~ s/.*:://; $self->{$AUTOLOAD} }


1;
__END__
# Below is stub documentation for your module. You better edit it!

=head1 NAME

Finance::Bank::Barclays - Check your Barclays bank accounts from Perl

=head1 SYNOPSIS

  use Finance::Bank::Barclays;
  my @accounts = Finance::Bank::Barclays->check_balance(
	  memnumber => "xxxxxxxxxxxx",
	  passcode => "12345",
	  surname => "Smith",
	  password => "xxxxxxxx"
  );

  foreach (@accounts) {
	  printf "%8s %8s : GBP %8.2f\n",
	  $_->{sort_code}, $_->{account_no}, $_->{balance};
  }

=head1 DESCRIPTION

This module provides a rudimentary interface to the Barclays Online
Banking service at C<https://ibank.barclays.co.uk>. You will need either
C<Crypt::SSLeay> or C<IO::Socket::SSL> installed for HTTPS support to
work with LWP. 

=head1 CLASS METHODS

  check_balance(memnumber => $u, passcode => $p, surname => $s,
    password => $w)

Return an array of account objects, one for each of your bank accounts.

=head1 OBJECT METHODS

  $ac->sort_code
  $ac->account_no

Return the account sort code (in the format XX-YY-ZZ) and the account
number.

  $ac->balance

Return the account balance as a signed floating point value.

=head1 WARNING

This warning is from Simon Cozens' C<Finance::Bank::LloydsTSB>, and seems
just as apt here.

This is code for B<online banking>, and that means B<your money>, and
that means B<BE CAREFUL>. You are encouraged, nay, expected, to audit
the source of this module yourself to reassure yourself that I am not
doing anything untoward with your banking data. This software is useful
to me, but is provided under B<NO GUARANTEE>, explicit or implied.

=head1 THANKS

Simon Cozens for C<Finance::Bank::LloydsTSB> and Perl hand-holding.
Chris Ball for C<Finance::Bank::HSBC>.

=head1 AUTHOR

Dave Holland C<dave@biff.org.uk>

=cut

# vi::ts=4:sw=4:ai:cindent
