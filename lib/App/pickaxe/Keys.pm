package App::pickaxe::Keys;
use Mojo::Base 'Exporter', -signatures;
use Curses;

our @EXPORT_OK = ('getkey');

my %table = (
    Curses::KEY_BACKSPACE => '<Backspace>',
    Curses::KEY_LEFT      => '<Left>',
    Curses::KEY_RIGHT     => '<Right>',
    Curses::KEY_UP        => '<Up>',
    Curses::KEY_DOWN      => '<Down>',
    Curses::KEY_END       => '<End>',
    Curses::KEY_HOME      => '<Home>',
    Curses::KEY_NPAGE     => '<PageDown>',
    Curses::KEY_PPAGE     => '<PageUp>',
    "\n"                  => '<Return>',
    ' '                   => '<Space>',
    '\\'                  => '<Backslash>',
);

sub getkey {
    my $key = getchar;
    if ( exists $table{$key} ) {
        $key = $table{$key};
    }
    elsif ( $key eq "" ) {
        nodelay( stdscr, 1 );
        my $mod = getchar;
        if ($mod) {
            $key = '<Esc>' . translate($mod);
        }
        else {
            $key = '<Esc>';
        }
        nodelay( stdscr, 0 );
    }
    else {
        $key = unctrl($key);
    }
    return $key;
}

sub translate ($key) {
    $table{$key} || $key;
}

1;
