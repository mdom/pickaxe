use strict;
use warnings;
use Test::More;
use App::pickaxe::Format;

my $fmt = App::pickaxe::Format->new(
    format     => '%t %a',
    identifier => {
        t => sub { $_[0]->{title} },
        a => sub { $_[0]->{author} },
    },
    cols => 20,
);

is( $fmt->printf( { title => "foo", author => "John Smith" } ),
    "foo John Smith" );
is( $fmt->printf( { title => "A very long title", author => "John Smith" } ),
    "A very long title Jo" );

$fmt = App::pickaxe::Format->new(
    format     => '%t %>  %a',
    identifier => {
        t => sub { $_[0]->{title} },
        a => sub { $_[0]->{author} },
    },
    cols => 60,
);

is(
    $fmt->printf( { title => "A very long title", author => "John Smith" } ),
    "A very long title                                 John Smith"
);

$fmt = App::pickaxe::Format->new(
    format     => '%t %>  %a',
    identifier => {
        t => sub { $_[0]->{title} },
        a => sub { $_[0]->{author} },
    },
    cols => 20,
);
is( $fmt->printf( { title => "A very long title", author => "John Smith" } ),
    "A very long title  J" );

$fmt = App::pickaxe::Format->new(
    format     => '%t %*  %a',
    identifier => {
        t => sub { $_[0]->{title} },
        a => sub { $_[0]->{author} },
    },
    cols => 20,
);
is( $fmt->printf( { title => "A very long title", author => "John Smith" } ),
    "A very lo John Smith" );

done_testing;
