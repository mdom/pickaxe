package App::pickaxe::State;
use Mojo::Base -base;


has base_url =>
  sub { Mojo::URL->new('https://example.com/projects/foo/') };


has 'pages';

1;
