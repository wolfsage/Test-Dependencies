package Test::Dependencies;
# ABSTRACT: Check that dependencies are properly listed

use strict;
use warnings;

use Test::More;
use Test::Pod;

use FindBin qw($Bin);

use CPAN::Meta;
use Module::CoreList;

use File::Spec;
use File::Find;

use Data::Dumper;

use PPI;
use Perl::PrereqScanner;

use Carp qw(croak);
use Cwd;

my $corelist;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(all_dependencies_ok);

sub all_dependencies_ok {
	my ($opt) = @_;

	if ($opt) {
		if ($opt eq 'allow_corelist') {
			$corelist = 1;
		} else {
			croak("Unknown option $opt in import");
		}
	}

	my $rootdir = getcwd;

	my $meta = get_meta($rootdir) or die "Failed to find our meta modules\n";

	my $pre = $meta->effective_prereqs;
	my $req = $pre->merged_requirements();
	my %listed = map { $_ => 1 } $req->required_modules;

	# Find all of our files
	my @files = all_pod_files('.');

	my $scanner = Perl::PrereqScanner->new();

	my %ignore;

	# First, assemble list of our packages
	for my $f (@files) {
		next if $f =~ /\.pod$/; # Skip pod

		# Load a Document from a file
		my $document = PPI::Document->new($f);

		# Get the name of the main package
		my $pkg = eval { $document->find_first('PPI::Statement::Package')->namespace; };
		if ($pkg) {
			$ignore{$pkg} = 1;
		}
	}

	my %done;

	for my $f (@files) {
		next if $f =~ /\.pod$/; # Skip pod

		ok(1, "Checking dependencies from $f");

		my $prereqs = $scanner->scan_file($f);

		for my $req ($prereqs->required_modules) {
			next if $done{$req}++;

			my $ok = $listed{$req} || $ignore{$req};

			my $cl = '';

			# Hmm not found, should we ignore core modules?
			if (!$ok && $corelist) {
				$ok = Module::CoreList->first_release($req);
				$cl = " [corelist]";
			}

			ok($ok, "[$f] Module $req is listed in prereqs$cl");
		}
	}		

	ok(1, "Finished");
}

sub file_from_module {
	my ($mod) = @_;
	$mod =~ s#::|'#/#g;
	$mod .= ".pm";
	return $mod;
}

sub module_from_file {
	my ($file) = @_;
	$file =~ s#/#::#g;
	$file =~ s/\.pm$//;
	return $file;
}

sub get_meta {
	my ($root) = @_;

	if (my @meta = find_mymeta_file($root)) {
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
}

sub find_mymeta_file {
	my ($dir) = @_;

	opendir(my $dhand, $dir) or die "Failed to open $dir: $!\n";

	my @metas = grep { /^MYMETA\./ } readdir($dhand);

	closedir($dhand);

	return @metas;
}

1;
