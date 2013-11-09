package Test::Dependencies;
# ABSTRACT: Test that dependencies are properly listed for your dist

use strict;
use warnings;

use Test::More;

use Test::Pod; # all_pod_files

use CPAN::Meta;
use Module::CoreList;

use PPI;
use Perl::PrereqScanner;

use Carp qw(croak);
use Cwd;

use Data::Dumper;

use version 0.77;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(all_dependencies_ok);

sub all_dependencies_ok {
	if (@_ % 2) {
		croak("Bad options, HASH expected");
	}

	my (%opt) = @_;

	my $corelist;

	# Explicitly ignored files
	my %ignore;

	if ($corelist = delete $opt{corelist}) {
		if (!version::is_lax($corelist)) {
			croak("Bad version passed to 'corelist'");
		}

		$corelist = version->parse($corelist);
	}

	if ($opt{ignore}) {
		if (ref $opt{ignore} ne 'ARRAY') {
			croak("Option 'ignore' must be an ARRAYREF");
		}

		%ignore = map { $_ => 1 } @{ delete $opt{ignore} };	
	}

	# Run as an author test by default unless someone explicitly
	# asks otherwise
	if (! delete $opt{force}) {
		require Test::DescribeMe;
		Test::DescribeMe->import('author');
	}	

	if (%opt) {
		croak("Unknown options: " . Dumper(\%opt));
	}

	my $meta = get_meta(getcwd) or die "Failed to find our meta modules\n";
	my $prereqs = $meta->effective_prereqs;

	my %listed;

	# Track requirements listed for different phases
	for my $phase (qw(configure build test runtime)) {
		my $reqs = $prereqs->requirements_for($phase, 'requires');

		$listed{$phase}{$_} = 1 for $reqs->required_modules;
		$listed{all}{$_} = 1 for $reqs->required_modules;
	}

	# Accumulate configure into build
	$listed{build}{$_} = 1 for keys %{ $listed{configure} };

	# There isn't really a test_requires (it's in build)
	$listed{build}{$_} = 1 for keys %{ $listed{test} };

	# Find all of our files
	my @files = all_pod_files('.');

	# list of our files
	my %our;

	# First, assemble list of our packages to ignore them
	for my $f (@files) {
		next if $f =~ /\.pod$/; # Skip pod

		# Load a Document from a file
		my $document = PPI::Document->new($f);

		# Get the name of the main package
		my $pkg = eval { $document->find_first('PPI::Statement::Package')->namespace; };
		if ($pkg) {
			$our{$pkg} = 1;
		}
	}

	# Scan them!
	my $scanner = Perl::PrereqScanner->new();

	my %done;

	for my $f (@files) {
		next if $f =~ /\.pod$/; # Skip pod

		ok(1, "Checking dependencies from $f");

		my $prereqs = $scanner->scan_file($f);

		for my $req ($prereqs->required_modules) {
			my $ok;
			my $why = '';

			if ($ignore{$req}) {
				$ok = 1;
				$why = ' [ignored]';

			} elsif ($our{$req}) {
				$ok = 1;
				$why = ' [internal dependency]';

			} else {
				my $phase = determine_phase($f);

				if ($phase) {
					next if $done{$phase}{$req}++;

					# set this on success/error if detected phase
					$why = " [listed in correct phase ${phase}_requires]";

					if ($listed{$phase}{$req}) {
						$ok = 1;
					}
				} elsif ($listed{all}{$req}) {
					$ok = 1;
					$why = " [listed as a requirement (could not determine phase)]";
				}
			}

			# Hmm not found, should we ignore core modules?
			if (!$ok && $corelist) {
				next if $done{corelist}{$req}++;

				my $fr = Module::CoreList->first_release($req);

				if ($fr && version->parse($fr) <= $corelist) {
					$ok = 1;
					$why = ' [corelist]';
				}
			}


			ok($ok, "[$f] Module '$req' is listed in prereqs$why");
		}
	}		

	ok(1, "Finished");

	done_testing;
}

sub get_meta {
	my ($root) = @_;

	# Look for MYMETA.* and then see if we can parse at least one of
	# them. These should have been freshly built during the build
	# phase and contain our requirements.
	opendir(my $dhand, $root) or die "Failed to open $root: $!\n";

	my @meta = grep { /^MYMETA\./ } readdir($dhand);

	closedir($dhand);

	my $meta;

	my %errors;

	for my $m (@meta) {
		eval { $meta = CPAN::Meta->load_file($m) };
		if (!$@) {
			return $meta;
		}
		$errors{$m} = $@;
	}

	die "Failed to parse MYMETA files: " . Dumper(\%errors);
}

# Try to guess which phase a file is in. (configure runtime build test)
# Fail? return nothing. This could be better
sub determine_phase {
	my ($f) = @_;

	my $phase;

	if ($f =~ /\.t/) {
		$phase = 'build';

	} elsif ($f =~ /\.p(m|l)/ && $f !~ m#(\.t/|/t/)#) {
		$phase = 'runtime';

	} elsif ($f =~ m#(\.bin/|/bin/)#) {
		$phase = 'runtime';

	} elsif ($f =~ /(Build\.PL|Makefile\.PL)/) {
		$phase = 'configure';
	}

	# Others???

	return $phase;
}

1;
__END__

=head1 NAME

Test::Dependencies - Test that dependencies are properly listed for your dist

=head1 SYNOPSIS

Check that your module lists all external depdencies, including those that are 
part of the Perl core:

  use Test::Dependencies;
  all_dependencies_ok();

Ignore dependencies that are listed as core for version 5.8.8 and above:

  all_dependencies_ok(corelist => '5.8.8');

Ignore specific dependencies:

  all_dependencies_ok(ignore => [qw(Foo Bar::Baz)]);

Force tests to be run (since it only expects to be run as an author test by 
default):

  all_dependencies_ok(force => 1);

=head1 DESCRIPTION

This module provides an author test (by default it will only run if author 
testing was explicitly requested) to CPAN distributions that will check that 
all modules used (detected by L<Perl::PrereqScanner>) in tests, utilities, 
and packages are listed in the distribution's dependencies.

It does this by scanning the distribution directory tree and comparing the 
requested modules to the generated C<MYMETA.*> that were created at build time 
for the distribution being tested.

Note that this does NOT detect minimum version requirements.

=head2 Methods

=head3 all_dependencies_ok

  all_dependencies_ok(%options);

Basic usage is (in some .t on its own):

  use Test::Dependencies;
  all_dependencies_ok();

This will check that B<any> module being loaded B<only by files in the 
distribution> are listed in C<MYMETA.*>, including those that are part of the 
Perl core. (It's good form to list core modules as dependencies as its possible 
they may be evicted in the future.)

The following options may be used to control the behavior:

=over 4

=item B<* force>

  all_dependencies_ok(force => 1);

Set this to true to force the tests to run, even if author testing isn't 
requested. This is almost certainly a bad idea since it's up to the author to 
ensure dependencies are listed properly before putting a dist on CPAN.

=item B<* ignore>

  all_dependencies_ok(ignore => [qw(Some::Module Some::Other::Module)]);

Explicilty ignore failures of certain modules. This is also almost certainly a 
bad idea, but who am I to judge?

=item B<* corelist>

  all_dependencies_ok(corelist => '5.8.8');

This will cause all modules that are listed as being a part of the Perl core 
from 5.8.8 and up. Note that this doesn't presently check whether or not its 
SINCE been deprecated, which is almost certainly a bug. TODO: Fix bug.

The versions can be anything that L<version/"is_lax"> accepts.

=back

=head1 AUTHOR

Matthew Horsfall (alh) - <WolfSage@gmail.com>

=cut
