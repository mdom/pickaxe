package App::pickaxe::Getline;
use Mojo::Base -signatures, 'Exporter';
use Curses;

our @EXPORT_OK = qw(getline);

my %getline_bindings = (
    Curses::KEY_BACKSPACE => 'backward_delete_character',
    Curses::KEY_LEFT      => 'backward_char',
    Curses::KEY_RIGHT     => 'forward_char',
    "\cA"                 => 'beginning_of_line',
    "\cE"                 => 'end_of_line',
    "\cD"                 => 'delete_character',
    "\cK"                 => 'kill_line',
    "\cG"                 => 'abort',
    "\n"                  => 'accept_line',
);

my $buffer = '';
my $cursor = 0;
my @history;

sub getline ( $prompt, $options = {}) {
    my ($lines, $cols);
    move($LINES - 1, 0 );
    $buffer = $options->{buffer} || '';
    $cursor = length($buffer) ;
    clrtoeol;
    addstring($prompt);
    addstring($buffer);
    chgat( $LINES - 1, $cursor + length($prompt), 1, A_REVERSE, 0, 0 );
    refresh;
    while (1) {
        my $key = getchar;
        my $funcname = $getline_bindings{$key} || 'self_insert';
        if ( $funcname eq 'accept_line' ) {
            last;
        }
        if ( $funcname eq 'abort' ) {
            $buffer = '';
            last;
        }
        no strict 'refs';
        &$funcname($key);

        move( $LINES - 1, length($prompt) );
        clrtoeol;
        my $rlcols = $COLS - length($prompt) - 1; # -1 extra space for indicator

        my $offset = int( $cursor / $rlcols ) * $rlcols;
        my $x      = substr( $buffer, $offset, $rlcols );
        if ($options->{password} ) {
            $x = '*' x length($x);
        }
        addstring($x);
        if ( $offset != 0 ) {
            addstring(0, $COLS - 1, '<' );
        }
        elsif ( length($buffer) > $rlcols ) {
            addstring( 0, $COLS - 1, '>' );
        }
        chgat( $LINES - 1, $cursor + length($prompt) - $offset, 1, A_REVERSE, 0, 0 );

        refresh;
    }
    move( $LINES - 1, 0 );
    clrtoeol;
    my $subwin = subwin($stdscr, 1, $COLS, $LINES - 1, 0);
    refresh($subwin);
    return $buffer;
}

sub delete_character {
    substr( $buffer, $cursor, 1, '' );
}

sub backward_delete_character {
    if ($cursor) {
        substr( $buffer, $cursor - 1, 1, '' );
        $cursor--;
    }
}

sub self_insert ($key) {
    substr( $buffer, $cursor, 0, $key );
    $cursor++;
}

sub backward_char {
    $cursor-- if $cursor;
}

sub forward_char {
    $cursor++ if $cursor != length($buffer);
}

sub beginning_of_line {
    $cursor = 0;
}

sub end_of_line {
    $cursor = length($buffer);
}

sub kill_line {
    substr( $buffer, $cursor ) = '';
}

sub add_to_history ($buffer) {
    if ($buffer ne '' ) {
        push @history, $buffer;
    }
}



1;
