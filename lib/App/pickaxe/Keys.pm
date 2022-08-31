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
    Curses::KEY_RESIZE    => '<Resize>',
    "^J"                  => '<Return>',
    "^I"                  => '<Tab>',
    "^["                  => '<Esc>',
    ' '                   => '<Space>',
    '\\'                  => '<Backslash>',
);

sub getkey {
    my ($ch, $key) = getchar;
    my $ret;

    if ( defined $key ) {
       if ( exists $table{$key} ) {
            $ret = $table{$key};
       }
       else {
           return;
       }
    }
    elsif( defined $ch ) {
        $ch = unctrl($ch);
        $ret = $table{$ch} || $ch;
    }
    else {
        return;
    }

    if ( $ret eq '<Esc>' ) {
        nodelay( stdscr, 1 );
        my $key = getchar;
        if ($key) {
            $ret .= $table{$key} || $key;
        }
        nodelay( stdscr, 0 );
    }
    return $ret;
}

1;
