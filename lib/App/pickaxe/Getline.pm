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

sub getline ( $win, $prompt, $options = {}) {
    my ($lines, $cols);
    getmaxyx($win, $lines, $cols);
    move($win, 0, 0 );
    $buffer = '';
    $cursor = 0;
    clrtoeol;
    addstring($win, $prompt);
    refresh($win);
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

        move( $win, 0 , length($prompt) );
        clrtoeol( $win);
        my $rlcols = $cols - length($prompt) - 1; # -1 extra space for indicator

        my $offset = int( $cursor / $rlcols ) * $rlcols;
        my $x      = substr( $buffer, $offset, $rlcols );
        if ($options->{password} ) {
            $x = '*' x length($x);
        }
        addstring( $win, $x);
        if ( $offset != 0 ) {
            addstring( $win, 0, $cols - 1, '<' );
        }
        elsif ( length($buffer) > $rlcols ) {
            addstring( $win, 0, $cols - 1, '>' );
        }
        chgat( $win, 0, $cursor + length($prompt) - $offset,
            1, A_REVERSE, 0, 0 );

        refresh($win);
    }
    move( $win, 0, 0 );
    clrtoeol($win);
    refresh($win);
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
