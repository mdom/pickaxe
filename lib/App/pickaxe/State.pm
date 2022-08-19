package App::pickaxe::State;
use Mojo::Base -base;

has base_url => sub {
    die "Required parameter 'url' not set.\n";
};

has 'pages';

1;
