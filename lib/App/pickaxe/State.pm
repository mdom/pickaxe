package App::pickaxe::State;
use Mojo::Base -base;


has base_url =>
  sub { Mojo::URL->new('https://redmine.hal.taz.de/projects/taz_wiki_edv/') };


has 'pages';

1;
