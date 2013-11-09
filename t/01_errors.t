use Test::More;
use Test::Exception;

use Test::Dependencies;

throws_ok { all_dependencies_ok('force' => 1, 'cat') }
	qr/Bad options, HASH expected/, 'Bad options detected';

throws_ok { all_dependencies_ok('force' => 1, 'corelist' => 'meh') }
	qr/Bad version passed to 'corelist'/, 'Bad corelist detected';

throws_ok { all_dependencies_ok('force' => 1, 'ignore' => 'meh') }
	qr/Option 'ignore' must be an ARRAYREF/, 'Bad ignore detected';

throws_ok { all_dependencies_ok('force' => 1, 'huh' => 'what') }
	qr/Unknown options:.*huh.*what/ms, 'Unknown options detected';

done_testing;
